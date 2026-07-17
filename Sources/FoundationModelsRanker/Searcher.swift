// New to FoundationModelsRanker (plan.md §3a, §6 phase 3) -- the package's one-call facade:
// composes the phase-2 `HybridRanker` (retrieval: BM25 + trigram + optional
// cosine, fused by RRF) with the phase-3 `SelectionTier` (agent final
// selection) over an in-memory `SelectionCatalog` built from the caller's
// `Searchable` items. No source file to port -- neither CodeContextKit nor
// FoundationModelsMetadataRegistry ships a facade this shape; FMR's own
// `MetadataSearcher` is the closest structural precedent (its `Weights`,
// `SearchMode`, `SelectionTierUnavailable`, and retrieval/selection/auto
// dispatch, `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`
// + `SearchMode.swift`), generalized here from a generic `Item:
// SearchableMetadata` index to FoundationModelsRanker's narrower `Searchable`/
// `SelectionCatalog` seams, and from an actor (FMR's index is mutable,
// hot-reloadable) to a plain value type (`Searcher`'s catalog is fixed for
// its lifetime -- no hot reload in this facade).
//
// SDK finding (plan.md §7 risk, carried from the `LanguageModelSession:
// AgentSession` conformance task, ^2gk4k4r, and documented at length in
// `Selection/LanguageModelSessionSupport.swift`): the installed Xcode-beta
// macOS 27 SDK's `FoundationModels.swiftinterface` exposes only
// `SystemLanguageModel.default`, not `.fast` as plan.md §3a's "shipped
// default" guidance describes ("the on-device system model's `.fast`
// variant -- guidance, not a requirement"). This facade's zero-config
// default session factory therefore uses `.default` in `.fast`'s place;
// nothing here assumes `.fast` exists, so a future SDK shipping it needs no
// changes beyond swapping this one constant.

import FoundationModels

/// The package's front door (plan.md §3a): "a list of things to search, then
/// a query" is the whole API.
///
/// Composes `HybridRanker` (BM25 + trigram + optional cosine, fused by RRF)
/// with `SelectionTier` (agent final selection) over an in-memory catalog
/// built once from `items` at `init`.
///
/// Every knob but `items` is optional: `embedder:` adds the cosine signal
/// (every item's `text` is embedded once, here, at `init`); `session:`
/// swaps the selection model -- defaults to the on-device system model, and
/// is never hardcoded beyond that default, since any closure returning an
/// `AgentSession` (a `LanguageModelSession` factory, or a
/// `RoutedAgentSession` factory for Router users) plugs in identically;
/// `weights:`, `preamble:`, `candidateLimit:` tune the retrieval and
/// selection tiers directly; `mode:` picks which tier answers
/// `search(_:limit:)`.
///
/// Degradation is graceful, never silent (plan.md §3a): no `embedder` (or
/// a query embed that itself fails) drops straight to keyword-only
/// retrieval with `.embeddingUnavailable` reported via `onDiagnostic` on
/// every such search. A `weights.cosine` of `0.0` is different -- a
/// caller's deliberate opt-out of the signal, not a degradation -- so it
/// skips cosine (and its embed call) without reporting anything, mirroring
/// FoundationModelsMetadataRegistry's own `computeSignals`'s "a zero weight
/// means the caller doesn't want the signal" rule. `mode: .selection` with
/// no session configured (`session: nil`) throws
/// `SelectionTierUnavailable` rather than silently retrieving instead;
/// `mode: .auto` (the default) silently prefers selection when a session is
/// configured, retrieval otherwise -- mirroring FMR's own `.auto`
/// semantics.
public struct Searcher: Sendable {
    /// Which tier `search(_:limit:)` answers a query with (plan.md §3a).
    public enum Mode: Sendable {
        /// `HybridRanker`'s fused BM25 + trigram + (optional cosine)
        /// ranking only -- no session, no tokens.
        case retrieval

        /// The agent selects among candidates (`SelectionTier`).
        ///
        /// Throws `SelectionTierUnavailable` when no session is configured
        /// (`session: nil`).
        case selection

        /// Selection when a session is configured, retrieval otherwise --
        /// the default.
        case auto
    }

    /// This facade's zero-config default session factory: the on-device
    /// system model.
    ///
    /// See this file's header for why `.default`, not `.fast`.
    ///
    /// `public`, not `private`: a default argument value on a `public`
    /// initializer must be at least as visible as the initializer itself.
    /// Exposed as a documented seam (rather than an unnamed closure
    /// literal) so a caller can also pass it explicitly, e.g. to restore
    /// the on-device default after overriding `session:` conditionally.
    public static let defaultSessionFactory: @Sendable (String) -> any AgentSession = { instructions in
        LanguageModelSession(model: .default, instructions: instructions)
    }

    /// This facade's precomputed retrieval state and the knobs
    /// `search(_:limit:)`'s retrieval fallback and the selection tier's
    /// per-search catalog ranking both drive `HybridRanker` through.
    private let engine: RetrievalEngine

    /// Which tier `search(_:limit:)` uses.
    private let mode: Mode

    /// This facade's selection tier, or `nil` when `session: nil` left
    /// selection unavailable.
    private let selectionTier: SelectionTier?

    /// Builds a searcher over `items`.
    ///
    /// - Parameters:
    ///   - items: the things to search: at minimum an id and the text that
    ///     describes it (`SearchItem`, or any `Searchable` conformer).
    ///     Duplicate ids keep the first occurrence; later ones are dropped.
    ///   - embedder: embeds every item's `text` once, here, at `init`, and
    ///     the query at every `search(_:limit:)` call -- adds the cosine
    ///     signal to retrieval. `nil` (the default) skips cosine entirely
    ///     and reports `.embeddingUnavailable` on every search that would
    ///     otherwise have used it (whenever `weights.cosine > 0.0`; a
    ///     caller who sets `weights.cosine` to `0.0` has already opted out
    ///     of the signal, so that combination reports nothing).
    ///   - session: creates a selection session seeded with the assembled
    ///     candidate prefix -- the seam that plugs in any
    ///     `LanguageModelSession` model or a `RoutedAgentSession` factory,
    ///     never hardcoded. Defaults to the on-device system model; pass
    ///     `nil` explicitly to leave selection unavailable (`mode:
    ///     .selection` then throws `SelectionTierUnavailable`; `.auto`
    ///     degrades to retrieval).
    ///   - weights: the per-signal fusion weights for retrieval. Defaults
    ///     to `1.0` for every signal.
    ///   - preamble: the selection guidance prepended to the assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - candidateLimit: how many top-ranked candidates the over-budget
    ///     selection path seeds a one-off session with. Defaults to
    ///     `SelectionConfig.defaultCandidateLimit`.
    ///   - mode: which tier `search(_:limit:)` uses. Defaults to `.auto`.
    ///   - onDiagnostic: called for every diagnostic this facade or its
    ///     selection tier emits. Defaults to doing nothing.
    /// - Throws: whatever `embedder.embed(_:)` throws while embedding
    ///   `items` at `init`.
    public init<Item: Searchable>(
        _ items: [Item],
        embedder: (any TextEmbedding)? = nil,
        session: (@Sendable (String) -> any AgentSession)? = Searcher.defaultSessionFactory,
        weights: SignalWeights = SignalWeights(),
        preamble: String = .selectionDefault,
        candidateLimit: Int = SelectionConfig.defaultCandidateLimit,
        mode: Mode = .auto,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
    ) async throws {
        let corpus = SearchCorpus(items: items)
        let itemEmbeddings: [[Float]]?
        if let embedder {
            itemEmbeddings = try await embedder.embed(corpus.ids.map { corpus.block(forId: $0) ?? "" })
        } else {
            itemEmbeddings = nil
        }

        let engine = RetrievalEngine(
            corpus: corpus,
            itemEmbeddings: itemEmbeddings,
            embedder: embedder,
            weights: weights,
            onDiagnostic: onDiagnostic
        )
        self.engine = engine
        self.mode = mode

        if let session {
            let config = SelectionConfig(
                model: { instructions, _ in session(instructions) },
                preamble: preamble,
                candidateLimit: candidateLimit
            )
            self.selectionTier = SelectionTier(
                catalog: corpus,
                config: config,
                onDiagnostic: onDiagnostic,
                retrievalRanking: engine.fullOrdering
            )
        } else {
            self.selectionTier = nil
        }
    }

    /// Searches this facade's catalog for `query`, answering through
    /// whichever tier `mode` selects.
    ///
    /// A selection-tier search (under or over budget) ranks the whole
    /// catalog once per query to attach real scores to the picks — which
    /// includes one query-embedding call when an `embedder:` is configured.
    /// Without one, each selection search reports the same
    /// `.embeddingUnavailable` degradation a retrieval search does (unless
    /// `weights.cosine` is `0.0`, the documented opt-out).
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of results to return. Defaults to
    ///     `20`. `limit <= 0` yields an empty result rather than throwing
    ///     or crashing.
    /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches, each
    ///   carrying real per-signal `signals`; `.selection`'s verbatim
    ///   matches, each carrying the same real fused score/signals the
    ///   full-catalog retrieval ordering reports for the query (plan.md
    ///   §3a); `.auto`'s resolution of whichever of those applies.
    /// - Throws: `SelectionTierUnavailable` when `mode == .selection` and no
    ///   session is configured (`session: nil`); otherwise whatever the
    ///   underlying selection session throws.
    public func search(_ query: String, limit: Int = 20) async throws -> [SelectionMatch] {
        switch mode {
        case .retrieval:
            return await engine.topMatches(query: query, limit: limit)
        case .selection:
            guard let selectionTier else { throw SelectionTierUnavailable() }
            return try await selectionTier.search(intent: query, limit: limit)
        case .auto:
            if let selectionTier {
                return try await selectionTier.search(intent: query, limit: limit)
            }
            return await engine.topMatches(query: query, limit: limit)
        }
    }
}

/// Thrown by `Searcher.search(_:limit:)` when `mode == .selection` and no
/// session is configured (`Searcher.init(..., session: nil, ...)`) --
/// requesting `.selection` explicitly without one fails loudly rather than
/// silently substituting retrieval.
///
/// Mirrors FoundationModelsMetadataRegistry's own `SelectionTierUnavailable`
/// (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`).
public struct SelectionTierUnavailable: Error, Sendable, Equatable {
    /// Creates an error indicating that no selection session is configured.
    public init() {}
}

/// Bundles `Searcher`'s precomputed retrieval state (the corpus and its item
/// embeddings) and knobs (`embedder`, `weights`, `onDiagnostic`) so both
/// `search(_:limit:)`'s own retrieval fallback and the selection tier's
/// `retrievalRanking` closure (captured at `init`, before `self` exists as a
/// `Searcher`) drive the same `HybridRanker` calls without duplicating the
/// wiring.
private struct RetrievalEngine: Sendable {
    /// The corpus this engine ranks: its `ids`/`documents` are
    /// `HybridRanker`'s arguments, and its `block(forId:)` resolves every hit
    /// to a verbatim `SelectionMatch`.
    ///
    /// Fixed for this engine's lifetime -- `Searcher` builds it once at
    /// `init` and never mutates it, which is what keeps `itemEmbeddings`
    /// positionally aligned with `corpus.ids`.
    let corpus: SearchCorpus

    /// One embedding per `corpus.ids` entry, positionally aligned with
    /// `corpus.documents` -- `nil` when no `embedder` was configured.
    let itemEmbeddings: [[Float]]?

    /// Embeds the *query* at search time for the cosine signal. `nil` means
    /// no cosine signal, ever, regardless of `weights.cosine`.
    let embedder: (any TextEmbedding)?

    /// The per-signal fusion weights `HybridRanker` uses.
    let weights: SignalWeights

    /// Called for every diagnostic this engine emits (currently only
    /// `.embeddingUnavailable`).
    let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// Embeds `query` and scores it against every precomputed item
    /// embedding -- the cosine signal `HybridRanker` fuses in when
    /// non-`nil`.
    ///
    /// `weights.cosine <= 0.0` short-circuits to `nil` with **no**
    /// diagnostic: a caller who zeroed the weight has already opted out of
    /// the signal, not hit a degradation, so there's nothing to embed or
    /// warn about -- mirrors FoundationModelsMetadataRegistry's
    /// `MetadataSearcher.computeSignals`'s "a zero weight means the caller
    /// doesn't want the signal" rule. Otherwise, degrades to `nil`
    /// (keyword-only) and *does* report `.embeddingUnavailable` whenever
    /// cosine was actually wanted but couldn't contribute: no
    /// `embedder`/`itemEmbeddings` available, or embedding the query
    /// itself fails -- mirrors `MetadataSearcher
    /// .computeCosineRanking`'s degradation, generalized to FoundationModelsRanker's
    /// `HybridRanker` seam.
    ///
    /// - Parameter query: the query to embed and score.
    /// - Returns: one cosine score per `corpus.documents` entry, positionally
    ///   aligned, or `nil` to skip the cosine signal for this search.
    func cosineScores(forQuery query: String) async -> [Double]? {
        guard weights.cosine > 0.0 else { return nil }
        guard let embedder, let itemEmbeddings else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }
        guard let queryVector = try? await embedder.embed([query]).first else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }
        return itemEmbeddings.map { CosineScoring.cosineSimilarity(queryVector, $0) }
    }

    /// `.retrieval` mode's answer: `HybridRanker.topMatches(...)`, mapped
    /// back through `corpus` to verbatim `SelectionMatch`es.
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the fused, `[0, 1]`-normalized matches, best-first.
    func topMatches(query: String, limit: Int) async -> [SelectionMatch] {
        guard limit > 0 else { return [] }
        return await rankedMatches(forQuery: query) { scores in
            HybridRanker.topMatches(
                ids: corpus.ids,
                documents: corpus.documents,
                query: query,
                cosineScores: scores,
                weights: weights,
                limit: limit
            )
        }
    }

    /// The selection tier's `retrievalRanking` source
    /// (`SelectionTier.init(catalog:config:onDiagnostic:retrievalRanking:)`):
    /// `HybridRanker.fullOrdering(...)`, mapped back through `corpus` to
    /// verbatim `SelectionMatch`es -- always exactly `corpus.count` long.
    /// Over budget it supplies the top-M candidate cut; under budget it
    /// supplies the real fused `score`/`signals` every selected id carries.
    ///
    /// - Parameter query: the search intent.
    /// - Returns: exactly `corpus.count` matches, best-first.
    func fullOrdering(query: String) async -> [SelectionMatch] {
        await rankedMatches(forQuery: query) { scores in
            HybridRanker.fullOrdering(
                ids: corpus.ids, documents: corpus.documents, query: query, cosineScores: scores, weights: weights
            )
        }
    }

    /// The shared ranking pipeline of `topMatches` and `fullOrdering`, which
    /// differ only in the `HybridRanker` call `rank` binds: short-circuit an
    /// empty corpus, resolve the cosine signal once, rank, and map the hits
    /// back through `corpus` to verbatim `SelectionMatch`es.
    ///
    /// - Parameters:
    ///   - query: the search query to resolve cosine scores for.
    ///   - rank: ranks the corpus given the resolved cosine scores (`nil`
    ///     when the signal is skipped), in whatever order it decides.
    /// - Returns: one `SelectionMatch` per hit, positionally aligned with
    ///   `rank`'s result.
    private func rankedMatches(forQuery query: String, rank: ([Double]?) -> [Hit]) async -> [SelectionMatch] {
        guard !corpus.isEmpty else { return [] }
        let hits = rank(await cosineScores(forQuery: query))
        return hits.map { hit in
            SelectionMatch(id: hit.id, block: corpus.block(forId: hit.id) ?? "", score: hit.score, signals: hit.signals)
        }
    }
}
