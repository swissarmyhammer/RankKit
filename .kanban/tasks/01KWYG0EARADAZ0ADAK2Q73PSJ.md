---
comments:
- actor: claude-code
  id: 01kxdxnsevn3pb66h1mypd0r91
  text: |-
    Implemented via TDD. Added Sources/RankKit/RankedDocument.swift: a Sendable, Equatable value type whose init(primaryText:bodyText:) precomputes weightedTermFrequency ([String:Double], BM25.primaryFieldWeight/bodyFieldWeight folded per token per field), termSet (Set(weightedTermFrequency.keys)), documentLength (unweighted token count across both fields), primaryTrigramSet and bodyTrigramSet (Trigram.canonicalTrigramSet(text:) per field) — verified against CodeContextKit's SearchCorpus.preprocessRow and FMR's MetadataIndex build step, which use identical logic modulo field naming (RankKit already carries the primaryFieldWeight/bodyFieldWeight rename from an earlier task).

    Wrote Tests/RankKitTests/RankedDocumentTests.swift first (11 tests) with hand-traced literal fixtures (not by re-invoking Tokenizer/Trigram in the test, to avoid circularity) covering: field weight application, overlapping-term summation across fields and occurrences, termSet derivation, documentLength as unweighted count, per-field canonical trigram sets (including multi-word canonicalization), empty primary, empty body, empty both, unicode/grapheme-cluster trigramming, and Sendable conformance. Confirmed RED (build failure: "cannot find 'RankedDocument' in scope") before implementing, then GREEN after.

    swift test: 78/78 tests pass across 6 suites (no failures). swift build: clean except one pre-existing, unrelated MLX dependency resource-bundle warning (not from RankKit source). No regressions in existing BM25Tests/RRFTests/TrigramTests/RankerTests/PackageTests.

    Ready for really-done / review.
  timestamp: 2026-07-13T14:21:40.187425+00:00
depends_on:
- 01KWYFZ70DH9VZR2CRJNFJTDNE
position_column: done
position_ordinal: '8380'
title: Add RankedDocument precompute type
---
## What\nCreate `Sources/RankKit/RankedDocument.swift` (plan.md §6 phase 2): a value type whose `init(primaryText:bodyText:)` precomputes everything the per-signal scorers need for one document:\n- field-weighted term-frequency map (`primaryFieldWeight` × primary tokens + `bodyFieldWeight` × body tokens)\n- term set (`Set(weightedTermFrequency.keys)`)\n- document length (unweighted token count across both fields)\n- canonical trigram sets for primary and body text\n\nThis replaces the duplicated precompute in `../CodeContextKit/Sources/CodeContextKit/Search/SearchCorpus.swift` (`preprocessRow`) and FMR's `MetadataIndex` build — use those two implementations as the behavioral reference.\n\n## Acceptance Criteria\n- [x] For identical inputs, `RankedDocument` produces the same weighted term frequencies, term sets, document lengths, and trigram sets as CCK's `preprocessRow` (assert against hand-computed fixtures derived from that code)\n- [x] Type is `Sendable`, pure, and has no storage/corpus dependencies\n\n## Tests\n- [x] `Tests/RankKitTests/RankedDocumentTests.swift`: fixture texts with known token/trigram outcomes; cases for empty primary, empty body, overlapping terms (weight summation), unicode text\n- [x] Run `swift test` — exits 0\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.