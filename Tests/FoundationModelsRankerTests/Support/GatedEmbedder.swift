import Foundation
import FoundationModelsRanker
import os

/// A `TextEmbedding` test double whose `embed(_:)` call suspends until a
/// test explicitly releases it -- lets a test inject a *specific*
/// interleaving against a `StreamingSearchCorpus` actor's suspension point,
/// deterministically, rather than hoping `withTaskGroup` stress happens to
/// hit it.
///
/// Exists for ^rayd7bq's race regression: `StreamingSearchCorpus
/// .add(items:)` embeds new items via an `await embedder.embed(_:)` call,
/// which is a genuine actor suspension point -- a concurrent `remove`/`add`
/// on the same actor can run to completion while that call is in flight.
/// `FakeEmbedder`/`CountingEmbedder` both resolve near-instantly, so a test
/// built on either can't reliably land a second actor call *inside* that
/// window. `GatedEmbedder` makes the window as wide as the test needs: hold
/// every `embed(_:)` call open until `release()` is called, and let a test
/// synchronize on exactly which call has started via
/// `waitUntilEntered(callNumber:)`.
final class GatedEmbedder: TextEmbedding, Sendable {
    let dimension: Int

    private let fake: FakeEmbedder
    private let releaseGate = OpenForeverGate()
    private let enteredGate = CountingGate()

    /// Creates a gated embedder that deterministically hashes text into
    /// vectors of `dimension` length, exactly like `FakeEmbedder`, once
    /// released.
    ///
    /// - Parameter dimension: the length of every vector this embedder
    ///   produces.
    init(dimension: Int) {
        self.dimension = dimension
        fake = FakeEmbedder(dimension: dimension)
    }

    /// Records this call as "entered" (for `waitUntilEntered(callNumber:)`
    /// to observe), then suspends until `release()` has been called, then
    /// embeds `texts` exactly like `FakeEmbedder`.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        enteredGate.signal()
        await releaseGate.wait()
        return try await fake.embed(texts)
    }

    /// Suspends until the `callNumber`-th call to `embed(_:)` (1-indexed,
    /// in call order) has been entered -- whether that happened before or
    /// after this call. Lets a test synchronize on a *specific* embed call
    /// among several concurrent ones, not just "any call has started."
    ///
    /// - Parameter callNumber: which `embed(_:)` call to wait for, in
    ///   1-indexed call order. Defaults to `1` (the first call).
    func waitUntilEntered(callNumber: Int = 1) async {
        await enteredGate.wait(untilCount: callNumber)
    }

    /// Opens the release gate permanently: every currently-parked
    /// `embed(_:)` call resumes, and every future one returns immediately
    /// without parking.
    func release() {
        releaseGate.open()
    }
}

/// A gate that starts closed and, once `open()` is called, stays open
/// forever: every waiter parked at that point resumes, and every later
/// `wait()` call returns immediately without suspending.
///
/// Backs `GatedEmbedder.release()`: releasing should free every embed call
/// currently parked (there may be more than one, if a test deliberately
/// stacks several concurrent actor calls behind the same gate) in one shot,
/// and never re-park a later call.
///
/// Uses `OSAllocatedUnfairLock.withLock` (a plain synchronous closure-based
/// API), not `NSLock.lock()`/`unlock()` directly -- those are unavailable
/// from `async` contexts specifically to prevent a lock held across a
/// suspension point, which `wait()`'s `await withCheckedContinuation` would
/// otherwise risk.
private final class OpenForeverGate: @unchecked Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let stateBox = OSAllocatedUnfairLock(initialState: State())

    /// Suspends until `open()` is called (whether that happens before or
    /// after this call).
    func wait() async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            let shouldResumeNow = stateBox.withLock { state -> Bool in
                guard !state.isOpen else { return true }
                state.waiters.append(k)
                return false
            }
            if shouldResumeNow {
                k.resume()
            }
        }
    }

    /// Opens this gate permanently, resuming every currently-parked
    /// waiter.
    func open() {
        let toResume = stateBox.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for k in toResume { k.resume() }
    }
}

/// A monotonically increasing counter with threshold-waiters: each
/// `signal()` call increments the count by one, and `wait(untilCount:)`
/// suspends until the count has reached at least the given threshold --
/// whether that happened before or after the call.
///
/// Backs `GatedEmbedder`'s `waitUntilEntered(callNumber:)`: each `embed(_:)`
/// call signals once on entry, so waiting for count `N` is waiting for the
/// `N`th call specifically, in the order calls actually entered.
private final class CountingGate: @unchecked Sendable {
    private struct State {
        var count = 0
        var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let stateBox = OSAllocatedUnfairLock(initialState: State())

    /// Increments the count by one, resuming every waiter whose threshold
    /// is now satisfied.
    func signal() {
        let ready = stateBox.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.count += 1
            var ready: [CheckedContinuation<Void, Never>] = []
            state.waiters.removeAll { waiter in
                guard waiter.threshold <= state.count else { return false }
                ready.append(waiter.continuation)
                return true
            }
            return ready
        }
        for k in ready { k.resume() }
    }

    /// Suspends until the count has reached at least `threshold` (whether
    /// that happened before or after this call).
    ///
    /// - Parameter threshold: the count to wait for.
    func wait(untilCount threshold: Int) async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            let shouldResumeNow = stateBox.withLock { state -> Bool in
                guard state.count < threshold else { return true }
                state.waiters.append((threshold, k))
                return false
            }
            if shouldResumeNow {
                k.resume()
            }
        }
    }
}
