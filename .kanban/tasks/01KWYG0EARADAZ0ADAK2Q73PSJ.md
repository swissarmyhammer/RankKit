---
depends_on:
- 01KWYFZ70DH9VZR2CRJNFJTDNE
position_column: todo
position_ordinal: '8680'
title: Add RankedDocument precompute type
---
## What
Create `Sources/RankKit/RankedDocument.swift` (plan.md §6 phase 2): a value type whose `init(primaryText:bodyText:)` precomputes everything the per-signal scorers need for one document:
- field-weighted term-frequency map (`primaryFieldWeight` × primary tokens + `bodyFieldWeight` × body tokens)
- term set (`Set(weightedTermFrequency.keys)`)
- document length (unweighted token count across both fields)
- canonical trigram sets for primary and body text

This replaces the duplicated precompute in `../CodeContextKit/Sources/CodeContextKit/Search/SearchCorpus.swift` (`preprocessRow`) and FMR's `MetadataIndex` build — use those two implementations as the behavioral reference.

## Acceptance Criteria
- [ ] For identical inputs, `RankedDocument` produces the same weighted term frequencies, term sets, document lengths, and trigram sets as CCK's `preprocessRow` (assert against hand-computed fixtures derived from that code)
- [ ] Type is `Sendable`, pure, and has no storage/corpus dependencies

## Tests
- [ ] `Tests/RankKitTests/RankedDocumentTests.swift`: fixture texts with known token/trigram outcomes; cases for empty primary, empty body, overlapping terms (weight summation), unicode text
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.