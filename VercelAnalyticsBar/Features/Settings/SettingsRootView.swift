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
        }
        .padding(24)
        .frame(width: 520, height: 620)
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
            progressContent("Restoring Vercel connection…")
        case .validating:
            progressContent("Validating Vercel access token…")
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

                Button("Sync projects") {
                    Task {
                        await model.refreshProjects()
                    }
                }
                .disabled(model.projectState == .loading)
            }

            Text("Your access token is stored securely in the macOS Keychain.")
                .foregroundStyle(.secondary)

            projectContent

            Button("Disconnect", role: .destructive) {
                model.disconnect()
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
            progressContent("Loading Vercel projects…")
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

    private func progressContent(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    private var tokenSettingsURL: URL {
        URL(string: "https://vercel.com/account/tokens")!
    }
}
