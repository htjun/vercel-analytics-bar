import Foundation
import Observation
import VercelAnalyticsCore

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(AnalyticsSnapshot)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let provider: any AnalyticsSnapshotProviding

    init(provider: any AnalyticsSnapshotProviding) {
        self.provider = provider
    }

    func load() async {
        state = .loading

        do {
            state = .loaded(try await provider.snapshot())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
