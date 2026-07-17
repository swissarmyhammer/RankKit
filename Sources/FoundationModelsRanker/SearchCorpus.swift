// New to FoundationModelsRanker -- the queryable corpus behind `Searcher`,
// generalized from the construct-once catalog the facade started with
// (`Searcher`'s own private `ItemCatalog`, which this type replaces) to one
// that also accepts items continuously. CodeContextKit's
// `Sources/CodeContextKit/Search/SearchCorpus.swift` is the name's precedent,
// but not a source to port: that corpus is storage-backed, and this package
// stays storage-free by design (in-memory precompute only) -- persistence,
// when a consumer wants it, is that consumer's concern.
//
// The motivating shape is a corpus fed by a producer rather than assembled by
// a caller: items append one at a time (one per event) and leave in cohorts
// (one per finished session). Rebuild-per-append is the wrong shape for that,
// so both mutations here are additive -- `add(items:)` precomputes only the
// arriving rows, and the removals only drop rows. No surviving row is ever
// re-tokenized or re-trigrammed.

/// The corpus FoundationModelsRanker's ranking pipeline queries: `ids` and
/// `documents`, ready to hand straight to `HybridRanker`, plus the per-id
/// text and summary lookups `SelectionCatalog` requires.
///
/// Mutation is additive in both directions. `add(items:)` precomputes each
/// arriving item's BM25/trigram statistics once, at add time, and appends;
/// `remove(ids:)` and `remove(group:)` drop rows. Neither touches a surviving
/// row's precompute, so a corpus grown by a thousand `add` calls has done
/// exactly the same tokenizing work as one built from the same thousand items
/// in a single batch -- and, because `init(items:)` is itself just
/// `add(items:)` over an empty corpus, ranks identically to it too.
///
/// **BM25 corpus globals are recomputed per query, never cached here.** `idf`
/// and `avgdl` are whole-corpus values, so any cached copy would be wrong the
/// moment a row is added or removed. Rather than maintain one and invalidate
/// it, this corpus stores no global statistics at all: `HybridRanker` builds
/// a `BM25Corpus` from the live `documents` on every query, in the single pass
/// it already makes to score them. That is correct by construction under any
/// interleaving of `add` and `remove` -- there is no stale state to
/// invalidate, because there is no state -- and costs nothing asymptotically,
/// since BM25 scoring is an O(N) pass over `documents` either way. The
/// alternative, an incrementally maintained document-frequency table, would
/// track the corpus's *whole* vocabulary to answer queries that only ever read
/// their own handful of terms, paying memory and per-mutation work for
/// statistics almost none of which is read -- and would add a staleness
/// failure mode where today there is none.
///
/// A value type with no concurrency posture of its own: a producer mutating
/// one while a consumer queries it must confine it (an actor, a lock, or a
/// single task), exactly as for any other `var`.
public struct SearchCorpus: SelectionCatalog, Sendable {
    /// One live row's non-retrieval state. The retrieval state --
    /// tokenized, trigrammed, and BM25-weighted -- lives in the positionally
    /// aligned `documents` entry instead, where `HybridRanker` consumes it
    /// without a per-query rebuild.
    private struct Row: Sendable {
        /// The item's full text: the retrieval body field, and
        /// `block(forId:)`'s answer.
        let text: String

        /// The item's summary: `summaryBlock(forId:)`'s answer, which seeds
        /// the selection prefix.
        let summary: String

        /// The item's eviction group, or `nil` for an ungrouped row that no
        /// `remove(group:)` can evict.
        let group: String?
    }

    /// This corpus's ids, in add order -- first-occurrence-id-wins, so a
    /// duplicate id is never a crash and never a silent overwrite.
    ///
    /// Positionally aligned with `documents`: the pair is exactly
    /// `HybridRanker`'s `ids:`/`documents:` arguments.
    public private(set) var ids: [String]

    /// One precomputed `RankedDocument` per `ids` entry, positionally
    /// aligned -- the BM25/trigram statistics `HybridRanker` scores, computed
    /// once at add time and never recomputed while the row lives.
    public private(set) var documents: [RankedDocument]

    /// id -> the row's text, summary, and group. Keyed rather than
    /// positional, so `block(forId:)`/`summaryBlock(forId:)` stay O(1) as the
    /// corpus streams.
    private var rows: [String: Row]

    /// The number of live rows.
    public var count: Int { ids.count }

    /// Whether this corpus has no live rows -- a query against it returns
    /// nothing rather than failing.
    public var isEmpty: Bool { ids.isEmpty }

    /// Creates an empty corpus, ready to `add(items:)` into.
    public init() {
        ids = []
        documents = []
        rows = [:]
    }

    /// Creates a corpus over `items` -- the batch build, which is exactly
    /// `add(items:)` over an empty corpus and therefore shares its
    /// preprocessing verbatim.
    ///
    /// - Parameter items: the items to index. Duplicate ids keep the first
    ///   occurrence; later ones are dropped.
    public init<Item: Searchable>(items: [Item]) {
        self.init()
        add(items: items)
    }

    /// Adds `items` to this corpus, precomputing each one's BM25/trigram
    /// statistics as it arrives and appending it after the existing rows.
    ///
    /// Purely additive: no surviving row is re-tokenized, re-trigrammed, or
    /// reordered, and no corpus-global statistic is recomputed (there are
    /// none to recompute -- see this type's documentation). Cost is
    /// proportional to `items`, not to the corpus.
    ///
    /// An item whose id is already live is **dropped**, not merged and not
    /// overwritten -- the same first-occurrence-id-wins rule `init(items:)`
    /// applies within one batch, extended across calls. Re-adding an id that
    /// was previously removed is not a duplicate: it appends a fresh row at
    /// the end.
    ///
    /// - Parameter items: the items to add.
    public mutating func add<Item: Searchable>(items: [Item]) {
        ids.reserveCapacity(ids.count + items.count)
        documents.reserveCapacity(documents.count + items.count)
        rows.reserveCapacity(rows.count + items.count)
        for item in items {
            guard rows[item.id] == nil else { continue }
            rows[item.id] = Row(text: item.text, summary: item.summary, group: item.group)
            ids.append(item.id)
            documents.append(RankedDocument(primaryText: item.id, bodyText: item.text))
        }
    }

    /// Removes `ids`' rows from this corpus. Ids that aren't live are
    /// ignored.
    ///
    /// - Parameter ids: the ids to evict.
    public mutating func remove(ids removedIds: [String]) {
        evict(ids: Set(removedIds))
    }

    /// Removes every row in `group` -- the cohort eviction a streaming
    /// producer ends a session with, in one call.
    ///
    /// Only matches rows added with that exact group: an ungrouped row
    /// (`Searchable.group == nil`) belongs to no group and is never evicted
    /// here. An unknown group evicts nothing.
    ///
    /// - Parameter group: the group to evict.
    public mutating func remove(group: String) {
        evict(ids: Set(ids.filter { rows[$0]?.group == group }))
    }

    /// Drops `removedIds`' rows, compacting `ids` and `documents` together
    /// in one pass so they stay positionally aligned -- the single removal
    /// path both `remove(ids:)` and `remove(group:)` resolve to, differing
    /// only in how they choose the set.
    ///
    /// - Parameter removedIds: the ids to drop. Ids that aren't live are
    ///   ignored.
    private mutating func evict(ids removedIds: Set<String>) {
        guard !removedIds.isEmpty else { return }

        var survivingIds: [String] = []
        var survivingDocuments: [RankedDocument] = []
        survivingIds.reserveCapacity(ids.count)
        survivingDocuments.reserveCapacity(documents.count)
        for (index, id) in ids.enumerated() where !removedIds.contains(id) {
            survivingIds.append(id)
            survivingDocuments.append(documents[index])
        }

        ids = survivingIds
        documents = survivingDocuments
        for id in removedIds {
            rows[id] = nil
        }
    }

    /// `id`'s summary -- the `SelectionCatalog` lookup that seeds a selection
    /// tier's assembled prefix. O(1) however large the corpus has streamed.
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's summary text, or `nil` if no row with that id is
    ///   live -- an id never added, or one since removed.
    public func summaryBlock(forId id: String) -> String? { rows[id]?.summary }

    /// `id`'s full, verbatim text -- the `SelectionCatalog` lookup a
    /// model-selected id resolves to as a result payload. O(1) however large
    /// the corpus has streamed.
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's full text, or `nil` if no row with that id is live
    ///   -- an id never added, or one since removed.
    public func block(forId id: String) -> String? { rows[id]?.text }
}
