import SwiftUI
import VercelAnalyticsCore

struct SettingsRootView: View {
    let model: AppModel
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ProductInfo.name)
                .font(.title2.weight(.semibold))

            accountContent
        }
        .padding(24)
        .frame(width: 460, height: 300)
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
            Label("Vercel account connected", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Your access token is stored securely in the macOS Keychain.")
                .foregroundStyle(.secondary)

            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
        }
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
