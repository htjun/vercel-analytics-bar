import AppKit
import SwiftUI
import VercelAnalyticsCore

enum SettingsLayout {
    static let contentWidth: CGFloat = 384
    static let productionHeight: CGFloat = 528
    static let developerHeight: CGFloat = 572
    static let horizontalPadding: CGFloat = 16
    static let titleTopPadding: CGFloat = 24
    static let titleHeight: CGFloat = 14
    static let titleToIdentitySpacing: CGFloat = 24
    static let identityHeight: CGFloat = 20
    static let identityToListSpacing: CGFloat = 16
    static let projectListSize = CGSize(width: 352, height: 300)
    static let projectListCornerRadius: CGFloat = 8
    static let projectListHorizontalPadding: CGFloat = 12
    static let projectListVerticalPadding: CGFloat = 8
    static let projectRowHeight: CGFloat = 26
    static let projectListToLoginSpacing: CGFloat = 24
    static let loginRowHeight: CGFloat = 26
    static let loginToActionsSpacing: CGFloat = 24
    static let actionSpacing: CGFloat = 8
    static let actionSize = CGSize(width: 112, height: 32)
    static let actionsToEditorSpacing: CGFloat = 12
    static let editorSize = CGSize(width: 352, height: 32)
    static let bottomPadding: CGFloat = 24

    static func contentHeight(showsComponentEditor: Bool) -> CGFloat {
        showsComponentEditor ? developerHeight : productionHeight
    }
}

enum SettingsAccountIdentity {
    static func label(for profile: VercelAccountProfile?) -> String {
        guard let profile else { return "Vercel account" }

        let name = normalized(profile.name)
        let username = normalized(profile.username)
        switch (name, username) {
        case let (name?, username?) where name.caseInsensitiveCompare(username) != .orderedSame:
            return "\(name) (\(username))"
        case let (name?, _):
            return name
        case let (_, username?):
            return username
        default:
            return "Vercel account"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private enum SettingsAlert: Identifiable {
    case disconnect
    case error(String)

    var id: String {
        switch self {
        case .disconnect:
            "disconnect"
        case let .error(message):
            "error:\(message)"
        }
    }
}

struct SettingsRootView: View {
    let model: AppModel
    let isComponentEditorEnabled: Bool
    let onOpenComponentEditor: () -> Void

    @State private var presentedAlert: SettingsAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: SettingsLayout.titleTopPadding)

            Text("Settings")
                .font(AppTypography.geistSemibold16)
                .foregroundStyle(.primary)
                .frame(height: SettingsLayout.titleHeight)

            Spacer()
                .frame(height: SettingsLayout.titleToIdentitySpacing)

            accountIdentity

            Spacer()
                .frame(height: SettingsLayout.identityToListSpacing)

            projectList

            Spacer()
                .frame(height: SettingsLayout.projectListToLoginSpacing)

            launchAtLogin

            Spacer()
                .frame(height: SettingsLayout.loginToActionsSpacing)

            actions

            componentEditor

            Spacer()
                .frame(height: SettingsLayout.bottomPadding)
        }
        .padding(.horizontal, SettingsLayout.horizontalPadding)
        .frame(
            width: SettingsLayout.contentWidth,
            height: SettingsLayout.contentHeight(showsComponentEditor: isComponentEditorEnabled),
            alignment: .topLeading
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $presentedAlert, content: alert)
    }

    private var accountIdentity: some View {
        HStack(spacing: 6) {
            AccountAvatar(url: model.connectedAccount?.avatarURL)

            Text(SettingsAccountIdentity.label(for: model.connectedAccount))
                .font(AppTypography.geistRegular12)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(height: SettingsLayout.identityHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SettingsAccountIdentity.label(for: model.connectedAccount))
    }

    private var projectList: some View {
        Group {
            switch model.projectState {
            case .idle:
                projectStatus("Connect your Vercel account from the menu bar.")
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Vercel projects")
            case let .loaded(projects):
                if projects.isEmpty {
                    projectStatus("No accessible projects were found.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(projects) { project in
                                projectRow(project)
                            }
                        }
                        .padding(.horizontal, SettingsLayout.projectListHorizontalPadding)
                        .padding(.vertical, SettingsLayout.projectListVerticalPadding)
                    }
                }
            case .failed:
                projectStatus("Projects could not be loaded.")
            }
        }
        .frame(
            width: SettingsLayout.projectListSize.width,
            height: SettingsLayout.projectListSize.height
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsLayout.projectListCornerRadius)
                .stroke(AnalyticsCardColors.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: SettingsLayout.projectListCornerRadius))
    }

    private func projectRow(_ project: VercelProject) -> some View {
        let isSelected = model.selectedProjectIDs.contains(project.id)
        let isOnlySelection = isSelected && model.selectedProjectIDs.count == 1

        return Toggle(isOn: Binding(
            get: { model.selectedProjectIDs.contains(project.id) },
            set: { selected in
                model.setProjectSelected(project.id, selected: selected)
                if let message = model.projectSelectionError {
                    presentedAlert = .error(message)
                }
            }
        )) {
            Text(projectLabel(project))
                .font(AppTypography.geistRegular12)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, minHeight: SettingsLayout.projectRowHeight, alignment: .leading)
        .disabled(isOnlySelection || model.isRefreshingProjects)
    }

    private func projectLabel(_ project: VercelProject) -> String {
        guard let team = model.teamMetadata(for: project) else { return project.name }
        return "\(project.name) (\(team))"
    }

    private func projectStatus(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.geistRegular12)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var launchAtLogin: some View {
        Toggle(
            "Open at login",
            isOn: Binding(
                get: { model.launchAtLoginStatus.isEnabled },
                set: { enabled in
                    model.setLaunchAtLogin(enabled: enabled)
                    if let message = model.launchAtLoginError {
                        presentedAlert = .error(message)
                        model.clearLaunchAtLoginError()
                    }
                }
            )
        )
        .font(AppTypography.geistRegular12)
        .toggleStyle(.checkbox)
        .frame(height: SettingsLayout.loginRowHeight)
        .disabled(model.launchAtLoginStatus == .unavailable)
        .help(model.launchAtLoginStatus.label)
    }

    private var actions: some View {
        HStack(spacing: SettingsLayout.actionSpacing) {
            SettingsActionButton(
                title: "Refresh",
                isBusy: model.isRefreshingProjects,
                isDisabled: model.accountState != .connected
            ) {
                Task {
                    await model.refreshProjects()
                    if let message = model.projectRefreshError {
                        presentedAlert = .error(message)
                        model.clearProjectRefreshError()
                    }
                }
            }

            SettingsActionButton(
                title: "Disconnect",
                isDisabled: model.accountState != .connected
            ) {
                presentedAlert = .disconnect
            }

            SettingsActionButton(title: "Quit (⌘ + Q)") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var componentEditor: some View {
        #if COMPONENT_EDITOR
            if isComponentEditorEnabled {
                Spacer()
                    .frame(height: SettingsLayout.actionsToEditorSpacing)

                SettingsActionButton(
                    title: "Component Editor",
                    width: SettingsLayout.editorSize.width,
                    action: onOpenComponentEditor
                )
            }
        #endif
    }

    private func alert(_ alert: SettingsAlert) -> Alert {
        switch alert {
        case .disconnect:
            Alert(
                title: Text("Disconnect Vercel account?"),
                message: Text("You will need to reconnect with a Vercel access token."),
                primaryButton: .destructive(Text("Disconnect"), action: model.disconnect),
                secondaryButton: .cancel()
            )
        case let .error(message):
            Alert(
                title: Text("Settings Error"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct AccountAvatar: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: SettingsLayout.identityHeight, height: SettingsLayout.identityHeight)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.18))

            Image(systemName: "person.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsActionButton: View {
    let title: String
    var width = SettingsLayout.actionSize.width
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(title)
                } else {
                    Text(title)
                        .font(AppTypography.geistMedium12)
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: SettingsLayout.actionSize.height)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AnalyticsCardColors.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
