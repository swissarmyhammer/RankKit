---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxrazmd111qep5yq06zc71sr
  text: |-
    Skipping for now in this /finish batch — not actually actionable yet, despite showing READY.

    FoundationModelsMetadataRegistry/Package.swift:200 resolves FoundationModelsRanker as a remote GitHub dependency pinned to `branch: "main"`, not a local path override. The forId→forID rename landed in Ranker only as LOCAL commits on this machine (^xqrbq19's checkpoints, final eb521d8) — /finish's contract is commit-only, never push. Until those commits reach github.com/swissarmyhammer/FoundationModelsRanker's main branch, `swift package resolve`/`update` here will keep pulling the OLD (still-`forId`) Ranker, so renaming MetadataIndex's conformance now would break the build against the actual resolved dependency, not fix it — exactly backwards from the goal.

    Needs a human to push FoundationModelsRanker's main branch first (a git push is outside what /finish or its subagents do unprompted). Leaving this in `todo`/ready per the board, but it will not make real progress until that push happens. Proceeding with ^c79yg0f and ^rayd7bq instead, which are Ranker-only and don't have this cross-repo dependency.
  timestamp: 2026-07-17T15:26:38.497512+00:00
position_column: todo
position_ordinal: '8380'
title: Rename MetadataIndex's SelectionCatalog conformance to forID (paired with Ranker ^xqrbq19)
---
## What

`FoundationModelsRanker` task ^xqrbq19 renamed `SelectionCatalog`'s two requirements from the `forId` spelling to `forID` (interior acronyms uniformly uppercase), per review finding. `FoundationModelsRanker` is green.

`FoundationModelsMetadataRegistry` is a **downstream conformer** and depends on Ranker as a remote package pinned to `branch: "main"`, so this breaks on its next dependency resolve — not at a future version bump.

`Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift`, `extension MetadataIndex: SelectionCatalog`:

- `summaryBlock(forId id: String)` — **breaks**. The protocol now requires `summaryBlock(forID:)`, which does not exist on `MetadataIndex`; the `forId` shim is its only `summaryBlock`.
- `block(forId id: String)` — becomes **redundant**. It is a shim whose body is just `block(forID: id)`; the protocol's `block(forID:)` requirement is already satisfied directly by the pre-existing native `public func block(forID id: String)`.

Both shims exist only to bridge the protocol's old spelling — their own doc comments say so ("the two lookups forward to this index's existing accessors under the protocol's `forId` spelling"; "This is `block(forID:)` under the protocol's spelling"). MetadataRegistry already renamed its own API to `forID` in commit `e1770d8`, so this finishes that migration rather than diverging from it.

## Acceptance Criteria

- [ ] `summaryBlock(forId:)` renamed to `summaryBlock(forID:)` in the `SelectionCatalog` conformance
- [ ] Redundant `block(forId:)` shim deleted — native `block(forID:)` satisfies the requirement directly
- [ ] Conformance-extension doc comments updated (drop the now-stale "under the protocol's `forId` spelling" rationale)
- [ ] Doc comments use the parameter binding name (`- Parameter id:`, not `- Parameter forId:`) per the same convention that drove ^xqrbq19
- [ ] `swift test` green in FoundationModelsMetadataRegistry

## Sequencing

Land **after** Ranker ^xqrbq19 is committed to `main` (MetadataRegistry tracks that branch). Until both land, MetadataRegistry will not build against Ranker main.