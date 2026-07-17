// New to FoundationModelsRanker (^c79yg0f) -- actor confinement for the
// mutable streaming corpus. `SearchCorpus` (SearchCorpus.swift) documents
// itself as "a value type with no concurrency posture of its own: a
// producer mutating one while a consumer queries it must confine it (an
// actor, a lock, or a single task)"; this type is that confinement,
// actor-shaped, for the motivating case both files describe: a recorder
// appending/evicting transcript entries while a search tool queries, from
// arbitrary, unsynchronized tasks.
//
// Family precedent for the shape (an actor holding a mutable value type as
// a `var`, swapped/mutated in place, never exposed directly):
// FoundationModelsMetadataRegistry's `MetadataSearcher`
// (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`) holds
// its `MetadataIndex` exactly this way for its own hot-reload case.
//
// Design choice -- wraps `SearchCorpus` directly, not `Searcher`'s private
// `RetrievalEngine`, and is not `SearchCorpus` itself turned into an actor:
//   - `SearchCorpus` itself stays a plain value type. Its existing API
//     (synchronous property access, direct construction, the equivalence
//     tests in SearchCorpusTests.swift driving it through `HybridRanker`
//     synchronously) is load-bearing for `Searcher`'s fixed-corpus,
//     never-mutated-after-init use, which has no concurrency problem to
//     solve and would gain nothing from `await` on every access.
//   - `RetrievalEngine` is `Searcher`-specific: it bundles an `embedder`,
//     fusion `weights`, and an `onDiagnostic` callback alongside the
//     corpus -- concerns this task's mutable-streaming-corpus scope never
//     asked for. Wrapping it would drag those knobs along for no reason
//     and couple this actor to `Searcher`'s internals (`RetrievalEngine`
//     is `private`).
//   - A new type wrapping `SearchCorpus` keeps the actor minimal: it owns
//     exactly the mutable state that needs confining and exposes exactly
//     the `add`/`remove`/`search` surface a producer/consumer pair needs.
//     A caller who also wants cosine scoring or diagnostics on a streaming
//     corpus composes a `Searcher`-like facade over this actor, the same
//     way `Searcher` composes `RetrievalEngine` over a fixed `SearchCorpus`.

/// Actor-confined wrapper around `SearchCorpus` for the producer/consumer
/// concurrency case `SearchCorpus` itself calls out: a producer (e.g. a
/// transcript recorder) appending and evicting items while a consumer
/// (e.g. a search tool) queries, both from arbitrary, unsynchronized
/// tasks.
///
/// **Confinement choice: `actor`**, not a lock or a single dedicated task
/// (see this file's header for why an actor, and why it wraps
/// `SearchCorpus` directly rather than `Searcher`'s `RetrievalEngine` or
/// turning `SearchCorpus` itself into an actor). Every `add`/`remove`/
/// `search` call below is a message serialized onto this actor's
/// isolation domain, and none of their bodies contains a suspension point
/// (no `await` inside `add`, `remove`, or `search`) -- so each call runs
/// to completion atomically with respect to every other call on this
/// actor, not merely without data corruption:
/// - Two concurrent `add(items:)` calls (or an `add` racing a `remove`)
///   never interleave partway through; each completes, in some total
///   order, before the next begins.
/// - `search(_:limit:)` therefore always ranks a **complete** snapshot of
///   `corpus` -- some fully-added, fully-removed state that really existed
///   at one point in this actor's serialized call order -- never a torn
///   state where `ids` has grown but the matching row/document hasn't
///   landed yet, or vice versa. That is "snapshot-at-entry": a query
///   answers with whatever state was complete when its turn came up, not
///   necessarily the very latest write if another mutation is still
///   queued behind it.
///
/// Every parameter and result here is `Sendable` (`Searchable` requires
/// it, `SelectionMatch` and `Hit` already conform), so every method is
/// safe to call from any task -- Swift 6 strict concurrency enforces it at
/// compile time, and no manual locking is needed anywhere in this type.
public actor StreamingSearchCorpus {
    /// The wrapped corpus. Never exposed directly -- every read and write
    /// goes through this actor's isolated methods below, which is the
    /// entire confinement mechanism: nothing outside this type ever holds
    /// a mutable reference to it, and every access from inside is already
    /// serialized by actor isolation.
    private var corpus: SearchCorpus

    /// Creates an empty streaming corpus, ready to `add(items:)` into.
    public init() {
        corpus = SearchCorpus()
    }

    /// Creates a streaming corpus over `items` -- the batch build, exactly
    /// `SearchCorpus.init(items:)`'s rules (duplicate ids keep the first
    /// occurrence).
    ///
    /// - Parameter items: the items to index.
    public init<Item: Searchable>(items: [Item]) {
        corpus = SearchCorpus(items: items)
    }

    /// The number of live rows, as of whenever this call's turn comes up
    /// in this actor's serialized order.
    public var count: Int { corpus.count }

    /// Whether this corpus currently has no live rows.
    public var isEmpty: Bool { corpus.isEmpty }

    /// Adds `items`, exactly as `SearchCorpus.add(items:)` -- see that
    /// method's documentation for the precompute and duplicate-id rules.
    /// Safe to call from any task: this call and every other `add`/
    /// `remove`/`search` on this actor serialize against each other, so it
    /// always completes before the next one starts.
    ///
    /// - Parameter items: the items to add.
    public func add<Item: Searchable>(items: [Item]) {
        corpus.add(items: items)
    }

    /// Removes `ids`' rows, exactly as `SearchCorpus.remove(ids:)`.
    ///
    /// - Parameter ids: the ids to evict. IDs that aren't live are
    ///   ignored.
    public func remove(ids: [String]) {
        corpus.remove(ids: ids)
    }

    /// Removes every row in `group`, exactly as `SearchCorpus
    /// .remove(group:)` -- the cohort eviction a streaming producer ends a
    /// session with, in one call.
    ///
    /// - Parameter group: the group to evict.
    public func remove(group: String) {
        corpus.remove(group: group)
    }

    /// `id`'s verbatim full text, or `nil` if no row with that id is live.
    ///
    /// - Parameter id: the id to look up.
    public func block(forID id: String) -> String? {
        corpus.block(forID: id)
    }

    /// `id`'s summary, or `nil` if no row with that id is live.
    ///
    /// - Parameter id: the id to look up.
    public func summaryBlock(forID id: String) -> String? {
        corpus.summaryBlock(forID: id)
    }

    /// Ranks this corpus's current snapshot for `query` -- the same fused
    /// BM25 + trigram `HybridRanker.topMatches` pipeline `Searcher
    /// .Mode.retrieval` uses (no cosine signal: this type has no
    /// `embedder`, per this file's header), mapped back to verbatim
    /// `SelectionMatch`es.
    ///
    /// Because this method has no suspension point, the ids ranked, the
    /// documents scored, and the blocks resolved all come from the exact
    /// same corpus snapshot -- never a state a concurrent `add`/`remove`
    /// is partway through writing.
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of results to return. Defaults to
    ///     `20`. `limit <= 0` yields an empty result rather than throwing
    ///     or crashing.
    /// - Returns: the fused, `[0, 1]`-normalized matches, best-first.
    public func search(_ query: String, limit: Int = 20) -> [SelectionMatch] {
        guard limit > 0, !corpus.isEmpty else { return [] }
        let hits = HybridRanker.topMatches(ids: corpus.ids, documents: corpus.documents, query: query, limit: limit)
        return hits.map { hit in
            SelectionMatch(id: hit.id, block: corpus.block(forID: hit.id) ?? "", score: hit.score, signals: hit.signals)
        }
    }
}
