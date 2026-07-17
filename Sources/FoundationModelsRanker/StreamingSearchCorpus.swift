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
//   - `RetrievalEngine` is `Searcher`-specific and stays that way: its
//     `weights`/`preamble`/`candidateLimit`/selection-tier wiring are
//     concerns this actor's mutable-streaming-corpus scope never asked
//     for, and it's `private` to Searcher.swift besides. This actor owns
//     its own, narrower `embedder`/`onDiagnostic` pair directly (below)
//     rather than wrapping `RetrievalEngine` wholesale.
//   - A new type wrapping `SearchCorpus` keeps the actor's *stored state*
//     minimal: it owns exactly the mutable corpus that needs confining,
//     plus the embedder/diagnostic knobs its own `add`/`search` need.
//
// Embedding wiring (^rayd7bq: incremental embed on the streaming add path)
// -- `add(items:)` embeds exactly the items it newly added, once, in a
// single batched call, then stores each vector on `SearchCorpus`'s row for
// that id (`SearchCorpus.setEmbedding(_:forID:ifTextMatches:)`), keyed by
// id rather than positional: `RetrievalEngine.itemEmbeddings`
// (Searcher.swift) is a plain array positionally aligned with `corpus.ids`,
// which is safe only because `Searcher` never mutates its corpus after
// `init`. This corpus appends and evicts continuously, so a parallel array
// would desync the moment either happens; storing the embedding on the row
// instead means it always travels with its item, through `add`/`evict`,
// with nothing to keep in sync. The write is additionally guarded on the
// row's *text* still matching what was embedded (not just liveness), since
// `add`'s embed call is itself async and can race a concurrent remove +
// re-add of the same id -- see `SearchCorpus.setEmbedding(_:forID:
// ifTextMatches:)`'s documentation for the exact race this closes.

/// Actor-confined wrapper around `SearchCorpus` for the producer/consumer
/// concurrency case `SearchCorpus` itself calls out: a producer (e.g. a
/// transcript recorder) appending and evicting items while a consumer
/// (e.g. a search tool) queries, both from arbitrary, unsynchronized
/// tasks.
///
/// **Confinement choice: `actor`**, not a lock or a single dedicated task
/// (see this file's header for why an actor, and why it wraps
/// `SearchCorpus` directly rather than `Searcher`'s `RetrievalEngine` or
/// turning `SearchCorpus` itself into an actor). `remove(ids:)`/
/// `remove(group:)` have no suspension point, so each still runs to
/// completion atomically with respect to every other call on this actor --
/// no data race, and no interleaving partway through, ever.
///
/// `add(items:)`/`search(_:limit:)` do now suspend (^rayd7bq: an `await
/// embedder.embed(_:)` call each), so a concurrent `remove`/`add` *can* run
/// during that gap. What stays true regardless:
/// - `remove`/other `add` calls are still each individually atomic (the
///   invariant above), so `corpus` itself is never torn -- only ever some
///   fully-added, fully-removed state that really existed at one point in
///   this actor's serialized order.
/// - `search(_:limit:)` snapshots `corpus` (a value type -- a cheap,
///   copy-on-write `let`) once, synchronously, before its own suspension,
///   and ranks/resolves every result from that one snapshot throughout --
///   never re-reading the live (possibly since-mutated) `corpus` after
///   resuming. That is "snapshot-at-entry": a query answers with whatever
///   state was complete when its turn came up, not necessarily the very
///   latest write if another mutation is still queued behind it, and never
///   a mix of two different snapshots (which would desync the cosine
///   scores this call computed from `corpus.ids`'s length at the *wrong*
///   moment, tripping `HybridRanker`'s alignment precondition).
/// - `add(items:)` embeds only the ids it itself just added and writes
///   each embedding back by id (`SearchCorpus.setEmbedding(_:forID:
///   ifTextMatches:)`), guarded on the row's text still matching what was
///   embedded -- not merely still being live, since a removed-then-re-added
///   id is live again but under different content. It never re-reads
///   `corpus`'s current ids/documents after resuming, so it has nothing to
///   desync either.
///
/// Every parameter and result here is `Sendable` (`Searchable` requires
/// it, `SelectionMatch` and `Hit` already conform), so every method is
/// safe to call from any task -- Swift 6 strict concurrency enforces it at
/// compile time, and no manual locking is needed anywhere in this type.
public actor StreamingSearchCorpus {
    /// The wrapped corpus, never exposed directly.
    ///
    /// Every read and write goes through this actor's isolated methods
    /// below, which is the entire confinement mechanism: nothing outside
    /// this type ever holds a mutable reference to it, and every access
    /// from inside is already serialized by actor isolation.
    private var corpus: SearchCorpus

    /// Embeds every newly added item's text at add time, and the query at
    /// every `search(_:limit:)` call -- adds the cosine signal to this
    /// corpus's ranking. `nil` (the default) skips cosine entirely and
    /// reports `.embeddingUnavailable` via `onDiagnostic` on every search
    /// (^rayd7bq: incremental embed on the streaming add path, mirroring
    /// `Searcher`'s own embedder degradation).
    private let embedder: (any TextEmbedding)?

    /// Called for every diagnostic this corpus emits (currently only
    /// `.embeddingUnavailable`).
    private let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// Creates an empty streaming corpus, ready to `add(items:)` into.
    ///
    /// - Parameters:
    ///   - embedder: embeds every item `add(items:)` adds, once, at add
    ///     time, and the query at every `search(_:limit:)` call. `nil` (the
    ///     default) skips cosine entirely and reports
    ///     `.embeddingUnavailable` on every search.
    ///   - onDiagnostic: called for every diagnostic this corpus emits.
    ///     Defaults to doing nothing.
    public init(
        embedder: (any TextEmbedding)? = nil,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
    ) {
        corpus = SearchCorpus()
        self.embedder = embedder
        self.onDiagnostic = onDiagnostic
    }

    /// Creates a streaming corpus over `items` -- the batch build, exactly
    /// `SearchCorpus.init(items:)`'s rules (duplicate ids keep the first
    /// occurrence), plus `add(items:)`'s embed-at-add-time economy when
    /// `embedder` is configured: `init(items:embedder:onDiagnostic:)` is
    /// itself just `add(items:)` over an empty corpus, so a batch build
    /// embeds its items exactly as an equivalent sequence of `add(items:)`
    /// calls would.
    ///
    /// - Parameters:
    ///   - items: the items to index.
    ///   - embedder: embeds `items`' text once, here, at construction, and
    ///     every later `add(items:)`/`search(_:limit:)` call. `nil` (the
    ///     default) skips cosine entirely.
    ///   - onDiagnostic: called for every diagnostic this corpus emits.
    ///     Defaults to doing nothing.
    public init<Item: Searchable>(
        items: [Item],
        embedder: (any TextEmbedding)? = nil,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
    ) async {
        corpus = SearchCorpus()
        self.embedder = embedder
        self.onDiagnostic = onDiagnostic
        await add(items: items)
    }

    /// The number of live rows, as of whenever this call's turn comes up
    /// in this actor's serialized order.
    public var count: Int { corpus.count }

    /// Whether this corpus currently has no live rows.
    public var isEmpty: Bool { corpus.isEmpty }

    /// Adds `items`, exactly as `SearchCorpus.add(items:)` -- see that
    /// method's documentation for the precompute and duplicate-id rules --
    /// then, when `embedder` is configured, embeds exactly the items this
    /// call actually added (^rayd7bq: incremental embed on the streaming add
    /// path).
    ///
    /// Every newly added item's text is embedded once, here, in a single
    /// batched `embedder.embed(_:)` call -- never once per item, and never
    /// again later. A duplicate id `SearchCorpus.add(items:)` drops is never
    /// embedded: it was never added, so there is no row to attach an
    /// embedding to. If `items` turns out to add nothing new (every id was
    /// already live), `embedder` isn't called at all.
    ///
    /// A failed embed call (`embedder.embed(_:)` throws, or returns a
    /// mismatched vector count) leaves the newly added rows with no stored
    /// embedding -- graceful degradation, exactly `Searcher`'s own
    /// `embedder`/`itemEmbeddings` handling: the add itself still succeeds,
    /// and the next `search(_:limit:)` call reports `.embeddingUnavailable`
    /// (every live row must carry an embedding for cosine to score any of
    /// them -- see `cosineScores(forQuery:snapshot:)`) rather than throwing
    /// here.
    ///
    /// The embed call is `await`-suspended, so a concurrent `remove`/`add`
    /// for the same id can run before it resolves -- e.g. `"x"` removed and
    /// re-added with different text while `"x"`'s old text is still being
    /// embedded here. The write-back below passes the *captured* text
    /// alongside each vector to `SearchCorpus.setEmbedding(_:forID:
    /// ifTextMatches:)`, which is a no-op unless `id`'s current live text
    /// still equals it -- so a stale vector from that race is dropped
    /// rather than silently attached to the wrong row's text.
    ///
    /// Safe to call from any task: `remove`/`search` never interleave
    /// partway through this call's synchronous portions (only the embed
    /// `await` itself is a real suspension point), and the text guard above
    /// makes the result correct either way.
    ///
    /// - Parameter items: the items to add.
    public func add<Item: Searchable>(items: [Item]) async {
        let addedIDs = corpus.add(items: items)
        guard let embedder, !addedIDs.isEmpty else { return }

        let toEmbed = addedIDs.compactMap { id in corpus.block(forID: id).map { (id: id, text: $0) } }
        guard let vectors = try? await embedder.embed(toEmbed.map(\.text)), vectors.count == toEmbed.count else { return }
        for (entry, vector) in zip(toEmbed, vectors) {
            corpus.setEmbedding(vector, forID: entry.id, ifTextMatches: entry.text)
        }
    }

    /// Removes `ids`' rows, exactly as `SearchCorpus.remove(ids:)`.
    ///
    /// - Parameter ids: the ids to evict; entries for ids that aren't live
    ///   are silently skipped.
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
    /// BM25 + trigram (+ cosine, when `embedder` is configured)
    /// `HybridRanker.topMatches` pipeline `Searcher.Mode.retrieval` uses,
    /// mapped back to verbatim `SelectionMatch`es.
    ///
    /// Embeds `query` at most once, here -- the only text this call ever
    /// embeds; every item's own embedding was already computed at add time
    /// by `add(items:)`.
    ///
    /// Snapshots `corpus` into `snapshot` synchronously, before doing
    /// anything else, and ranks/resolves every result from that one
    /// snapshot alone from then on -- never re-reading the live `corpus`
    /// property once this call's only suspension point (the embed-query
    /// `await` inside `cosineScores(forQuery:snapshot:)`) has run. `corpus`
    /// is a value type, so `snapshot` is a cheap copy-on-write `let`: a
    /// concurrent `add`/`remove` that runs during the suspension mutates the
    /// live `corpus`, never `snapshot`. Without this, `cosineScores`'s
    /// per-document array (built from `snapshot.ids`'s length *before* the
    /// suspension) could otherwise end up scored against `corpus.ids`/
    /// `corpus.documents` read *after* it -- a different, possibly
    /// different-length state -- which would desync the two and trip
    /// `HybridRanker`'s `cosineScores.count == documents.count`
    /// precondition.
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of results to return. Defaults to
    ///     `20`. `limit <= 0` yields an empty result rather than throwing
    ///     or crashing.
    /// - Returns: the fused, `[0, 1]`-normalized matches, best-first.
    public func search(_ query: String, limit: Int = 20) async -> [SelectionMatch] {
        guard limit > 0, !corpus.isEmpty else { return [] }
        let snapshot = corpus
        let scores = await cosineScores(forQuery: query, snapshot: snapshot)
        let hits = HybridRanker.topMatches(
            ids: snapshot.ids, documents: snapshot.documents, query: query, cosineScores: scores, limit: limit
        )
        return hits.map { hit in
            SelectionMatch(id: hit.id, block: snapshot.block(forID: hit.id) ?? "", score: hit.score, signals: hit.signals)
        }
    }

    /// Embeds `query` and scores it against every one of `snapshot`'s live
    /// rows' stored embeddings -- the cosine signal `search(_:limit:)` fuses
    /// in when available.
    ///
    /// Takes `snapshot` (rather than reading the actor's own `corpus`
    /// directly) so every id this scores, and the query-embed call itself,
    /// all resolve against the exact same corpus state `search(_:limit:)`
    /// captured before its suspension -- see that method's documentation.
    ///
    /// Degrades to `nil` (keyword-only for this search) and reports
    /// `.embeddingUnavailable` whenever cosine can't contribute: no
    /// `embedder` configured, some live row in `snapshot` hasn't been
    /// embedded yet (only possible if an earlier `add(items:)`'s embed call
    /// failed -- a completed `add(items:)` always leaves every one of its
    /// new rows embedded when `embedder` is configured and the call
    /// succeeds), or embedding the query itself fails. The embedder/
    /// row-completeness check runs before embedding `query`, so a search
    /// that's already known to be unable to use cosine never pays for a
    /// wasted query-embed call.
    ///
    /// - Parameters:
    ///   - query: the query to embed and score.
    ///   - snapshot: the corpus state to score against -- `search(_:limit:)`'s
    ///     pre-suspension snapshot, not the live `corpus`.
    /// - Returns: one cosine score per `snapshot.documents` entry,
    ///   positionally aligned, or `nil` to skip the cosine signal for this
    ///   search.
    private func cosineScores(forQuery query: String, snapshot: SearchCorpus) async -> [Double]? {
        guard let embedder else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }

        var itemVectors: [[Float]] = []
        itemVectors.reserveCapacity(snapshot.ids.count)
        for id in snapshot.ids {
            guard let vector = snapshot.embedding(forID: id) else {
                onDiagnostic(.embeddingUnavailable)
                return nil
            }
            itemVectors.append(vector)
        }

        guard let queryVector = try? await embedder.embed([query]).first else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }
        return itemVectors.map { CosineScoring.cosineSimilarity(queryVector, $0) }
    }
}
