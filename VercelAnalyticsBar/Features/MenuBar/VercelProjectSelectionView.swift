import SwiftUI
import VercelAnalyticsCore

enum VercelProjectSelectionLayout {
    static let titleTopPadding: CGFloat = 32
    static let titleHeight: CGFloat = 20
    static let titleToListSpacing: CGFloat = 24
    static let listSize = CGSize(width: 336, height: 390)
    static let listCornerRadius: CGFloat = 8
    static let listHorizontalPadding: CGFloat = 12
    static let listVerticalPadding: CGFloat = 8
    static let projectRowHeight: CGFloat = 26
    static let listToButtonsSpacing: CGFloat = 24
    static let buttonSpacing: CGFloat = 8
    static let buttonSize = CGSize(width: 164, height: 32)
    static let bottomPadding: CGFloat = 24
}

enum VercelProjectSelectionFormState {
    static func canConfirm(selectedProjectIDs: Set<String>, isBusy: Bool) -> Bool {
        !selectedProjectIDs.isEmpty && !isBusy
    }
}

@MainActor
enum VercelProjectSelectionAction {
    static func confirm(model: AppModel, projectIDs: Set<String>) async -> Bool {
        guard model.confirmProjectSelection(projectIDs) else { return false }
        await model.load()
        return true
    }

    static func cancel(model: AppModel) {
        model.disconnect()
    }
}

struct VercelProjectSelectionView: View {
    let model: AppModel
    private let projectStateOverride: AppModel.ProjectState?

    @State private var selectedProjectIDs: Set<String>
    @State private var isConfirming = false
    @State private var actionError: String?

    init(
        model: AppModel,
        initialSelectedProjectIDs: Set<String> = [],
        projectStateOverride: AppModel.ProjectState? = nil
    ) {
        self.model = model
        self.projectStateOverride = projectStateOverride
        _selectedProjectIDs = State(initialValue: initialSelectedProjectIDs)
    }

    var body: some View {
        AnalyticsCardShell {
            VStack(spacing: 0) {
                Text("Select projects")
                    .font(AppTypography.geistSemibold16)
                    .tracking(AppTypography.connectionTitleTracking)
                    .foregroundStyle(AnalyticsCardColors.connectionText)
                    .frame(height: VercelProjectSelectionLayout.titleHeight)
                    .padding(.top, VercelProjectSelectionLayout.titleTopPadding)

                Spacer()
                    .frame(height: VercelProjectSelectionLayout.titleToListSpacing)

                projectList

                Spacer()
                    .frame(height: VercelProjectSelectionLayout.listToButtonsSpacing)

                actionButtons

                Spacer()
                    .frame(height: VercelProjectSelectionLayout.bottomPadding)
            }
            .frame(
                width: AnalyticsCardLayout.cardSize.width,
                height: AnalyticsCardLayout.cardSize.height
            )
        }
        .onChange(of: availableProjectIDs) { _, availableProjectIDs in
            selectedProjectIDs.formIntersection(availableProjectIDs)
        }
    }

    @ViewBuilder
    private var projectListContent: some View {
        switch projectState {
        case .idle, .loading:
            centeredListStatus {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading Vercel projects")
            }

        case let .loaded(projects):
            if projects.isEmpty {
                centeredListStatus {
                    Text("No accessible projects were found.")
                        .font(AppTypography.geistRegular12)
                        .foregroundStyle(AnalyticsCardColors.connectionText.opacity(0.5))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(projects) { project in
                            projectRow(project)
                        }
                    }
                    .padding(.horizontal, VercelProjectSelectionLayout.listHorizontalPadding)
                    .padding(.vertical, VercelProjectSelectionLayout.listVerticalPadding)
                }
            }

        case .failed:
            centeredListStatus {
                VStack(spacing: 10) {
                    Text("Projects could not be loaded.")
                        .font(AppTypography.geistRegular12)
                        .foregroundStyle(AnalyticsCardColors.connectionText.opacity(0.5))

                    Button("Retry") {
                        Task {
                            await model.refreshProjects()
                        }
                    }
                    .font(AppTypography.geistMedium12)
                }
            }
        }
    }

    private var projectList: some View {
        ZStack(alignment: .bottom) {
            projectListContent

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.geistRegular12)
                    .foregroundStyle(AnalyticsCardColors.connectionError)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .accessibilityLabel("Project selection error. \(errorMessage)")
            }
        }
        .frame(
            width: VercelProjectSelectionLayout.listSize.width,
            height: VercelProjectSelectionLayout.listSize.height
        )
        .overlay {
            RoundedRectangle(cornerRadius: VercelProjectSelectionLayout.listCornerRadius)
                .stroke(AnalyticsCardColors.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: VercelProjectSelectionLayout.listCornerRadius))
    }

    private func projectRow(_ project: VercelProject) -> some View {
        Toggle(isOn: selectionBinding(for: project.id)) {
            HStack(spacing: 6) {
                Text(project.name)
                    .foregroundStyle(.black)

                if let metadata = model.teamMetadata(for: project) {
                    Text(metadata)
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            }
            .font(AppTypography.geistRegular12)
            .lineLimit(1)
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, minHeight: VercelProjectSelectionLayout.projectRowHeight, alignment: .leading)
        .disabled(isConfirming)
    }

    private var actionButtons: some View {
        HStack(spacing: VercelProjectSelectionLayout.buttonSpacing) {
            Button(action: cancel) {
                buttonLabel("Cancel", showsProgress: false)
                    .foregroundStyle(AnalyticsCardColors.primaryText)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AnalyticsCardColors.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isConfirming)

            Button(action: confirm) {
                buttonLabel("Confirm", showsProgress: isConfirming)
                    .foregroundStyle(.white)
                    .background(confirmButtonBackground, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func buttonLabel(_ title: String, showsProgress: Bool) -> some View {
        Group {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Text(title)
                    .font(AppTypography.geistMedium12)
            }
        }
        .frame(
            width: VercelProjectSelectionLayout.buttonSize.width,
            height: VercelProjectSelectionLayout.buttonSize.height
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func centeredListStatus(_ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectionBinding(for projectID: String) -> Binding<Bool> {
        Binding(
            get: { selectedProjectIDs.contains(projectID) },
            set: { isSelected in
                actionError = nil
                if isSelected {
                    selectedProjectIDs.insert(projectID)
                } else {
                    selectedProjectIDs.remove(projectID)
                }
            }
        )
    }

    private var projectState: AppModel.ProjectState {
        projectStateOverride ?? model.projectState
    }

    private var availableProjectIDs: Set<String> {
        guard case let .loaded(projects) = projectState else { return [] }
        return Set(projects.map(\.id))
    }

    private var canConfirm: Bool {
        VercelProjectSelectionFormState.canConfirm(
            selectedProjectIDs: selectedProjectIDs,
            isBusy: isConfirming
        )
    }

    private var confirmButtonBackground: Color {
        canConfirm ? .black : .black.opacity(0.2)
    }

    private var errorMessage: String? {
        actionError ?? model.projectSelectionError
    }

    private func confirm() {
        guard canConfirm else { return }
        isConfirming = true
        let confirmedProjectIDs = selectedProjectIDs

        Task {
            defer { isConfirming = false }
            guard await VercelProjectSelectionAction.confirm(
                model: model,
                projectIDs: confirmedProjectIDs
            ) else {
                actionError = model.projectSelectionError ?? "The project selection could not be confirmed. Try again."
                return
            }
        }
    }

    private func cancel() {
        guard !isConfirming else { return }
        VercelProjectSelectionAction.cancel(model: model)
    }
}
