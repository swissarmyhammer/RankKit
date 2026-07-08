---
depends_on:
- 01KWYFYV2BQ968Y1RHQXRSP6NQ
position_column: todo
position_ordinal: '8280'
title: Port BM25 with neutral field-weight names
---
## What
Copy `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Search/BM25.swift` → `Sources/RankKit/BM25.swift`, applying the one deliberate rename (plan.md §4.1):
- `idFieldWeight` → `primaryFieldWeight` (value stays `5.0`)
- `blockFieldWeight` → `bodyFieldWeight` (value stays `1.0`)

Rewrite the constants' doc comments neutrally ("primary field" / "body field" — no ids, blocks, symbol paths). Strip the port-attribution header like the other files. `BM25Corpus` and `score(...)` stay byte-identical.

After this and the other two port tasks are green, push RankKit `main` to GitHub so consumers can resolve the remote dependency when they migrate (their migration is planned separately, in their own repos).

## Acceptance Criteria
- [ ] `BM25.primaryFieldWeight == 5.0`, `BM25.bodyFieldWeight == 1.0`
- [ ] Scoring behavior identical to both existing copies (ported tests pass unmodified apart from constant names/imports)
- [ ] No domain language in doc comments

## Tests
- [ ] Port the BM25 cases from `../CodeContextKit/Tests/CodeContextKitTests/RankerTests.swift` AND from `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/BM25Tests.swift` to `Tests/RankKitTests/BM25Tests.swift` (keep both repos' cases — they encode each repo's edge-case history, plan.md §5), updating only constant names/imports
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — port the tests first (failing), then the source file to make them pass.