import AppKit
import SwiftUI
import VercelAnalyticsCore

struct MenuBarRootView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            await model.restoreConnection()
            guard model.state == .idle else { return }
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading analytics…")
            }

        case let .loaded(snapshot):
            snapshotContent(snapshot)

        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Analytics unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await model.load()
                    }
                }
            }
        }
    }

    private func snapshotContent(_ snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.projectName)
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.primaryMetric.value, format: .number)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(snapshot.primaryMetric.label)
                    .foregroundStyle(.secondary)
            }

            Text("Updated \(snapshot.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
