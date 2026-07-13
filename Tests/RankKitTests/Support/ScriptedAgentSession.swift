import Foundation
import os

@testable import RankKit

// MARK: - Selection-tier `AgentSession` fixtures (plan.md §6 phase 3)
//
// Ported from FoundationModelsMetadataRegistry's
// `Tests/FoundationModelsMetadataRegistryTests/TestSupport/ScriptedAgentSession.swift`
// and `SelectionFixtures.swift` (themselves lifted from Multitool's own
// `LibrarianFixtures.swift`): `SelectionTests`/`OverBudgetTests` never touch a
// real Router model — a selection tier's session is always supplied through
// the internal `AgentSession` seam, driven by these scripted fakes. Zero GPU,
// no Router dependency.

/// Thrown by `ScriptedAgentSession.respond(to:)` when it receives more calls
/// than it was scripted with — a test bug (an under-scripted fixture), never
/// a condition a correctly scripted fixture should trigger in production
/// code driven through the `AgentSession` seam.
struct ScriptedAgentSessionError: Error, Equatable, CustomStringConvertible {
    /// How many scripted responses `respond(to:)` had queued.
    let scriptedResponseCount: Int

    var description: String {
        "ScriptedAgentSession received more calls than its \(scriptedResponseCount) scripted response(s)."
    }
}

/// A scripted `AgentSession` test double: returns its canned `responses` in
/// order, one per call, regardless of the prompt, and counts `fork()`
/// calls — this test target's zero-GPU stand-in for a real Router session.
///
/// `final class ... Sendable` (not a `struct`) because `respond(to:)` needs
/// to record every prompt it received and advance a call index across
/// `await` boundaries, and `fork()` needs to record a call count visible
/// after the `async` call returns; state lives behind an
/// `OSAllocatedUnfairLock`.
final class ScriptedAgentSession: AgentSession, Sendable {
    /// The mutable state guarded by `stateBox`.
    private struct State {
        /// How many calls `respond(to:)` has handled so far — the index into
        /// `responses` the next call consumes.
        var callCount = 0
        /// Every prompt `respond(to:)` has received, in call order.
        var receivedPrompts: [String] = []
        /// How many times `fork()` has been called.
        var forkCount = 0
    }

    /// The canned responses returned in order, one per call.
    private let responses: [String]

    /// This session's call state.
    private let stateBox: OSAllocatedUnfairLock<State>

    /// Creates a scripted session that returns `responses` in order, one per
    /// `respond(to:)` call.
    ///
    /// - Parameter responses: the canned responses to return, in call order.
    init(_ responses: [String]) {
        self.responses = responses
        self.stateBox = OSAllocatedUnfairLock(initialState: State())
    }

    /// Creates a scripted session that always returns `response` — a
    /// convenience for the common single-canned-response case.
    ///
    /// - Parameter response: the canned response every call returns.
    ///   Defaults to `""`.
    convenience init(response: String = "") {
        self.init([response])
    }

    /// Every prompt this session received, in call order — lets a test
    /// assert on what a caller fed back as the next turn's prompt.
    var receivedPrompts: [String] { stateBox.withLock { $0.receivedPrompts } }

    /// How many calls this session has handled so far.
    var callCount: Int { stateBox.withLock { $0.callCount } }

    /// How many times `fork()` has been called on this session.
    var forkCount: Int { stateBox.withLock { $0.forkCount } }

    func respond(to prompt: String) async throws -> String {
        let index = stateBox.withLock { state -> Int in
            state.receivedPrompts.append(prompt)
            let index = state.callCount
            state.callCount += 1
            return index
        }
        guard index < responses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: responses.count)
        }
        return responses[index]
    }

    func fork() async throws -> any AgentSession {
        stateBox.withLock { $0.forkCount += 1 }
        return self
    }
}

/// Thrown by `RootSessionRespondCalledDirectlySession.respond(to:)` if it is
/// ever called directly — the selection tier's contract is that every
/// `search()` call goes through a `fork()` of the prefix-rooted session,
/// never the root itself (the KV-cache-copy seam only pays off if the root is
/// never asked to generate on its own transcript).
struct RootSessionRespondCalledDirectlyError: Error, Equatable {}

/// A selection-root `AgentSession` double: records how many times `fork()`
/// was called and hands back a fresh, independently-scripted
/// `ScriptedAgentSession` each time — but throws if `respond(to:)` is ever
/// invoked on the root itself, asserting the "always via fork()" contract.
final class RootSessionRespondCalledDirectlySession: AgentSession, Sendable {
    /// One scripted response per `fork()` call, in fork order — the raw
    /// guided-generation JSON text the resulting fork's `respond(to:)`
    /// returns.
    private let forkResponses: [String]

    /// How many `fork()` calls this root has handled so far.
    private let forkCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a root double that hands back one freshly-scripted fork per
    /// `fork()` call, in order.
    ///
    /// - Parameter forkResponses: one canned raw response per expected
    ///   `fork()` call, in call order.
    init(forkResponses: [String]) {
        self.forkResponses = forkResponses
    }

    /// How many `fork()` calls this root has handled so far.
    var forkCount: Int { forkCountBox.withLock { $0 } }

    func respond(to prompt: String) async throws -> String {
        throw RootSessionRespondCalledDirectlyError()
    }

    func fork() async throws -> any AgentSession {
        let index = forkCountBox.withLock { count -> Int in
            let index = count
            count += 1
            return index
        }
        guard index < forkResponses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: forkResponses.count)
        }
        return ScriptedAgentSession([forkResponses[index]])
    }
}

/// Records every `instructions` string a `SelectionConfig.model` factory
/// closure was called with, returning one freshly-scripted
/// `ScriptedAgentSession` (canned with `responses`) per call — lets a test
/// assert both on *how many times* a session was created (proving the root
/// session is cached, not rebuilt per `search()` call) and on *what prefix
/// text* was actually seeded (e.g. that it carries summary blocks, not full
/// ones).
final class RecordingSessionFactory: Sendable {
    /// The canned responses every created session is scripted with.
    private let responses: [String]

    /// Every `instructions` string `makeSession(instructions:)` has been
    /// called with, in call order.
    private let receivedInstructionsBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Creates a factory whose every vended session is scripted with
    /// `responses`.
    ///
    /// - Parameter responses: the canned responses every created session
    ///   returns, in call order.
    init(responses: [String]) {
        self.responses = responses
    }

    /// Every `instructions` string this factory has been called with, in
    /// call order.
    var receivedInstructions: [String] { receivedInstructionsBox.withLock { $0 } }

    /// Creates and records a new scripted session — `SelectionConfig`'s
    /// `model` factory parameter.
    ///
    /// - Parameter instructions: the instructions text to record.
    /// - Returns: a freshly-scripted `ScriptedAgentSession`.
    func makeSession(instructions: String) -> any AgentSession {
        receivedInstructionsBox.withLock { $0.append(instructions) }
        return ScriptedAgentSession(responses)
    }
}

/// A thread-safe call counter — used to assert a closure ran an exact number
/// of times without needing a bespoke lock-boxed fixture per test.
final class CallCounter: Sendable {
    /// This counter's current count.
    private let countBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a counter starting at `0`.
    init() {}

    /// Increments the count and returns its new value.
    ///
    /// - Returns: the count after incrementing.
    @discardableResult
    func increment() -> Int {
        countBox.withLock { count -> Int in
            count += 1
            return count
        }
    }

    /// This counter's current count.
    var count: Int { countBox.withLock { $0 } }
}

/// A thread-safe recorder for `onDiagnostic` callbacks — lets a test assert
/// on the `RankDiagnostic`s a selection tier reported without maintaining its
/// own lock-boxed state per suite.
final class DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RankDiagnostic] = []

    var diagnostics: [RankDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ diagnostic: RankDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(diagnostic)
    }
}
