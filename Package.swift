// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, following the pattern established by the
/// sibling FoundationModelsRouter and FoundationModelsMetadataRegistry
/// packages.
let packageName = "RankKit"

/// The name of the FoundationModelsRouter dependency package.
///
/// Wired as a remote dependency (`main` branch) rather than a local path
/// dependency, matching the family convention FoundationModelsMetadataRegistry
/// documents for CI — the shared `swift-ci.yaml` reusable workflow only
/// checks out the calling repo, so a local path dependency would never
/// resolve there (plan.md §3).
let routerDependencyName = "FoundationModelsRouter"

/// The SwiftPM manifest for RankKit (plan.md §3).
///
/// Phase 1 scaffold: a single library target depending on
/// FoundationModelsRouter, and a Swift Testing unit test target. The ported
/// retrieval primitives, the selection tier, and the `Examples/` targets
/// land in later phases (plan.md §6).
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
        .package(url: "https://github.com/swissarmyhammer/\(routerDependencyName)", branch: "main")
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
                .target(name: packageName)
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ]
)
