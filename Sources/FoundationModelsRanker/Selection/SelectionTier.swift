// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`
// (plan.md §6 phase 3), generalized over `any SelectionCatalog` instead of
// `MetadataIndex<Item>`: `index.ids`/`item(forId:)`/`block(forId:)`/
// `renderSummaryBlock()` map onto `catalog.ids`/`summaryBlock(forId:)`/
// `block(forId:)`; `Match<Item>` becomes `SelectionMatch` (no catalog item to
// carry); `MetadataDiagnostic` becomes `RankDiagnostic`. Semantics unchanged.

import Foundation
import FoundationModelsRouter

/// The selection tier's dynamic session over a `SelectionCatalog` (plan.md
/// §6): generalizes FoundationModelsMetadataRegistry's own `SelectionTier`,
/// which itself generalized Multitool's shipped `Librarian`
/// (`../FoundationModelsMultitool/Sources/.../Librarian.swift`), over any
/// narrow `SelectionCatalog` conformer instead of a bespoke index type.
///
/// Assembles a prefix from `SelectionConfig.preamble` + every catalog id's
/// **`summaryBlock(forId:)`** (plan.md §4: the summary seeds the selection
/// prefix; retrieval indexes the full `block(forId:)` instead) once at
/// `init`, since the catalog never changes for this tier's lifetime — a
/// reload replaces the whole tier rather than mutating one in place.
///
/// **Under budget** (assembled prefix ≤ `capacityCharacterLimit`): a cached
/// root session is seeded once with the prefix, and each
/// `search(intent:limit:)` `fork()`s a fresh child from it, so the prefix's
/// KV cache is prefilled once and inherited per call — lifted from
/// `Librarian.findAPIs(task:)`'s cached-root + fork-per-call mechanics.
///
/// **Over budget**: `retrievalRanking` ranks the whole catalog for the
/// intent, and the top `config.candidateLimit` candidates (best-first) seed
/// a **fresh, uncached, unforked one-off session** — there is no stable
/// prefix to reuse, since the candidate set differs per intent. The cut is
/// reported via `RankDiagnostic.retrievalCut(considered:kept:)` (the
/// `onPrefilterCut` pattern, generalized to ranked retrieval). Unlike the
/// under-budget path, retrieval genuinely ran, so returned `SelectionMatch`es
/// carry its real fused `score`/`signals` instead of the pure-selection
/// `1.0`/`nil`, and a selected id outside this round's candidates — even a
/// legitimate id from elsewhere in the wider catalog — is filtered and
/// reported via `.unknownSelectedId`, exactly like an id absent from the
/// catalog altogether.
///
/// **Ids only, grammar-enforced** (plan.md §6, decision #4): the guided
/// output is `Selection { ids: [String] }`; `idEnumGrammar(ids:)` derives the
/// xgrammar JSON Schema constraining `ids` to the current candidate id
/// set — the full catalog under budget, the top-M ranked ids over budget —
/// so the model is structurally incapable of inventing one — the same
/// pattern as `Librarian.grammarSchemaSource()`, with an added `enum`
/// constraint injected into the `ids` array's `items` subschema. Returned ids
/// map back through the catalog to verbatim `SelectionMatch`es; an id outside
/// the current candidate set — structurally unreachable given the grammar,
/// but defended against anyway — is filtered and reported via
/// `RankDiagnostic.unknownSelectedId(id:)`.
public actor SelectionTier {
    /// The full catalog this tier answers `search(intent:limit:)` calls
    /// over.
    private let catalog: any SelectionCatalog

    /// This tier's session factory, preamble, and capacity/candidate budgets.
    private let config: SelectionConfig

    /// `assemblePrefix(preamble:catalog:)`, precomputed once at `init` since
    /// `catalog` never changes for this tier's lifetime.
    private let assembledPrefix: String

    /// Called for every diagnostic this tier emits (currently
    /// `.unknownSelectedId` and `.retrievalCut`).
    private let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// Ranks the whole catalog for one intent, best-first, always returning
    /// exactly as many `SelectionMatch`es as the catalog has entries — the
    /// over-budget path's source of top-M candidates. A consumer composing
    /// this tier with FoundationModelsRanker's own `HybridRanker` wires this to
    /// `HybridRanker.fullOrdering(ids:documents:query:cosineScores:weights:)`
    /// mapped into `SelectionMatch`; tests script it directly.
    private let retrievalRanking: @Sendable (String) async -> [SelectionMatch]

    /// This tier's cached root session — `nil` until the first under-budget
    /// `search(intent:limit:)` call creates and caches it.
    private var rootSession: (any AgentSession)?

    /// Creates a selection tier over `catalog`, using `config`'s session
    /// factory, preamble, and budgets.
    ///
    /// - Parameters:
    ///   - catalog: the catalog to answer `search(intent:limit:)` calls over.
    ///   - config: this tier's session factory, preamble, and budgets.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    ///   - retrievalRanking: ranks the whole catalog for one intent,
    ///     best-first — the over-budget path's source of top-M candidates.
    public init(
        catalog: any SelectionCatalog,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void,
        retrievalRanking: @escaping @Sendable (String) async -> [SelectionMatch]
    ) {
        self.catalog = catalog
        self.config = config
        self.assembledPrefix = Self.assemblePrefix(preamble: config.preamble, catalog: catalog)
        self.onDiagnostic = onDiagnostic
        self.retrievalRanking = retrievalRanking
    }

    /// Answers one `search(intent:limit:)` call.
    ///
    /// Under budget: reuses (creating on first use) this tier's cached root
    /// session, seeded with the full assembled prefix, and `fork()`s a fresh
    /// child per call so the prefix's prefilled compute is inherited rather
    /// than replayed. Over budget: ranks the whole catalog and seeds a
    /// one-off session with the top-M candidates (`overBudgetSearch(intent:
    /// limit:)`, plan.md §6) — no caching, no fork.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without forking or creating a session.
    /// - Returns: the selected ids' verbatim `SelectionMatch`es, at most
    ///   `limit`.
    /// - Throws: an error from `idEnumGrammar(ids:)` (not expected for
    ///   `Selection`'s fixed shape), or whatever the underlying session's
    ///   `fork()`/`respond(to:generating:)` throws.
    public func search(intent: String, limit: Int) async throws -> [SelectionMatch] {
        guard limit > 0 else { return [] }
        guard assembledPrefix.count <= config.capacityCharacterLimit else {
            return try await overBudgetSearch(intent: intent, limit: limit)
        }

        let child = try await cachedRootSession().fork()
        let selection = try await child.respond(to: intent, generating: Selection.self)
        return matches(forIds: selection.ids, limit: limit)
    }

    /// Returns this tier's cached root session, creating and caching it on
    /// first use.
    ///
    /// - Returns: the cached root session, seeded with the full assembled
    ///   prefix and constrained to `idEnumGrammar(ids:)` over the whole
    ///   catalog -- every id is a legal selection under budget, since the
    ///   assembled prefix already summarizes the whole catalog.
    /// - Throws: an error from `idEnumGrammar(ids:)` (not expected for
    ///   `Selection`'s fixed shape) on first use; nothing on a cached hit.
    private func cachedRootSession() async throws -> any AgentSession {
        if let rootSession { return rootSession }
        let grammar = try Self.idEnumGrammar(ids: catalog.ids)
        let session = config.model(assembledPrefix, grammar)
        rootSession = session
        return session
    }

    // MARK: - Over budget: retrieval top-M + one-off session

    /// Answers one over-budget `search(intent:limit:)` call (plan.md §6
    /// "Over budget"): ranks the whole catalog through `retrievalRanking`,
    /// takes the top `config.candidateLimit` candidates (best-first —
    /// always `min(config.candidateLimit, considered)` of them, even when
    /// few or none score positively, so the model always has a full
    /// candidate set to pick from), reports the cut via
    /// `.retrievalCut(considered:kept:)`, and seeds a **fresh, uncached,
    /// unforked** one-off session with exactly those candidates'
    /// `summaryBlock(forId:)`s — there is no stable prefix here to reuse,
    /// since the candidate set differs per intent.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected candidates' verbatim `SelectionMatch`es,
    ///   carrying the real retrieval `score`/`signals` that ranked them, at
    ///   most `limit`.
    /// - Throws: an error from `idEnumGrammar(ids:)` (not expected for
    ///   `Selection`'s fixed shape), or whatever the one-off session's
    ///   `respond(to:generating:)` throws.
    private func overBudgetSearch(intent: String, limit: Int) async throws -> [SelectionMatch] {
        let ranked = await retrievalRanking(intent)
        let candidates = Array(ranked.prefix(config.candidateLimit))
        onDiagnostic(.retrievalCut(considered: ranked.count, kept: candidates.count))

        // Nothing to seed a session with -- and nothing worth asking a
        // model to choose among -- when the catalog itself is empty.
        guard !candidates.isEmpty else { return [] }

        let candidateIds = candidates.map(\.id)
        let prefix = Self.assemblePrefix(preamble: config.preamble, ids: candidateIds, catalog: catalog)
        // Constrained to *this round's* candidates, not the whole catalog --
        // a one-off session has no stable prefix to reuse, so its grammar is
        // recomputed fresh per call, scoped to exactly `candidateIds`.
        let grammar = try Self.idEnumGrammar(ids: candidateIds)
        let session = config.model(prefix, grammar)
        let selection = try await session.respond(to: intent, generating: Selection.self)
        return matches(
            forIds: selection.ids,
            limit: limit,
            allowedIds: Set(candidateIds),
            retrievalMatches: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        )
    }

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `SelectionMatch`es (plan.md §6 "Verbatim lookup"), filtering any id
    /// not resolvable and reporting it via `.unknownSelectedId` —
    /// structurally unreachable given the id-enum grammar's `uniqueItems` +
    /// per-element enum constraint, but defended against anyway —
    /// deduplicating repeats (first occurrence wins, keeping the model's own
    /// call-order intent) without reporting a diagnostic for them, and
    /// truncating to `limit`.
    ///
    /// - Parameters:
    ///   - ids: the model-selected ids, in the order the model returned them.
    ///   - limit: the maximum number of matches to return.
    ///   - allowedIds: restricts resolution to this id set (the over-budget
    ///     path's current candidates) in addition to the catalog itself; an
    ///     id absent from `allowedIds` is treated exactly like an id absent
    ///     from the catalog. `nil` (the under-budget default) allows any
    ///     catalog id.
    ///   - retrievalMatches: the retrieval `SelectionMatch` (real fused
    ///     `score` and `signals`) for each of this round's candidates, keyed
    ///     by id — the over-budget path's ranking result. Empty (the
    ///     under-budget default) yields the pure-selection `1.0`/`nil`.
    /// - Returns: the verbatim `SelectionMatch`es for every known, allowed,
    ///   first-seen id, at most `limit`.
    private func matches(
        forIds ids: [String],
        limit: Int,
        allowedIds: Set<String>? = nil,
        retrievalMatches: [String: SelectionMatch] = [:]
    ) -> [SelectionMatch] {
        var results: [SelectionMatch] = []
        results.reserveCapacity(min(ids.count, limit))
        var seenIds: Set<String> = []
        for id in ids {
            guard results.count < limit else { break }
            guard seenIds.insert(id).inserted else { continue }
            guard allowedIds?.contains(id) ?? true,
                let block = catalog.block(forId: id)
            else {
                onDiagnostic(.unknownSelectedId(id: id))
                continue
            }
            let retrievalMatch = retrievalMatches[id]
            results.append(
                SelectionMatch(
                    id: id,
                    block: block,
                    score: retrievalMatch?.score ?? 1.0,
                    signals: retrievalMatch?.signals
                )
            )
        }
        return results
    }

    // MARK: - Prefix assembly

    /// Assembles this tier's instruction prefix (plan.md §6): `preamble`
    /// followed by a `# Candidates` header and every catalog id's
    /// **`summaryBlock(forId:)`**, in catalog order — never `block(forId:)`,
    /// which stays reserved for the verbatim `SelectionMatch.block` a
    /// selected id looks up afterward (plan.md §4).
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - catalog: the catalog to assemble a prefix for.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, catalog: any SelectionCatalog) -> String {
        assemblePrefix(preamble: preamble, ids: catalog.ids, catalog: catalog)
    }

    /// Assembles an instruction prefix for an arbitrary candidate id
    /// set (plan.md §6): `preamble` followed by a `# Candidates` header and
    /// exactly those ids' **`summaryBlock(forId:)`**, in `ids`' order —
    /// `assemblePrefix(preamble:catalog:)`'s whole-catalog case is
    /// `ids: catalog.ids`; the over-budget path passes the top-M ranked ids
    /// instead, best-first.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - ids: the candidate ids to render, in the order they should appear.
    ///   - catalog: the catalog to look candidate summaries up in.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, ids: [String], catalog: any SelectionCatalog) -> String {
        let summaryBlocks = ids.compactMap { catalog.summaryBlock(forId: $0) }
        return "\(preamble)\n\n# Candidates\n\(summaryBlocks.joined(separator: "\n\n"))"
    }

    // MARK: - Guided-generation grammar

    /// Derives the xgrammar JSON Schema constraining `Selection.ids` to
    /// exactly `ids` (plan.md §6 "Ids only, grammar-enforced") — the same
    /// derive-then-wrap pattern as Multitool's own
    /// `Librarian.grammarSchemaSource()` (which wraps the analogous derived
    /// schema in `Grammar.jsonSchema(_:)`), with an `enum` constraint
    /// injected into the `ids` array's `items` subschema so the model is
    /// structurally incapable of inventing an id outside the current
    /// candidate set.
    ///
    /// - Parameter ids: the candidate id set to constrain output to — the
    ///   full catalog's ids under budget, the top-M ranked ids over budget.
    /// - Returns: the xgrammar-ready `Grammar.jsonSchema(_:)`.
    /// - Throws: an encoding error if `Selection.generationSchema` can't be
    ///   encoded to JSON (not expected for a valid `@Generable` type), or
    ///   `SelectionSchemaShapeError` if its encoded shape doesn't have the
    ///   expected `properties.ids.items` subschema to constrain (not expected
    ///   for `Selection`'s fixed shape).
    public static func idEnumGrammar(ids: [String]) throws -> Grammar {
        let data = try JSONEncoder().encode(Selection.generationSchema)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            var properties = root["properties"] as? [String: Any],
            var idsSchema = properties["ids"] as? [String: Any],
            var itemsSchema = idsSchema["items"] as? [String: Any]
        else {
            throw SelectionSchemaShapeError()
        }

        itemsSchema["enum"] = ids
        idsSchema["items"] = itemsSchema
        // No duplicate ids in one selection -- pairs with the per-element
        // `enum` constraint above to make the *set* of ids structurally
        // exact, not just each individual element's membership.
        idsSchema["uniqueItems"] = true
        properties["ids"] = idsSchema
        root["properties"] = properties

        let constrained = try JSONSerialization.data(withJSONObject: root)
        return .jsonSchema(String(decoding: constrained, as: UTF8.self))
    }
}

/// Thrown by `SelectionTier.idEnumGrammar(ids:)` if `Selection`'s encoded
/// `GenerationSchema` doesn't have the expected `properties.ids.items`
/// subschema shape to inject an `enum` constraint into — not expected for
/// `Selection`'s fixed shape, kept as a genuine (if practically unreachable)
/// failure mode rather than trapping.
public struct SelectionSchemaShapeError: Error, Sendable, Equatable {}
