import Foundation
import Testing
import VercelAnalyticsCore
@testable import VercelAnalyticsBar

@MainActor
@Test func appModelLoadsSnapshotThroughInjectedProvider() async {
    let expected = AnalyticsSnapshot.fixture
    let provider = ControlledSnapshotProvider()
    let model = AppModel(provider: provider)

    #expect(model.state == .idle)

    let loadTask = Task {
        await model.load()
    }
    await provider.waitUntilRequested()

    #expect(model.state == .loading)

    await provider.succeed(with: expected)
    await loadTask.value

    #expect(model.state == .loaded(expected))
}

@MainActor
@Test func appModelExposesProviderFailure() async {
    let provider = ControlledSnapshotProvider()
    let model = AppModel(provider: provider)

    let loadTask = Task {
        await model.load()
    }
    await provider.waitUntilRequested()
    await provider.fail(with: SnapshotError.unavailable)
    await loadTask.value

    guard case let .failed(message) = model.state else {
        Issue.record("Expected a failed state")
        return
    }

    #expect(message == SnapshotError.unavailable.localizedDescription)
}

private enum SnapshotError: Error {
    case unavailable
}

private actor ControlledSnapshotProvider: AnalyticsSnapshotProviding {
    private var resultContinuation: CheckedContinuation<AnalyticsSnapshot, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func snapshot() async throws -> AnalyticsSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard resultContinuation == nil else { return }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func succeed(with snapshot: AnalyticsSnapshot) {
        resultContinuation?.resume(returning: snapshot)
        resultContinuation = nil
    }

    func fail(with error: any Error) {
        resultContinuation?.resume(throwing: error)
        resultContinuation = nil
    }
}
