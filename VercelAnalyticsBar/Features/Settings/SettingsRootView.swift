import SwiftUI
import VercelAnalyticsCore

struct SettingsRootView: View {
    let model: AppModel
    @State private var token = ""
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ProductInfo.name)
                .font(.title2.weight(.semibold))

            accountContent

            IndependenceNotice()
        }
        .padding(24)
        .frame(width: 520, height: 680)
        .task {
            await model.restoreConnection()
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch model.accountState {
        case .disconnected:
            connectionForm
        case .restoring:
            ProgressContent(message: "Restoring Vercel connection…")
        case .validating:
            ProgressContent(message: "Validating Vercel access token…")
        case .connected:
            connectedContent
        case let .failed(error):
            connectionForm(error: error)
        }
    }

    private var connectionForm: some View {
        connectionForm(error: nil)
    }

    private func connectionForm(error: AccountConnectionError?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your Vercel account")
                .font(.headline)

            Text("Use a Vercel Personal Access Token. It is validated by Vercel and stored only in the macOS Keychain.")
                .foregroundStyle(.secondary)

            SecureField("Vercel access token", text: $token)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Connect") {
                    Task {
                        await model.connect(token: token)
                        if model.accountState == .connected {
                            token = ""
                        }
                    }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Link("Create or manage tokens", destination: tokenSettingsURL)
                    .font(.caption)
            }

            if let error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Vercel account connected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                Button("Sync now") {
                    Task {
                        await model.syncNow()
                    }
                }
                .disabled(model.projectState == .loading)
            }

            Text("Your access token is stored securely in the macOS Keychain.")
                .foregroundStyle(.secondary)

            launchAtLoginContent
            analyticsStatusContent
            projectContent

            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
        }
    }

    private var launchAtLoginContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Open at login",
                isOn: Binding(
                    get: { model.launchAtLoginStatus.isEnabled },
                    set: { model.setLaunchAtLogin(enabled: $0) }
                )
            )
            .disabled(model.launchAtLoginStatus == .unavailable)

            Text("Login Item: \(model.launchAtLoginStatus.label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = model.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var analyticsStatusContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.state {
            case .idle:
                Label("Analytics not loaded", systemImage: "chart.line.uptrend.xyaxis")
            case .loading:
                Label("Refreshing analytics", systemImage: "arrow.clockwise")
            case let .loaded(snapshot):
                analyticsLoadedStatus(snapshot)
            case let .empty(message):
                Label("Analytics unavailable", systemImage: "questionmark.circle")
                Text(message)
                    .font(.caption)
            case let .failed(message):
                Label("Analytics unavailable", systemImage: "exclamationmark.triangle")
                Text(message)
                    .font(.caption)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func analyticsLoadedStatus(_ snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.snapshotFreshness == .stale {
                Label("Showing stale analytics", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else {
                Label("Analytics up to date", systemImage: "checkmark.circle")
            }

            Text("Updated \(snapshot.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)

            if let refreshMessage = model.refreshMessage {
                Text(refreshMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var projectContent: some View {
        switch model.projectState {
        case .idle:
            Text("Sync to load your Vercel projects.")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressContent(message: "Loading Vercel projects…")
        case let .loaded(projects):
            projectList(projects)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Projects unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await model.refreshProjects()
                    }
                }
            }
        }
    }

    private func projectList(_ projects: [VercelProject]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Text("\(model.selectedProjectIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Find Project…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)

            let filteredProjects = model.projects(matching: searchQuery)
            if filteredProjects.isEmpty {
                Text("No projects match this search.")
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .foregroundStyle(.secondary)
            } else {
                List(filteredProjects) { project in
                    projectRow(project)
                }
                .listStyle(.inset)
                .frame(minHeight: 300)
            }

            if projects.isEmpty {
                Text("No accessible projects were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Analytics status is checked when metrics are loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.projectSelectionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func projectRow(_ project: VercelProject) -> some View {
        Toggle(
            isOn: Binding(
                get: { model.selectedProjectIDs.contains(project.id) },
                set: { model.setProjectSelected(project.id, selected: $0) }
            )
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                    if let metadata = model.teamMetadata(for: project) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(project.analyticsAvailability.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .help(project.analyticsAvailability.label)
    }

    private var tokenSettingsURL: URL {
        URL(string: "https://vercel.com/account/tokens")!
    }
}

private struct IndependenceNotice: View {
    var body: some View {
        Text("Vercel Analytics Bar is an independent app and is not affiliated with Vercel. "
            + "It connects directly to Vercel using your Personal Access Token.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ProgressContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }
}
