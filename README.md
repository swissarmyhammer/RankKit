# RankKit

[![CI](https://github.com/swissarmyhammer/RankKit/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/RankKit/actions/workflows/ci.yml)

Shared hybrid-search and ranking primitives — BM25 + trigram + cosine retrieval fused by
reciprocal rank fusion, plus an optional LLM-driven selection tier — extracted so
CodeContextKit and FoundationModelsMetadataRegistry can depend on one canonical copy
instead of maintaining duplicates. Targets macOS 27+ and Swift 6.1.

This package is in early scaffolding; see [`plan.md`](plan.md) for the full extraction
design and phased rollout.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/RankKit", branch: "main")
```

## License

No license file is included in this repository.
