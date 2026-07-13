// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionConfig.swift`
// (plan.md §6 phase 3). Behavior unchanged (defaults, clamping); the one
// deliberate diff is the default preamble constant, renamed from
// `.librarianDefault` to `.selectionDefault` with neutral wording -- no
// "API librarian"/"functions" domain language, since RankKit's catalog is
// never assumed to be an API surface.

/// Configuration for a selection tier: how selection sessions are created,
/// what guidance seeds the assembled prefix, and the capacity/candidate
/// budgets that decide between the cached-root and one-off session paths.
///
/// Generalizes Multitool's own `Librarian` initializer parameters
/// (`capacityCharacterLimit`, `makeSession`) into one value type so a
/// selection tier can accept -- or omit -- a selection configuration
/// without a combinatorial explosion of initializer overloads.
public struct SelectionConfig: Sendable {
    /// A generous default capacity, in characters, approximating a
    /// typical 8,192-token context budget at roughly 4 characters per
    /// token -- identical to Multitool's own
    /// `Librarian.defaultCapacityCharacterLimit`.
    public static let defaultCapacityCharacterLimit = 32_000

    /// The default number of top-ranked candidates the over-budget path
    /// seeds its one-off session with.
    public static let defaultCandidateLimit = 24

    /// Creates a session seeded with the given instructions text -- the
    /// seam a selection tier drives both the cached root session and the
    /// over-budget one-off session through. `@Sendable` so it can cross a
    /// selection tier's actor isolation boundary; production wires it to
    /// `RoutedLLM.makeGuidedSession(_:instructions:)`, already constrained
    /// to the current id-enum grammar -- the same shape as Multitool's own
    /// `Librarian`'s `makeSession` parameter.
    public var model: @Sendable (String) -> any AgentSession

    /// The selection guidance prepended to every assembled prefix. Defaults
    /// to `.selectionDefault`.
    public var preamble: String

    /// The assembled prefix's character budget (preamble + every
    /// candidate's summary block); at or under this, the cached-root +
    /// fork-per-call path runs. Negative values are clamped to `0`.
    public var capacityCharacterLimit: Int

    /// Over budget, how many top-ranked retrieval candidates seed the
    /// one-off session. Negative values are clamped to `0`.
    public var candidateLimit: Int

    /// Creates a selection tier configuration.
    ///
    /// - Parameters:
    ///   - model: creates a session seeded with the given instructions
    ///     text.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`.
    ///   - candidateLimit: the over-budget top-M candidate count. Defaults
    ///     to `defaultCandidateLimit`.
    public init(
        model: @escaping @Sendable (String) -> any AgentSession,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit,
        candidateLimit: Int = SelectionConfig.defaultCandidateLimit
    ) {
        self.model = model
        self.preamble = preamble
        self.capacityCharacterLimit = max(0, capacityCharacterLimit)
        self.candidateLimit = max(0, candidateLimit)
    }
}

extension String {
    /// The curated selection guidance every `SelectionConfig` defaults its
    /// `preamble` to -- a neutral rewrite of Multitool's shipped
    /// `Librarian.selectionGuidance` ("You are an API librarian ... return
    /// ONLY the functions needed"), generalized to items/ids rather than
    /// functions so it carries no domain-specific language (plan.md §6
    /// phase 3): "fewest that suffice, in call order when order matters."
    public static let selectionDefault: String = """
        Given a task, return ONLY the items needed — fewest that suffice, in call order when
        order matters. Do not invent ids; return an empty list if nothing fits.
        """
}
