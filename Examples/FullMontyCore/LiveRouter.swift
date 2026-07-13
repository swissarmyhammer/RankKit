// `FullMonty`'s gated real-model path (plan.md §3a): "with the family's
// gated env var set it instead resolves a live Router + tiny mlx-community
// model for both the embedder and the selection session, exactly like FMR's
// Librarian/SemanticSearch examples." Mirrors
// FoundationModelsMetadataRegistry's `Examples/LiveRouterSupport` pattern —
// resolve one profile through a live `Router`, adapt its `.embedding` slot
// as a `TextEmbedding`, and grammar-constrain its `.standard` slot for
// selection — folded directly into this target rather than split into its
// own `LiveRouterSupport` target, since `FullMonty` is (so far) RankKit's
// only example with a gated path to share it with.
//
// New to RankKit — no source file to port (plan.md §3a); the shape is
// FoundationModelsMetadataRegistry's own `LiveRouterSupport
// .resolveLiveProfile(demoLabel:name:description:)` /
// `buildLiveEmbedder(demoLabel:name:description:)`, generalized to build
// `Searcher`'s plain `(String) -> any AgentSession` seam instead of a
// `SelectionConfig`. The id-enum grammar itself is not reimplemented here:
// `SelectionTier.idEnumGrammar(ids:)` is `public`, so this file calls it
// directly rather than hand-rolling the same JSON Schema construction FMR's
// own copy duplicates.

import Foundation
import FoundationModelsRouter
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import RankKit
import Tokenizers

/// Environment variable enabling FullMonty's real-model path (name: `rankKitIntegrationEnvVar`).
///
/// The opt-in environment variable gating `FullMonty`'s real-model path
/// (plan.md §3a), mirroring FoundationModelsMetadataRegistry's own
/// `METADATA_REGISTRY_INTEGRATION_TESTS` convention. Unset (the default),
/// `FullMonty` never touches the network or GPU.
public let rankKitIntegrationEnvVar = "RANKKIT_INTEGRATION_TESTS"

/// Whether `FullMonty`'s gated real-model path is enabled for this run.
public var isRankKitIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[rankKitIntegrationEnvVar] != nil
}

/// The tiny, deliberately small `mlx-community` models FullMonty's gated path resolves.
///
/// Cheap enough for a local demo run, matching the model pair
/// FoundationModelsMetadataRegistry's own gated `Examples/` demos share.
private enum LiveDemoModels {
    static let generation: ModelRef = "mlx-community/SmolLM-135M-Instruct-4bit"
    static let embedding: ModelRef = "mlx-community/bge-small-en-v1.5-4bit"
}

/// Resolves a real, on-device model profile through a live Router.
///
/// The one path `FullMonty`'s real-model story touches the network/GPU
/// through. Mirrors FoundationModelsRouter's own gated integration suite and
/// FoundationModelsMetadataRegistry's `LiveRouterSupport
/// .resolveLiveProfile(demoLabel:name:description:)`.
///
/// - Returns: the resolved profile, with `.standard` and `.embedding` slots
///   ready for `runLiveFullMontyDemo(onDiagnostic:)` to drive.
/// - Throws: whatever `Router.resolve(profile:reporting:)` throws.
public func resolveLiveFullMontyProfile() async throws -> LanguageModelProfile {
    let recordingsDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FullMonty-\(UUID().uuidString)", isDirectory: true)
    let router = Router(
        recordingsDir: recordingsDir,
        loader: LiveModelLoader(
            downloader: #hubDownloader(),
            tokenizerLoader: #huggingFaceTokenizerLoader()
        )
    )
    let profileDefinition = ProfileDefinition(
        name: "full-monty-demo",
        description: "Tiny co-resident models sized for a local demo run of RankKit's full pipeline.",
        standard: [LiveDemoModels.generation],
        flash: [LiveDemoModels.generation],
        embedding: [LiveDemoModels.embedding]
    )
    return try await router.resolve(profile: profileDefinition, reporting: ResolutionProgress())
}

/// Runs the full demo over a live Router-resolved profile with embedding and selection.
///
/// `profile.embedding` joins retrieval's cosine signal, and
/// `profile.standard` answers selection through a grammar-constrained
/// guided session — "the full monty" plan.md §3a describes, both signals
/// and the agent final pick over a real model.
///
/// The selection grammar is derived once, over the whole catalog's ids: the
/// ~50-item `toolCatalog` stays comfortably under
/// `SelectionConfig.defaultCapacityCharacterLimit`, so the cached-root +
/// fork-per-call path always runs and never needs the over-budget path's
/// narrower, per-call candidate grammar.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` or its
///   selection tier emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `resolveLiveFullMontyProfile()`,
///   `SelectionTier.idEnumGrammar(ids:)`, or
///   `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)` throws.
public func runLiveFullMontyDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    let profile = try await resolveLiveFullMontyProfile()
    let embedder: any TextEmbedding = RoutedEmbedderAdapter(routedEmbedder: profile.embedding)
    let grammar = try SelectionTier.idEnumGrammar(ids: toolCatalog.map(\.id))
    let session: @Sendable (String) -> any AgentSession = { instructions in
        RoutedAgentSession(session: profile.standard.makeGuidedSession(grammar: grammar, instructions: instructions))
    }
    return try await runFullMontyDemo(embedder: embedder, session: session, mode: .auto, onDiagnostic: onDiagnostic)
}
