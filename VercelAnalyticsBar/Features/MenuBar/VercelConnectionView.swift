import AppKit
import SwiftUI

enum VercelConnectionLayout {
    static let introductionHeight: CGFloat = 466
    static let footerHeight: CGFloat = 80
    static let introductionWidth: CGFloat = 296
    static let introductionContentHeight: CGFloat = 174
    static let tokenManagementButtonSize = CGSize(width: 185, height: 32)
    static let tokenFieldSize = CGSize(width: 258, height: 32)
    static let connectButtonSize = CGSize(width: 68, height: 32)
    static let formSpacing: CGFloat = 8
    static let formWidth: CGFloat = 334
}

enum VercelConnectionFormState {
    static func canSubmit(token: String, isBusy: Bool) -> Bool {
        !isBusy && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
enum VercelConnectionAction {
    static func connect(model: AppModel, token: String) async -> Bool {
        await model.connect(token: token)
        return model.accountState == .connected
    }
}

struct VercelConnectionView: View {
    let model: AppModel
    let error: AccountConnectionError?
    let isValidating: Bool
    let rendersStaticTokenField: Bool

    @Environment(\.openURL) private var openURL
    @FocusState private var isTokenFieldFocused: Bool
    @State private var token = ""
    @State private var isSubmitting = false

    init(
        model: AppModel,
        error: AccountConnectionError?,
        isValidating: Bool,
        initialToken: String = "",
        rendersStaticTokenField: Bool = false
    ) {
        self.model = model
        self.error = error
        self.isValidating = isValidating
        self.rendersStaticTokenField = rendersStaticTokenField
        _token = State(initialValue: initialToken)
    }

    var body: some View {
        AnalyticsCardShell {
            VStack(spacing: 0) {
                introduction
                connectionForm
            }
        }
        .onAppear {
            isTokenFieldFocused = !isBusy
        }
        .task(id: error) {
            guard let error else { return }
            announce(error)
        }
    }

    private var introduction: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 24) {
                Image("AnalyticsBarLogo")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(spacing: 16) {
                    Text("Connect your Vercel account")
                        .font(AppTypography.geistSemibold16)
                        .tracking(AppTypography.connectionTitleTracking)
                        .foregroundStyle(AnalyticsCardColors.connectionText)
                        .frame(width: VercelConnectionLayout.introductionWidth, height: 20)

                    Text("Use a Vercel Personal Access Token.\nIt is stored only in the macOS Keychain.")
                        .font(AppTypography.geistRegular14)
                        .foregroundStyle(AnalyticsCardColors.connectionText.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: VercelConnectionLayout.introductionWidth, height: 34)
                }

                Button {
                    openURL(Self.tokenSettingsURL)
                } label: {
                    HStack(spacing: 8) {
                        Text("Create or manage tokens")
                            .font(AppTypography.geistMedium12)
                            .foregroundStyle(AnalyticsCardColors.primaryText)

                        Image("ExternalArrow")
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    .frame(
                        width: VercelConnectionLayout.tokenManagementButtonSize.width,
                        height: VercelConnectionLayout.tokenManagementButtonSize.height
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .overlay {
                    Capsule()
                        .stroke(AnalyticsCardColors.border, lineWidth: 1)
                }
                .help("Open Vercel token settings")
            }
            .frame(
                width: VercelConnectionLayout.introductionWidth,
                height: VercelConnectionLayout.introductionContentHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error {
                Text(errorMessage(for: error))
                    .font(AppTypography.geistRegular12)
                    .foregroundStyle(AnalyticsCardColors.connectionError)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: VercelConnectionLayout.formWidth)
                    .frame(minHeight: 32)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Connection error. \(errorMessage(for: error))")
            }
        }
        .frame(
            width: AnalyticsCardLayout.cardSize.width,
            height: VercelConnectionLayout.introductionHeight
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AnalyticsCardColors.connectionDivider)
                .frame(height: 1)
        }
    }

    private var connectionForm: some View {
        HStack(spacing: VercelConnectionLayout.formSpacing) {
            tokenField

            Button(action: submit) {
                Group {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityHidden(true)
                    } else {
                        Text("Connect")
                            .font(AppTypography.geistMedium12)
                            .foregroundStyle(.white)
                    }
                }
                .frame(
                    width: VercelConnectionLayout.connectButtonSize.width,
                    height: VercelConnectionLayout.connectButtonSize.height
                )
                .background(connectButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(isBusy ? "Connecting to Vercel" : "Connect")
        }
        .frame(
            width: AnalyticsCardLayout.cardSize.width,
            height: VercelConnectionLayout.footerHeight
        )
    }

    @ViewBuilder
    private var tokenField: some View {
        if rendersStaticTokenField {
            tokenFieldChrome(
                Text(staticTokenText)
                    .foregroundStyle(token.isEmpty ? Color.black.opacity(0.3) : .black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        } else {
            tokenFieldChrome(
                SecureField(
                    "Vercel access token",
                    text: $token,
                    prompt: Text("Vercel access token")
                        .foregroundStyle(Color.black.opacity(0.3))
                )
                .textFieldStyle(.plain)
                .focused($isTokenFieldFocused)
                .disabled(isBusy)
                .onSubmit(submit)
                .accessibilityHint(error.map(errorMessage(for:)) ?? "Paste a Vercel Personal Access Token")
            )
        }
    }

    private func tokenFieldChrome(_ content: some View) -> some View {
        content
            .font(AppTypography.geistMedium12)
            .padding(.horizontal, 12)
            .frame(
                width: VercelConnectionLayout.tokenFieldSize.width,
                height: VercelConnectionLayout.tokenFieldSize.height
            )
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(fieldBorderColor, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !rendersStaticTokenField, !isBusy else { return }
                isTokenFieldFocused = true
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.iBeam.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
    }

    private var staticTokenText: String {
        token.isEmpty ? "Vercel access token" : String(repeating: "•", count: 48)
    }

    private var isBusy: Bool {
        isValidating || isSubmitting
    }

    private var canSubmit: Bool {
        VercelConnectionFormState.canSubmit(token: token, isBusy: isBusy)
    }

    private var fieldBorderColor: Color {
        error == nil ? AnalyticsCardColors.connectionBorder : AnalyticsCardColors.connectionError.opacity(0.65)
    }

    private var connectButtonBackground: Color {
        canSubmit || isBusy ? .black : .black.opacity(0.2)
    }

    private func submit() {
        guard canSubmit else { return }

        isSubmitting = true
        let submittedToken = token
        Task {
            if await VercelConnectionAction.connect(model: model, token: submittedToken) {
                token = ""
            }
            isSubmitting = false
        }
    }

    private func errorMessage(for error: AccountConnectionError) -> String {
        [error.localizedDescription, error.recoverySuggestion]
            .compactMap(\.self)
            .joined(separator: " ")
    }

    private func announce(_ error: AccountConnectionError) {
        guard let application = NSApp else { return }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: errorMessage(for: error),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private static let tokenSettingsURL = URL(string: "https://vercel.com/account/tokens")!
}
