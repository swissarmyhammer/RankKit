# FoundationModelsRanker

[![CI](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml)

Hybrid search and ranking for Swift: give it a list of things and a query,
get back ranked results. Under the hood it fuses BM25 keyword matching,
trigram fuzzy matching, and (optionally) cosine similarity by reciprocal
rank fusion, then optionally lets an agent make the final pick from the top
candidates. Targets macOS 27+ and depends on
[FoundationModelsRouter](https://github.com/swissarmyhammer/FoundationModelsRouter).

```swift
import FoundationModelsRanker

// The things to search: an id and the text that describes it.
let items = [
    SearchItem(id: "grep",  text: "Search file contents with regular expressions"),
    SearchItem(id: "glob",  text: "Find files by name pattern, sorted by mtime"),
    SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    // ...hundreds more...
]

// Zero config: BM25 + trigram retrieval fused by RRF narrows the field,
// then an agent picks the final result on the on-device system model.
let searcher = try await Searcher(items)
let hits = try await searcher.search("how do I find TODO comments in my code")
// hits[0].id == "grep" -- the agent's pick, carrying the real fused
// .score and per-signal .signals retrieval reports for the query
```

Any `LanguageModelSession` works — the model is never hardcoded. This is
exactly what the zero-config call above does under the hood
(`Searcher.defaultSessionFactory`); pass a session factory explicitly to
swap it for something else:

```swift
import FoundationModels

let searcher = try await Searcher(items, session: { instructions in
    LanguageModelSession(model: .default, instructions: instructions)
})
```

The full monty: a Router adds the embedder (cosine joins the fused ranking)
and supplies the selection session too — still just arguments. See
[`Examples/FullMonty`](Examples/FullMonty) for the runnable version,
including how to resolve `profile` from a live `Router`:

```swift
import FoundationModelsRouter
import FoundationModelsRanker

let grammar = try SelectionTier.idEnumGrammar(ids: items.map(\.id))
let searcher = try await Searcher(
    items,
    embedder: RoutedEmbedderAdapter(routedEmbedder: profile.embedding),
    session: { instructions in
        RoutedAgentSession(session: profile.standard.makeGuidedSession(grammar: grammar, instructions: instructions))
    }
)
```

## Modes

`mode:` picks which tier `search(_:limit:)` answers through — defaults to
`.auto`:

- `.retrieval` — the fused BM25 + trigram (+ cosine) ranking only; no
  session is ever consulted. Results carry the real fused `score` and
  per-signal `.signals`.
- `.selection` — an agent picks from the top candidates; throws if no
  `session:` is configured. Picks carry the real fused `score` and
  per-signal `.signals` retrieval reports for the query: when the item
  list fits the selection budget the whole catalog stays selectable and is
  ranked once per search to attach those scores (one query-embedding call
  when an `embedder:` is configured); once it doesn't fit, the one-off
  fallback seeds itself from the top retrieval candidates.
- `.auto` — selection when a session is configured, retrieval otherwise
  (the lead example's zero-config call resolves here).

## Graceful degradation

Every fallback is reported, never silent: no `embedder` (or a failed query
embed) drops to keyword-only retrieval and reports `.embeddingUnavailable`
via `onDiagnostic`; `mode: .selection` with no session throws
`SelectionTierUnavailable`; `mode: .auto` degrades to retrieval instead of
failing.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsRanker", branch: "main")
```

## License

No license file is included in this repository.
