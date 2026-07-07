# RankKit — extract the shared search/ranking primitives

Extract the hybrid-search primitives duplicated between `../CodeContextKit` and
`../FoundationModelsMetadataRegistry` into this package, then make both repos
depend on it. This is the extraction FoundationModelsMetadataRegistry's own
plan.md pre-authorized (decision #9: *"Port, don't depend … extract a shared
micro-package only if a third copy appears"* — it even sketched the name,
"SwiftRankFusion"). RankKit is that package; any next consumer becomes the
third copy that rule anticipated, so we extract now rather than copy a third
time.

## 1. Verified findings (2026-07-07)

The duplication assumption is **confirmed for retrieval, not for selection**:

**Byte-identical modulo header comments** — FoundationModelsMetadataRegistry's
copies carry explicit "Ported from CodeContextKit's …" attribution headers;
the CodeContextKit originals are themselves ports of the Rust
`swissarmyhammer-search` crate:

| File | CCK | FMR | Divergence |
|---|---|---|---|
| `Search/Trigram.swift` | 70 ln | 74 ln | header comment only |
| `Search/Tokenizer.swift` | 133 ln | 137 ln | header comment only |
| `Search/RRF.swift` | 67 ln | 71 ln | header comment only |
| `Search/Hit.swift` (`Hit` + `Signals`) | 70 ln | 74 ln | header comment only |
| `Search/BM25.swift` | 103 ln | 111 ln | field-weight constant *names* only: `symbolPathFieldWeight`/`bodyFieldWeight` vs `idFieldWeight`/`blockFieldWeight` (same values, 5.0/1.0) |
| `Embedding/TextEmbedding.swift` | 19 ln | 26 ln | doc comments only; identical `func embed(_ texts: [String]) async throws -> [[Float]]` |
| `Embedding/RoutedEmbedderAdapter.swift` | 45 ln | 50 ln | one call-site label: CCK calls `routedEmbedder.embed(texts:)`, FMR calls `embed(_:)`. FoundationModelsRouter `main` exposes `embed(_:)` — **FMR's copy is the one that matches current Router; take it as canonical** |

**Structurally duplicated (same logic, different corpus representation)** —
`CodeContextKit/Ops/SearchCode.swift` (425 ln) and
`FoundationModelsMetadataRegistry/MetadataSearcher.swift` (758 ln) each
reimplement the identical pipeline against their own snapshot type:

- a per-signal weights struct (`SearchWeights` vs `Weights` — same three
  fields, same defaults)
- `computeBM25Ranking` / `computeTrigramRanking` / `computeCosineRanking`
- `rankingOfPositiveScores(scores:)` — verbatim-identical function in both
- the absent-signal rule: only signals with positive weight *and* a non-empty
  ranking enter `RRF.fuse`/`RRF.normalize`, so the normalization ceiling never
  counts a signal that couldn't score (FMR's doc comments say "generalized
  from CodeContextKit's `SearchWeights`/`SearchCode.fuseRankings`")
- deterministic descending-score sort with a first-seen/lowest-id tie-break
- two-field weighting applied identically to BM25 term frequencies *and*
  trigram Dice aggregates (primary field ×5, body ×1)
- document precompute: tokenize both fields → weighted term-frequency map,
  term set, document length, two canonical trigram sets
  (`SearchCorpus.preprocessRow` vs `MetadataIndex`'s build)

**Genuinely different (stays put)**:

- Cosine scoring strategy: CCK packs embeddings into one contiguous row-major
  `[Float]` matrix and scores with a single `vDSP_mmul` matvec
  (`SearchCorpusSnapshot`); FMR does scalar per-row `cosineSimilarity` (its
  plan.md explicitly reserves `MetadataIndex` as the seam to adopt the matrix
  design later). Both are candidates to share via a `CosineScoring` utility —
  phase 2.
- Corpus/storage: CCK's `SearchCorpus` is GRDB/`ts_chunks`/generation-cache
  specific; FMR's `MetadataIndex` is in-memory with incremental re-embed and
  hot reload. Not shared.
- **Agent-based selection is NOT duplicated today.** CodeContextKit has no
  LLM selection tier at all (grep: no `LanguageModelSession`/selection code).
  The selection tier exists only in FMR (`SelectionTier`, `SelectionConfig`,
  `Selection`, `AgentSession`, ~570 ln), which itself superseded
  FoundationModelsMultitool's Librarian (Multitool no longer contains any
  BM25/trigram/RRF code). But CodeContextKit *should* have it — `search code`
  currently stops at RRF fusion, and we want an agent-selection mode there
  too. That makes CCK the second consumer, so the tier moves into RankKit
  rather than being copied a second time (§6 phase 3).

## 2. Goals / non-goals

**Goals**
- One canonical copy of the retrieval primitives, with the tests that prove
  them, consumed by both repos as a SwiftPM dependency.
- Zero behavior change in either consumer in phase 1 — file moves + renames,
  proven by porting the existing tests verbatim.
- The selection tier generalized into RankKit, and CodeContextKit's
  `search code` gaining an agent-selection mode over its RRF candidates
  (phases 3–4) — the one deliberate new capability.
- Neutral naming: nothing in RankKit may mention chunks, symbols, catalogs,
  or metadata.

**Non-goals**
- No new ranking *signals*, no persistence, no vector store.
- No attempt to make CCK and FMR share a corpus/index type — only the
  primitives, the fusion pipeline (phase 2), and the selection tier
  (phase 3) over narrow protocols.

## 3. Package design

```
RankKit/
  Package.swift              swift-tools 6.1, platforms: [.macOS("27.0")]
  Sources/
    RankKit/                 ← the one product
      Searcher.swift          (phase 3 — the one-call facade, §3a)
      BM25.swift             (neutral field-weight names, §4)
      Trigram.swift
      Tokenizer.swift
      RRF.swift
      Hit.swift              (Hit + Signals)
      TextEmbedding.swift
      RoutedEmbedderAdapter.swift   (take FMR's copy — matches Router main's embed(_:))
      Selection/               (lands in phase 3, generalized from FMR — §6)
        SelectionCatalog.swift
        SelectionTier.swift
        SelectionConfig.swift
        Selection.swift
        AgentSession.swift
  Examples/
    FullMonty/               (phase 3 — §3a; runnable `swift run FullMonty`)
    FullMontyCore/           (library twin so smoke tests can drive it, FMR's pattern)
  Tests/
    RankKitTests/            ported from both repos, verbatim (§5)
```

- **One product, one target.** `FoundationModelsRouter` is a plain required
  dependency (remote URL, `branch: "main"`, matching the family convention
  FMR documents for CI — the shared `swift-ci.yaml` only checks out the
  calling repo, so no local path deps). No product split: both consumers
  already depend on Router, so keeping the core dependency-free buys nothing.
- **macOS 27 floor**, inherited from Router; both consumers are already on
  27, so nothing is lost.
- Strip the "Ported from CodeContextKit's …" headers on the moved files and
  replace with a single attribution note (RankKit is now the canonical home;
  lineage: Rust `swissarmyhammer-search` → CodeContextKit → here). Keep all
  doc comments otherwise, minus repo-specific references.

## 3a. The one-call interface (`Searcher`) — the package's front door

RankKit is not just a parts bin: it ships a facade where "a list of things to
search, then a query" is the whole API, and the full monty — BM25 + trigram +
cosine fused by RRF, then agent final selection over the top candidates — is
the *default* behavior, not an assembly project:

```swift
import FoundationModels
import FoundationModelsRouter
import RankKit

// The things to search: an id and the text that describes it.
let items = [
    SearchItem(id: "grep",  text: "Search file contents with regular expressions"),
    SearchItem(id: "glob",  text: "Find files by name pattern, sorted by mtime"),
    SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    // ...hundreds more...
]

// Easiest call: agent selection on the on-device system model (.fast —
// the shipped default; selection is a constrained pick-from-a-list, a
// fast-variant task), retrieval is BM25 + trigram fused by RRF.
let searcher = try await Searcher(items)
let hits = try await searcher.search("how do I find TODO comments in my code")
// hits[0].id == "grep", with .score and per-signal .signals attached

// Any LanguageModelSession works — the model is never hardcoded.
// Prefer .default for more careful picks:
let careful = try await Searcher(items, session: { instructions in
    LanguageModelSession(model: .default, instructions: instructions)
})

// The true full monty: a Router adds the embedder (cosine joins RRF)
// and can also supply the selection session (grammar-constrained,
// any local model the router resolves) — still just arguments:
let full = try await Searcher(
    items,
    embedder: RoutedEmbedderAdapter(embedder: router.embedder),
    session: { instructions in router.makeSelectionSession(instructions) }
)
```

Design rules for the facade:

- `SearchItem` is the trivial unit: `id` + `text` (an optional `summary`
  defaults to `text`, used to seed the selection prefix). Alongside it, a
  `Searchable` protocol lets richer types participate without wrapping.
- **The selection model is pluggable, never hardcoded.** `session:` is a
  factory `(String) -> any AgentSession` — the same seam FMR ships today.
  RankKit retroactively conforms Apple's `LanguageModelSession` to
  `AgentSession`, so a closure returning
  `LanguageModelSession(model:instructions:)` with `.fast`, `.default`, or
  any adapter-loaded model just works; Router users pass a
  `RoutedAgentSession` factory instead. The shipped default (used by
  `Searcher(items)`) is the system model's `.fast` variant — guidance, not a
  requirement; `.default` or anything else is one argument away.
- Grammar enforcement follows the session: Router guided sessions get the
  id-enum xgrammar constraint (`idEnumGrammar`); plain
  `LanguageModelSession`s rely on `Selection`'s `@Generable` typed output
  plus the `.unknownSelectedId` filter — same defended semantics either way.
- Every knob stays reachable but optional: `embedder:`, `session:`,
  `weights:`, `preamble:`, `candidateLimit:`, `mode:`
  (`.retrieval`/`.selection`/`.auto`, default `.auto`).
- Graceful degradation is inherited, never silent: no embedder →
  keyword-only retrieval with a reported diagnostic; no session →
  retrieval-only, exactly FMR's absent-signal semantics.
- Internally `Searcher` is thin: it composes the phase-2 `HybridRanker` and
  the phase-3 `SelectionTier` — the same parts FMR's `MetadataSearcher` and
  CCK's `SearchCode` compose with their own corpora. Once it exists, FMR's
  `MetadataSearcher` can (optionally, later) become a wrapper over it.

`Examples/FullMonty` is the living proof: a fixture catalog of ~50 items, a
handful of queries, printed matches with per-signal scores and the model's
final selection. Its default path runs out of the box on the on-device
system model (`.fast`, per the guidance above — with a `--model default`
flag showing the swap); `--no-model` prints the degraded keyword-only path
and its diagnostic for CI. With the family's gated env var set it instead
resolves a live Router + tiny mlx-community model for both the embedder and
the selection session, exactly like FMR's `Librarian`/`SemanticSearch`
examples. The example-only MLX/Hugging Face product dependencies attach to
the example targets, never the library.

## 4. API reconciliations (the only deliberate diffs from today's code)

1. **BM25 field-weight names** — the one real code divergence. Rename to
   domain-neutral in RankKit:
   - `BM25.primaryFieldWeight = 5.0` (CCK's `symbolPathFieldWeight`, FMR's
     `idFieldWeight`)
   - `BM25.bodyFieldWeight = 1.0` (CCK already uses this name; FMR calls it
     `blockFieldWeight`)
   Call sites in each consumer update mechanically (CCK: `SearchCorpus.
   preprocessRow`, `SearchCode.computeTrigramRanking`; FMR: `MetadataIndex`,
   `MetadataSearcher.computeTrigramRanking`).
2. **`TextEmbedding`** — already identical; take the signature as-is. Doc
   comment rewritten neutrally ("conformers embed a batch of texts; tests
   substitute a deterministic double").
3. **`RoutedEmbedderAdapter`** — take FMR's copy verbatim (calls Router's
   current `embed(_:)`). Deleting CCK's stale-labeled copy in favor of this
   one silently fixes CCK's drift against Router `main`.
4. **Access control** — everything moved stays `public` exactly as it is
   today. Each consumer adds `@_exported import RankKit` (or plain `import`
   plus local `typealias`es, decided per repo at migration time) so *their*
   public APIs that expose `Hit`/`Signals`/`TextEmbedding` (`SearchCodeMatch.
   hit`, FMR's `Match.signals`, both packages' `init(embedder:)` seams) don't
   break downstream source.

## 5. Tests that move

Port verbatim (rename suites, drop repo-specific fixtures only where they
reference chunks/catalogs by name):

- CCK `Tests/CodeContextKitTests/RankerTests.swift` (335 ln — BM25, trigram,
  RRF, tokenizer coverage) and the primitive-level parts of
  `EmbeddingSeamTests.swift`.
- FMR `RRFTests.swift`, `TrigramTests.swift` — written against the *same*
  primitives; overlapping cases are fine (keep both; they encode each repo's
  edge-case history).

The consumers keep their pipeline-level tests (`SearchCodeTests`,
`RetrievalSearchTests`, `OverBudgetTests`, …) — those run against the moved
primitives transitively and are the no-behavior-change proof during
migration.

## 6. Phases

**Phase 1 — extract the identical files (this is the whole immediate ask)**
1. Scaffold `Package.swift`, `README.md`, family CI workflow in this repo.
2. Move the six core files + adapter per §3/§4; port tests per §5.
3. `swift test` green here; push to `github.com/swissarmyhammer/RankKit`.
4. Migrate **FMR**: delete `Search/`, `Embedding/`; add the RankKit
   dependency; rename `idFieldWeight`/`blockFieldWeight` call sites; full test
   suite green with no test-body edits other than imports.
5. Migrate **CCK**: delete `Search/{BM25,Trigram,Tokenizer,RRF,Hit}.swift`,
   `Embedding/`; add RankKit; rename `symbolPathFieldWeight` call sites;
   suite green. (`SearchCorpus.swift` stays — it's storage, not primitives.)

**Phase 2 — unify the duplicated pipeline (recommended follow-up, separate PR)**
Extract into RankKit the logic §1 lists as structurally duplicated:
- `SignalWeights` (bm25/trigram/cosine, defaults 1.0) replacing
  `SearchWeights`/`Weights`.
- `RankedDocument` value type: `init(primaryText:bodyText:)` precomputes the
  weighted term-frequency map, term set, document length, and both trigram
  sets — replaces `SearchCorpus.preprocessRow` and `MetadataIndex`'s
  equivalent.
- `HybridRanker`: given per-document `RankedDocument`s, optional cosine
  scores, and `SignalWeights`, produce the fused, `[0,1]`-normalized,
  tie-broken ranking plus per-document raw `Signals` — encoding the
  absent-signal rule and `rankingOfPositiveScores` once. `SearchCode.run`
  and `MetadataSearcher.retrievalSearch`/`rankEntireCatalog` become thin
  mappings from their snapshot/index into it.
- `CosineScoring`: CCK's `matvecCosineScores` (vDSP, contiguous matrix) and
  FMR's scalar `cosineSimilarity`, side by side — FMR's `MetadataIndex` can
  then adopt the matrix path its plan.md reserved as a seam, or not.

**Phase 3 — generalize the selection tier into RankKit**

CCK wanting agent selection for `search code` makes it the second consumer,
so FMR's tier moves here rather than being copied. The coupling is narrow —
`SelectionTier` touches its index only via `index.ids`, `item(forId:)`,
`block(forId:)`, and `renderSummaryBlock()` — so the generalization is:

- `SelectionCatalog` protocol (the seam replacing `MetadataIndex<Item>`):
  `ids: [String]`, `summaryBlock(forId:) -> String?` (seeds the prefix),
  `block(forId:) -> String?` (the verbatim result payload). FMR's
  `MetadataIndex` conforms trivially; CCK conforms a thin view over
  `SearchCorpusSnapshot` (id = chunk id, summary = symbol path + kind +
  `file:start-end`, block = chunk text).
- Move `SelectionTier`, `SelectionConfig` (session factory, preamble,
  `capacityCharacterLimit`, `candidateLimit`), `Selection` (`@Generable` —
  brings the FoundationModels system framework import, fine at the macOS 27
  floor), `AgentSession`, and `idEnumGrammar(ids:)` (already uses Router's
  `Grammar`, which RankKit links anyway).
- Neutral diagnostics: RankKit needs its own small diagnostic enum for
  `.retrievalCut(considered:kept:)` / `.unknownSelectedId(id:)`; FMR maps it
  into `MetadataDiagnostic`, CCK into its logging.
- Everything selection-shaped keeps its semantics verbatim: under-budget
  cached-root + fork-per-call, over-budget retrieval top-M into a one-off
  session, ids-only grammar-constrained output, verbatim block lookup.
- **Selection prompt: default in RankKit, override per consumer.** The
  prompt is `SelectionConfig.preamble` (the full prefix is preamble +
  `# Candidates` + each candidate's summary block, assembled in
  `SelectionTier.assemblePrefix`). RankKit ships the default —
  `String.selectionDefault`, today's `.librarianDefault` guidance with
  neutral wording ("return ONLY the items needed — fewest that suffice, in
  call order when order matters; do not invent ids; return an empty list if
  nothing fits"). Consumers override via the existing `preamble:` parameter:
  FMR passes its API-librarian text (keeping today's model-visible prompt
  byte-identical), CCK passes a code-flavored one ("you select source-code
  chunks that answer the question…", phase 4).
- Conform Apple's `LanguageModelSession` to `AgentSession` (retroactive
  conformance in RankKit) so any FoundationModels model — `.fast`,
  `.default`, adapter-loaded — plugs into the selection seam without Router
  (§3a: the model is never hardcoded).
- Build the `Searcher` facade (§3a) and the `Examples/FullMonty` targets in
  this phase — they compose the phase-2 ranker with this tier and are the
  package's front door and living documentation.
- Port FMR's `SelectionTests`/`OverBudgetTests` alongside; FMR keeps thin
  integration coverage over its `MetadataSearcher` wiring. `Searcher` gets
  its own suite against scripted `AgentSession` fakes and a fake embedder.

**Phase 4 — CodeContextKit adopts agent selection in `search code`**

- Add a search mode to `SearchCode` mirroring FMR's `SearchMode`:
  `.retrieval` (today's behavior, unchanged, stays the default), `.selection`
  (agent picks), `.auto` (selection when a session factory is configured,
  else retrieval) — and thread it through `CodeContext`'s `search code` op.
- A code corpus (10³–10⁵ chunks) will essentially always be over
  `capacityCharacterLimit`, so CCK lives on the over-budget path: RRF ranks
  the corpus exactly as today, the top `candidateLimit` chunks' summary
  blocks seed a one-off session, the model returns the fewest chunk ids that
  answer the intent, and results keep their real fused `score`/`signals`.
  Selection is a *reranking/pruning stage over* RRF, not a replacement — RRF
  remains the candidate source.
- Wiring: `CodeContext` accepts an optional `SelectionConfig` (session
  factory from FoundationModelsRouter, same shape FMR uses); absent one,
  `.selection` fails loudly and `.auto` degrades to `.retrieval`, matching
  FMR's `SelectionTierUnavailable` semantics.
- Tests: scripted `AgentSession` fakes (FMR's pattern) over small fixture
  corpora — no GPU, no live model — plus one gated live-Router integration
  test mirroring FMR's `METADATA_REGISTRY_INTEGRATION_TESTS` convention.

## 7. Risks

- **Module-move source breaks downstream** of CCK/FMR (types change modules).
  Mitigated by `@_exported import` in phase-1 steps 4–5; verify by building
  each repo's dependents (sah MCP, Multitool) before merging.
- **Remote `branch: "main"` dependency** means a RankKit regression breaks
  both consumers' CI at once. Same tradeoff the family already accepts for
  FoundationModelsRouter; the ported test suite is the guard.
- **CCK's Router-label drift** (`embed(texts:)`): if CCK currently pins an
  older Router, adopting RankKit's adapter may surface other Router API
  drift in CCK — handle in step 5, don't paper over it in RankKit.
- **Selection adds latency and a model dependency to `search code`** (a
  session per query, tokens per candidate summary). Mitigated by keeping
  `.retrieval` the default and `.auto` degrading loudly when no session
  factory is configured — the same never-silent posture FMR ships.
- **Candidate-summary budget for code**: chunk summaries must stay terse
  (symbol path + kind + location, not chunk text) or the over-budget one-off
  prefix itself blows the context window at `candidateLimit` ≈ 24. Phase 4
  should measure the assembled prefix size on a real corpus before picking
  defaults.
