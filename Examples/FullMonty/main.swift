import FullMontyCore

/// # The `Searcher` facade's living proof (plan.md §3a).
///
/// Three paths, gated in this order:
///
/// - `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` set: resolves a live Router + tiny
///   mlx-community model, joining the cosine signal into retrieval and
///   answering selection through a real, grammar-constrained model — "the
///   full monty."
/// - `--no-model`: the degraded, GPU-free, CI-safe path — keyword-only
///   (BM25 + trigram) retrieval, no selection model, with the
///   `.embeddingUnavailable` diagnostic printed for every query.
/// - Neither: the default, out-of-the-box path — keyword-only retrieval
///   signals, but real agent selection on the on-device system model
///   (`Searcher.defaultSessionFactory`).
///
/// The actual search logic lives in `FullMontyCore` so `ExamplesSmokeTests`
/// can invoke its GPU-free paths directly; this file is just the runnable
/// entry point. Run with `swift run FullMonty`, `swift run FullMonty
/// --no-model`, or `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS=1 swift run FullMonty`.

if isFoundationModelsRankerIntegrationEnabled {
    print("\(foundationModelsRankerIntegrationEnvVar) set -- running the full monty against a live Router + tiny mlx-community model.\n")
    let results = try await runLiveFullMontyDemo(onDiagnostic: printDiagnostic)
    printResults(results)
} else if CommandLine.arguments.contains("--no-model") {
    print("--no-model set -- printing keyword-only retrieval results (GPU-free, CI-safe).\n")
    let results = try await runNoModelDemo(onDiagnostic: printDiagnostic)
    printResults(results)
} else {
    print(
        """
        Running the default path: keyword-only retrieval, real agent selection on the on-device system model.
        Pass --no-model for the GPU-free keyword-only path, or set \(foundationModelsRankerIntegrationEnvVar) for the live \
        Router + tiny mlx-community model path.

        """
    )
    let results = try await runDefaultDemo(onDiagnostic: printDiagnostic)
    printResults(results)
}
