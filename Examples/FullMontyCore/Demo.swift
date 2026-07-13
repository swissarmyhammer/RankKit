// `FullMonty`'s entry logic (plan.md §3a): runs `demoQueries` against
// `toolCatalog` through the `Searcher` facade and formats the results —
// factored into this library target (rather than living directly in
// `FullMonty`'s `main.swift`) so `ExamplesSmokeTests` can invoke every
// GPU-free path directly, with no `swift run` subprocess spawning, mirroring
// FoundationModelsMetadataRegistry's `CatalogSearchCore`/`SemanticSearchCore`
// pattern.
//
// New to RankKit — no source file to port (plan.md §3a).

import Foundation
import RankKit

/// One `demoQueries` entry's result: the query itself, alongside its ranked
/// or selected matches.
public typealias FullMontyResult = (query: String, matches: [SelectionMatch])

/// Runs every `demoQueries` entry against `toolCatalog` through a `Searcher`
/// built from the given ingredients — the shared plumbing every one of
/// `FullMonty`'s three paths (`--no-model`, the default on-device-system-
/// model path, and the `RANKKIT_INTEGRATION_TESTS`-gated live-Router path)
/// drives through, differing only in which `embedder`/`session` they supply.
///
/// - Parameters:
///   - embedder: embeds `toolCatalog` and every query for the cosine signal,
///     or `nil` for keyword-only retrieval.
///   - session: creates a selection session, or `nil` to leave selection
///     unavailable (`mode` should then be `.retrieval`).
///   - mode: which tier `Searcher.search(_:limit:)` answers through.
///     Defaults to `.auto`.
///   - limit: the maximum number of matches per query. Defaults to `5`.
///   - onDiagnostic: called for every diagnostic `Searcher` emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `Searcher.init` or `Searcher.search(_:limit:)` throws.
public func runFullMontyDemo(
    embedder: (any TextEmbedding)?,
    session: (@Sendable (String) -> any AgentSession)?,
    mode: Searcher.Mode = .auto,
    limit: Int = 5,
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    let searcher = try await Searcher(
        toolCatalog,
        embedder: embedder,
        session: session,
        mode: mode,
        onDiagnostic: onDiagnostic
    )
    var results: [FullMontyResult] = []
    results.reserveCapacity(demoQueries.count)
    for query in demoQueries {
        results.append((query: query, matches: try await searcher.search(query, limit: limit)))
    }
    return results
}

/// `--no-model`'s degraded, GPU-free path (plan.md §3a "the CI-safe path"):
/// no embedder (keyword-only BM25 + trigram retrieval), no selection
/// session — `mode: .retrieval` so `Searcher.search(_:limit:)` never even
/// tries to consult a model.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` emits —
///   `.embeddingUnavailable` fires on every search this path runs, since no
///   embedder is configured.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws.
public func runNoModelDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    try await runFullMontyDemo(embedder: nil, session: nil, mode: .retrieval, onDiagnostic: onDiagnostic)
}

/// The default path run with no flags and no gated env var set: no
/// embedder (still keyword-only retrieval signal-wise — a live embedder
/// needs the gated Router path), but `session:
/// Searcher.defaultSessionFactory` so `mode: .auto` drives real selection
/// on the on-device system model.
///
/// Explicitly passes `Searcher.defaultSessionFactory` (rather than omitting
/// `session:` and letting `Searcher.init`'s own default argument supply it)
/// so this call site documents the exact swap point plan.md §3a's
/// `--model default` flag was meant to demonstrate — see this package's
/// `Searcher.swift` header for why: the installed SDK exposes only
/// `SystemLanguageModel.default`, not `.fast`, so `defaultSessionFactory`
/// already *is* `.default`; there is no longer a second value to swap to,
/// so `FullMonty` ships no `--model` flag.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws — in particular, whatever the on-device system model session
///   throws if Apple Intelligence is unavailable on this machine.
public func runDefaultDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    try await runFullMontyDemo(embedder: nil, session: Searcher.defaultSessionFactory, mode: .auto, onDiagnostic: onDiagnostic)
}

// MARK: - Printing

/// Prints `toolCatalog`, one line per tool — used by every path so a run
/// always shows what's being searched.
public func printCatalog() {
    print("FullMonty catalog (\(toolCatalog.count) tools):")
    for item in toolCatalog {
        print("- \(item.id): \(item.text)")
    }
}

/// Formats one query's matches, one line each, with their per-signal
/// breakdown when retrieval produced one — mirrors
/// FoundationModelsMetadataRegistry's `Examples/ExamplesSupport
/// .formattedMatches(matches:)`, adapted to RankKit's catalog-agnostic
/// `SelectionMatch` (no generic `Item`).
///
/// - Parameter matches: the matches to format, in ranked or selected order.
/// - Returns: one formatted line per match, joined by newlines, or a
///   placeholder line when `matches` is empty.
public func formattedMatches(_ matches: [SelectionMatch]) -> String {
    guard !matches.isEmpty else { return "(no matches)" }
    return matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "selection (no retrieval signals)"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}

/// Prints every `FullMontyResult`, one query block at a time.
///
/// - Parameter results: the results to print, in query order.
public func printResults(_ results: [FullMontyResult]) {
    for result in results {
        print("Query: \"\(result.query)\"")
        print(formattedMatches(result.matches))
        print("")
    }
}

/// Prints one diagnostic `Searcher` or its selection tier emitted — RankKit
/// itself never logs on a caller's behalf (`RankDiagnostic.swift`'s header),
/// so every `Examples/` target owns printing its own.
///
/// - Parameter diagnostic: the diagnostic to print.
public func printDiagnostic(_ diagnostic: RankDiagnostic) {
    print("[diagnostic] \(diagnostic)")
}
