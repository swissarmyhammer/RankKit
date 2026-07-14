// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, following the pattern established by the
/// sibling FoundationModelsRouter and FoundationModelsMetadataRegistry
/// packages.
let packageName = "FoundationModelsRanker"

/// The name of the FoundationModelsRouter dependency package.
///
/// Wired as a remote dependency (`main` branch) rather than a local path
/// dependency, matching the family convention FoundationModelsMetadataRegistry
/// documents for CI — the shared `swift-ci.yaml` reusable workflow only
/// checks out the calling repo, so a local path dependency would never
/// resolve there (plan.md §3).
let routerDependencyName = "FoundationModelsRouter"

/// The `mlx-swift-lm` fork's package name.
///
/// The same remote dependency FoundationModelsRouter itself declares;
/// re-declared here with the identical URL/branch so SwiftPM's dependency
/// resolution unifies the two into a single resolved checkout, never a
/// duplicate, so `FullMontyCore` can import `MLXHuggingFace`'s
/// `#hubDownloader()` / `#huggingFaceTokenizerLoader()` macros to build a
/// live `Router` for its gated real-model path (plan.md §3a) — the only
/// place this package touches MLX directly.
let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client package name.
///
/// `FullMontyCore` links this to supply `LiveModelLoader`'s `Downloader`,
/// mirroring FoundationModelsRouter's own gated integration suite and
/// FoundationModelsMetadataRegistry's `Examples/SemanticSearch` demo. Needed
/// only by `FullMontyCore`'s live-Router path; the library target never
/// imports it.
let huggingFacePackage = "swift-huggingface"

/// The Hugging Face Transformers package name.
///
/// Its `Tokenizers` product supplies `LiveModelLoader`'s `TokenizerLoader`
/// alongside `huggingFacePackage`'s `Downloader`. Needed only by
/// `FullMontyCore`'s live-Router path; the library target never imports it.
let transformersPackage = "swift-transformers"

/// The Router/MLX/Hugging Face product quintet that resolves a real
/// `Router` + `LiveModelLoader`: FoundationModelsRouter itself, MLX's
/// Hugging Face hub + LM-common products, and the Hugging Face
/// hub/transformers products.
///
/// Mirrors FoundationModelsMetadataRegistry's own
/// `liveRouterProductDependencies` (plan.md §3a "example-only MLX/Hugging
/// Face product dependencies attach to the example targets, never the
/// library"). Attaches only to `FullMontyCore`; the library target's own
/// `FoundationModelsRouter` dependency below stays exactly as it was.
let liveRouterProductDependencies: [Target.Dependency] = [
    .product(name: routerDependencyName, package: routerDependencyName),
    .product(name: "MLXHuggingFace", package: mlxPackage),
    .product(name: "MLXLMCommon", package: mlxPackage),
    .product(name: "HuggingFace", package: huggingFacePackage),
    .product(name: "Tokenizers", package: transformersPackage),
]

/// The SwiftPM manifest for FoundationModelsRanker (plan.md §3).
///
/// A single library target depending on FoundationModelsRouter, a Swift
/// Testing unit test target, and the `Examples/FullMonty` /
/// `Examples/FullMontyCore` targets (plan.md §3a): the package's runnable
/// living proof of the `Searcher` facade — demo only, never a dependency of
/// the library. `FullMonty`'s entry logic lives in `FullMontyCore` (a plain
/// library target, not the executable itself) so the test target can
/// `@testable import` and invoke it directly as a plain library dependency,
/// mirroring FoundationModelsMetadataRegistry's `*Core` example targets.
let package = Package(
    name: packageName,
    // Commit to macOS 27 / FoundationModels v2; floor inherited from
    // FoundationModelsRouter, matching both consumer repos (plan.md §3).
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swissarmyhammer/\(routerDependencyName)", branch: "main"),
        .package(url: "https://github.com/swissarmyhammer/\(mlxPackage)", branch: "foundationmodels-fixes"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackage)", from: "1.3.0"),
        // Pinned below swift-jinja 2.4.0 for the same reason
        // FoundationModelsMetadataRegistry's `Package.swift` pins it: that
        // release changed `Value.object` to key on `ObjectKey` instead of
        // `String`, which the latest tagged swift-transformers never
        // adopted — `Sources/Hub/Config.swift` fails to compile against
        // 2.4.0. `transformersPackage` only constrains jinja to `from:
        // "2.0.0"`, so without this upper bound `swift package update`
        // silently drifts onto the broken release.
        .package(url: "https://github.com/huggingface/swift-jinja.git", "2.0.0"..<"2.4.0"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName)
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: "FullMontyCore"),
            ],
            path: "Tests/\(packageName)Tests"
        ),
        // `FullMonty`'s entry logic (plan.md §3a): a fixture catalog of ~50
        // developer-tool items, a handful of queries, printed matches with
        // per-signal scores and the model's final selection — the living
        // proof of the `Searcher` facade documented in `Searcher.swift`'s
        // header. A plain library (not the executable itself) so
        // `ExamplesSmokeTests` can invoke its GPU-free paths directly.
        // Depends on the full `liveRouterProductDependencies` quintet for
        // its gated real-model path (behind `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS`);
        // every other path (the default on-device-system-model path, and
        // `--no-model`) never touches them.
        .target(
            name: "FullMontyCore",
            dependencies: [.target(name: packageName)] + liveRouterProductDependencies,
            path: "Examples/FullMontyCore"
        ),
        // A thin runnable entry point over `FullMontyCore`. `swift build`
        // compiles this GPU-free; `swift run FullMonty --no-model` runs the
        // degraded keyword-only path GPU-free; the default (on-device
        // system model) and `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS`-gated (live Router)
        // paths need Apple Intelligence / a live Router respectively.
        .executableTarget(
            name: "FullMonty",
            dependencies: [.target(name: "FullMontyCore")],
            path: "Examples/FullMonty"
        ),
    ]
)
