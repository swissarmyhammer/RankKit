# FoundationModelsRanker — extract the shared search/ranking primitives

Extract the hybrid-search primitives duplicated between `../CodeContextKit` and
`../FoundationModelsMetadataRegistry` into this package so both repos can
depend on it. This plan covers **only FoundationModelsRanker** — each consumer's migration is
a separate job, planned in that repo (§6a). This is the extraction FoundationModelsMetadataRegistry's own
plan.md pre-authorized (decision #9: *"Port, don't depend … extract a shared
micro-package only if a third copy appears"* — it even sketched the name,
"SwiftRankFusion"). FoundationModelsRanker is that package; any next consumer becomes the
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
  too. That makes CCK the second consumer, so the tier moves into FoundationModelsRanker
  rather than being copied a second time (§6 phase 3).

## 2. Goals / non-goals

**Goals**
- One canonical copy of the retrieval primitives, with the tests that prove
  them, ready for both sibling repos to consume as a SwiftPM dependency.
- Behavior preserved: the ports are verbatim (modulo the §4 renames), proven
  by porting the existing tests from both repos.
- The selection tier generalized behind narrow protocols, fronted by the
  one-call `Searcher` facade and a runnable example (§3a).
- Neutral naming: nothing in FoundationModelsRanker may mention chunks, symbols, catalogs,
  or metadata.

**Non-goals**
- No new ranking *signals*, no persistence, no vector store.
- **No changes to CodeContextKit or FoundationModelsMetadataRegistry from
  this repo.** This plan builds FoundationModelsRanker; each consumer's migration onto it
  (and CodeContextKit's future agent-selection search mode) is a separate
  job, planned and executed in that repo. Their code is referenced here only
  as the *source* being ported and the behavioral reference the ported tests
  encode.
- No attempt to make the consumers share a corpus/index type — only the
  primitives, the fusion pipeline, and the selection tier over narrow
  protocols.

## 3. Package design

```
FoundationModelsRanker/
  Package.swift              swift-tools 6.1, platforms: [.macOS("27.0")]
  Sources/
    FoundationModelsRanker/                 ← the one product
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
    FoundationModelsRankerTests/            ported from both repos, verbatim (§5)
```

- **One product, one target.** `FoundationModelsRouter` is a plain required
  dependency (remote URL, `branch: "main"`, matching the family convention
  FMR documents for CI — the shared `swift-ci.yaml` only checks out the
  calling repo, so no local path deps). No product split: both consumers
  already depend on Router, so keeping the core dependency-free buys nothing.
- **macOS 27 floor**, inherited from Router; both consumers are already on
  27, so nothing is lost.
- **Port means copy.** The sibling repos are read-only reference material for
  this entire plan — nothing in `../CodeContextKit` or
  `../FoundationModelsMetadataRegistry` is modified, deleted, or touched.
- Strip the "Ported from CodeContextKit's …" headers on the ported copies and
  replace with a single attribution note (FoundationModelsRanker is now the canonical home;
  lineage: Rust `swissarmyhammer-search` → CodeContextKit → here). Keep all
  doc comments otherwise, minus repo-specific references.

## 3a. The one-call interface (`Searcher`) — the package's front door

FoundationModelsRanker is not just a parts bin: it ships a facade where "a list of things to
search, then a query" is the whole API, and the full monty — BM25 + trigram +
cosine fused by RRF, then agent final selection over the top candidates — is
the *default* behavior, not an assembly project:

```swift
import FoundationModels
import FoundationModelsRouter
import FoundationModelsRanker

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
  FoundationModelsRanker retroactively conforms Apple's `LanguageModelSession` to
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
   domain-neutral in FoundationModelsRanker:
   - `BM25.primaryFieldWeight = 5.0` (CCK's `symbolPathFieldWeight`, FMR's
     `idFieldWeight`)
   - `BM25.bodyFieldWeight = 1.0` (CCK already uses this name; FMR calls it
     `blockFieldWeight`)
2. **`TextEmbedding`** — already identical; take the signature as-is. Doc
   comment rewritten neutrally ("conformers embed a batch of texts; tests
   substitute a deterministic double").
3. **`RoutedEmbedderAdapter`** — take FMR's copy verbatim (it calls Router's
   current `embed(_:)`; CCK's copy carries a stale label and is not the
   canonical source).
4. **Access control** — everything ported stays `public` exactly as it is
   today, so consumers can re-export (`@_exported import FoundationModelsRanker` or local
   typealiases) during their own migrations without breaking their public
   APIs. How each does that is their migration's call, not this plan's.

## 5. Tests that get ported

Copy verbatim (rename suites, drop repo-specific fixtures only where they
reference chunks/catalogs by name) — the source test files stay where they
are:

- CCK `Tests/CodeContextKitTests/RankerTests.swift` (335 ln — BM25, trigram,
  RRF, tokenizer coverage) and the primitive-level parts of
  `EmbeddingSeamTests.swift`.
- FMR `RRFTests.swift`, `TrigramTests.swift` — written against the *same*
  primitives; overlapping cases are fine (keep both; they encode each repo's
  edge-case history).

The consumers keep all their own tests untouched — their pipeline-level
suites (`SearchCodeTests`, `RetrievalSearchTests`, `OverBudgetTests`, …)
become the no-behavior-change proof whenever they run their own migrations
(§6a).

## 6. Phases (all within this repo)

**Phase 1 — extract the identical files**
1. Scaffold `Package.swift`, `README.md` stub, family CI workflow.
2. Port (copy) the six core files + adapter per §3/§4; port tests per §5.
3. `swift test` green; push `main` to `github.com/swissarmyhammer/FoundationModelsRanker`
   so consumers can resolve the dependency whenever they migrate.

**Phase 2 — unify the duplicated pipeline**
Extract the logic §1 lists as structurally duplicated:
- `SignalWeights` (bm25/trigram/cosine, defaults 1.0) — one weights type
  where each source repo has its own.
- `RankedDocument` value type: `init(primaryText:bodyText:)` precomputes the
  weighted term-frequency map, term set, document length, and both trigram
  sets (behavioral reference: `SearchCorpus.preprocessRow` and
  `MetadataIndex`'s build).
- `HybridRanker`: given per-document `RankedDocument`s, optional cosine
  scores, and `SignalWeights`, produce the fused, `[0,1]`-normalized,
  tie-broken ranking plus per-document raw `Signals` — encoding the
  absent-signal rule and `rankingOfPositiveScores` once. Two output shapes:
  top-K matches-only, and full-catalog ordering with a zero-scored tail (the
  selection tier's over-budget candidate source) — so any consumer's
  snapshot/index can map into it.
- `CosineScoring`: the vDSP contiguous-matrix matvec and the scalar
  per-row form, side by side, both available to any consumer.

**Phase 3 — generalize the selection tier, the facade, and the example**

The coupling is narrow — the source tier touches its index only via ids,
per-id item/block lookup, and summary rendering — so the generalization is:

- `SelectionCatalog` protocol (the seam replacing the source's index type):
  `ids: [String]`, `summaryBlock(forId:) -> String?` (seeds the prefix),
  `block(forId:) -> String?` (the verbatim result payload). Any index or
  snapshot type can conform trivially.
- Port (copy) `SelectionTier`, `SelectionConfig` (session factory, preamble,
  `capacityCharacterLimit`, `candidateLimit`), `Selection` (`@Generable` —
  brings the FoundationModels system framework import, fine at the macOS 27
  floor), `AgentSession`, and `idEnumGrammar(ids:)` (already uses Router's
  `Grammar`, which FoundationModelsRanker links anyway).
- Neutral diagnostics: a small `RankDiagnostic` enum for
  `.retrievalCut(considered:kept:)` / `.unknownSelectedId(id:)`; consumers
  map it into their own diagnostics or logging.
- Everything selection-shaped keeps its semantics verbatim: under-budget
  cached-root + fork-per-call, over-budget retrieval top-M into a one-off
  session, ids-only grammar-constrained output, verbatim block lookup.
- **Selection prompt: default in FoundationModelsRanker, override per consumer.** The
  prompt is `SelectionConfig.preamble` (the full prefix is preamble +
  `# Candidates` + each candidate's summary block, assembled in
  `SelectionTier.assemblePrefix`). FoundationModelsRanker ships the default —
  `String.selectionDefault`, the proven librarian guidance with neutral
  wording ("return ONLY the items needed — fewest that suffice, in call
  order when order matters; do not invent ids; return an empty list if
  nothing fits"). Consumers pass their own domain-flavored guidance via the
  `preamble:` parameter, keeping their model-visible prompts under their
  own control.
- Conform Apple's `LanguageModelSession` to `AgentSession` (retroactive
  conformance in FoundationModelsRanker) so any FoundationModels model — `.fast`,
  `.default`, adapter-loaded — plugs into the selection seam without Router
  (§3a: the model is never hardcoded).
- Build the `Searcher` facade (§3a) and the `Examples/FullMonty` targets —
  they compose the phase-2 ranker with this tier and are the package's
  front door and living documentation.
- Port the source repo's `SelectionTests`/`OverBudgetTests` alongside.
  `Searcher` gets its own suite against scripted `AgentSession` fakes and a
  fake embedder.

## 6a. Follow-on work — separate jobs, out of scope here

Each of these gets planned and executed **in its own repo**, against FoundationModelsRanker
`main`; this plan deliberately does not spec them:

- **CodeContextKit**: migrate onto FoundationModelsRanker (drop its primitive copies, adopt
  the shared types), and later add an agent-selection mode to `search code`
  over its RRF candidates.
- **FoundationModelsMetadataRegistry**: migrate onto FoundationModelsRanker (drop its
  ported copies, adopt the shared tier, keep its librarian preamble and
  `MetadataDiagnostic` surface).
- After those migrations: each repo verifies its own downstream dependents.

## 7. Risks (this repo)

- **Remote `branch: "main"` dependency**: once consumers adopt FoundationModelsRanker, a
  regression here breaks their CI. Same tradeoff the family already accepts
  for FoundationModelsRouter; the ported test suite is the guard — keep
  `main` green.
- **FoundationModels API assumptions**: the `.fast`/`.default` model
  spellings and the feasibility of a retroactive `LanguageModelSession`
  conformance must be verified against the macOS 27 SDK in phase 3 — fall
  back to a thin wrapper type if the retroactive conformance fights the
  class's actual API surface.
- **`fork()` semantics for plain `LanguageModelSession`s**: the tier's
  under-budget path assumes fork-per-call; a session type without native
  fork needs either a factory-recreated fresh session or documented
  transcript-accumulation behavior — decide and test in phase 3.
