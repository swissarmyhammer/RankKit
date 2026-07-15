---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxhh7tkgnr2h1cjtx0gynp30
  text: 'Picked up by /finish (scoped-batch, no filter). Starting iteration 1: /implement → /test → /commit checkpoint → /review.'
  timestamp: 2026-07-15T00:01:17.424372+00:00
- actor: claude-code
  id: 01kxhhb382e29h7c0m2dpved9c
  text: 'Picked up by /implement. Found the RED test idEnumGrammarBoundsIdsWithMaxItemsAtTheCandidateCount already present as an uncommitted change in Tests/FoundationModelsRankerTests/SelectionTests.swift (left by a prior iteration); the implementation in Sources/FoundationModelsRanker/Selection/SelectionTier.swift is untouched. Verified RED: swift test --filter idEnumGrammarBoundsIdsWithMaxItemsAtTheCandidateCount fails with idsSchema["maxItems"] as? Int → nil. Now adding maxItems = ids.count to idEnumGrammar(ids:).'
  timestamp: 2026-07-15T00:03:04.578573+00:00
- actor: claude-code
  id: 01kxhhf4q22f0r64pfq5s2v6hg
  text: 'Implementation landed: idEnumGrammar(ids:) in Sources/FoundationModelsRanker/Selection/SelectionTier.swift now sets idsSchema["maxItems"] = ids.count (with a why-comment about xgrammar ignoring uniqueItems), and the function doc comment mentions the cap. Verified GREEN: the new test idEnumGrammarBoundsIdsWithMaxItemsAtTheCandidateCount passes, full `swift test` = 194 tests in 17 suites, all passing. Only build warnings are pre-existing package-level ones (swift-jinja unused dependency, mlx bundle node) — untouched by this change. Running double-check next.'
  timestamp: 2026-07-15T00:05:17.154395+00:00
- actor: claude-code
  id: 01kxhhnj0jrq9c7b0rbpth6fm1
  text: 'Double-check verdict: REVISE with a single Low, comment-only finding — the matches(forIds:) doc comment still cited uniqueItems as structurally enforced, contradicting the new xgrammar-ignores-uniqueItems rationale. Fixed exactly as suggested: unknown-id unreachability now attributed to the per-element enum constraint alone, and the dedup note explains duplicates are structurally possible (uniqueItems ignored; maxItems only bounds count). Everything else verified good by the critic: no other hand-rolled grammar builders (LiveRouter.swift calls the shared public idEnumGrammar), empty-ids case emits maxItems: 0 correctly, runtime dedup/allowedIds defenses intact. Fresh full run after the doc fix: swift test → 194 tests in 17 suites, all passed. Not re-spawning double-check for a comment-only touch-up (bounded loop, justification logged here). All acceptance criteria met; task left in doing, ready for /review. Note for the orchestrator: the RED test in SelectionTests.swift was already present uncommitted when this iteration started (left by a prior iteration) — it is part of this task''s change set.'
  timestamp: 2026-07-15T00:08:47.378438+00:00
- actor: claude-code
  id: 01kxhjahftdwba9a6ytx2re353
  text: /finish complete in 1 iteration. Implement landed the maxItems cap + regression test; full suite green (194 tests / 17 suites, 0 warnings); checkpoint commit 61baca3 on main (not pushed); review of HEAD~1..HEAD came back clean → done. The one engine finding (extract shared JSON-schema parsing helper across 4 grammar tests) was dropped under the review skill's blanket exception against refactoring existing tests.
  timestamp: 2026-07-15T00:20:14.970734+00:00
position_column: done
position_ordinal: 8d80
title: Cap SelectionTier.idEnumGrammar ids array with maxItems to stop runaway generation (port of registry fix 98a91db)
---
## What

Port `FoundationModelsMetadataRegistry` commit `98a91db` ("fix(selection): cap idEnumGrammar ids array with maxItems to stop runaway generation") to this package's own copy of the selection grammar builder.

When the selection code was extracted from the registry into `FoundationModelsRanker`, the copy came over WITHOUT the `maxItems` cap: `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`'s `idEnumGrammar(ids:)` (around line 303) injects `enum` + `uniqueItems: true` into the `ids` array schema but never sets `maxItems`. The xgrammar pipeline (via Router's `RuntimeJSONSchemaConverter` → `DynamicGenerationSchema(maximumElements:)` → Apple `GenerationSchema` Codable → xgrammar `json_schema_converter.cc`) enforces `minItems`/`maxItems` but silently ignores `uniqueItems`, so the compiled grammar permits an unbounded-length array of repeated enum members.

Empirically confirmed 2026-07-14 on real hardware (M3 Ultra, Qwen2.5-1.5B-Instruct-4bit, via FoundationModelsMultitool's gated `PrefixReuseTests`): an off-topic selection intent deterministically produced a ~6150-token repeated-id runaway (~190-195s wall clock); adding `maxItems = ids.count` to the effective grammar bounded it to ~2.5s. `grep -rn maxItems Sources/` in this repo returns nothing — the whole package lacks the cap.

## Fix

In `idEnumGrammar(ids:)`, set `maxItems` on the `ids` array subschema to `ids.count`, mirroring the registry's fixed copy verbatim (a selection can never legitimately contain more ids than there are candidates).

## Acceptance Criteria

- [ ] `SelectionTier.idEnumGrammar(ids:)`'s emitted JSON schema contains `"maxItems": <ids.count>` on the `ids` array.
- [ ] A unit test asserts the cap equals the candidate count (mirror the registry's `SelectionTests` addition from 98a91db).
- [ ] Full `swift test` remains green.
