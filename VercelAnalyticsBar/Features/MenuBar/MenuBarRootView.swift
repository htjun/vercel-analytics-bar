import SwiftUI
import VercelAnalyticsCore

enum MenuBarContentMode: Equatable {
    case analytics
    case restoring
    case preparingProjects
    case connection(error: AccountConnectionError?, isValidating: Bool)
    case projectSelection

    static func resolve(
        accountState: AppModel.AccountState,
        projectState: AppModel.ProjectState,
        hasConfirmedProjectSelection: Bool,
        hasStandaloneSnapshotProvider: Bool
    ) -> MenuBarContentMode {
        guard !hasStandaloneSnapshotProvider else { return .analytics }

        switch accountState {
        case .disconnected:
            return .connection(error: nil, isValidating: false)
        case .restoring:
            return .restoring
        case .validating:
            return .connection(error: nil, isValidating: true)
        case .connected:
            switch projectState {
            case .idle, .loading:
                return .preparingProjects
            case .loaded, .failed:
                return hasConfirmedProjectSelection ? .analytics : .projectSelection
            }
        case let .failed(error):
            return .connection(error: error, isValidating: false)
        }
    }
}

struct MenuBarRootView: View {
    let model: AppModel
    let componentStyle: ComponentStyleStore
    var chartIntroPlayback: ChartIntroPlayback?
    var breakdownListIntroPlayback: BreakdownListIntroPlayback?
    #if MOCK_MODE
        let demoMetricTicker: DemoMetricTicker
        let openedAt: Date
    #endif
    let onOpenSettings: () -> Void
    let onDismissPanel: () -> Void
    @State private var isProjectSelectorPresented = false
    @State private var projectSearchQuery = ""
    @State private var selectedBreakdown = AnalyticsBreakdownSelection.pages
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .onExitCommand(perform: onDismissPanel)
    }

    @ViewBuilder
    private var content: some View {
        switch contentMode {
        case .analytics:
            analyticsContent
        case .restoring:
            AnalyticsCardShell {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Restoring Vercel connection")
            }
        case .preparingProjects:
            AnalyticsCardShell {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Vercel projects")
            }
        case let .connection(error, isValidating):
            VercelConnectionView(
                model: model,
                error: error,
                isValidating: isValidating
            )
        case .projectSelection:
            VercelProjectSelectionView(model: model)
        }
    }

    private var contentMode: MenuBarContentMode {
        MenuBarContentMode.resolve(
            accountState: model.accountState,
            projectState: model.projectState,
            hasConfirmedProjectSelection: !model.selectedProjectIDs.isEmpty,
            hasStandaloneSnapshotProvider: model.provider != nil
        )
    }

    @ViewBuilder
    private var analyticsContent: some View {
        switch model.state {
        case .idle, .loading:
            AnalyticsCardShell {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading analytics")
            }

        case let .empty(message):
            AnalyticsCardShell {
                statusContent(
                    title: "No analytics data",
                    message: message,
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }

        case let .loaded(snapshot):
            snapshotContent(snapshot)

        case let .failed(message):
            AnalyticsCardShell {
                statusContent(
                    title: "Analytics unavailable",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    showsRetry: true
                )
            }
        }
    }

    private func snapshotContent(_ snapshot: AnalyticsSnapshot) -> some View {
        AnalyticsCardView(
            presentation: presentation(for: snapshot),
            chartStyle: componentStyle.chartStyle,
            breakdownListStyle: componentStyle.listStyle,
            chartIntroPlayback: chartIntroPlayback,
            breakdownListIntroPlayback: breakdownListIntroPlayback,
            isProjectSelectorPresented: $isProjectSelectorPresented,
            selectedBreakdown: $selectedBreakdown,
            projectSelectorContent: {
                ProjectSelectorView(
                    model: model,
                    searchQuery: $projectSearchQuery,
                    isPresented: $isProjectSelectorPresented
                )
            },
            onSelectProject: {
                projectSearchQuery = ""
                isProjectSelectorPresented = true
            },
            onSelectRange: { range in
                Task {
                    await model.selectAnalyticsRange(range)
                }
            },
            onOpenSettings: onOpenSettings,
            onOpenDashboard: { url in
                onDismissPanel()
                openURL(url)
            }
        )
    }

    private func presentation(for snapshot: AnalyticsSnapshot) -> AnalyticsCardPresentation {
        let presentation = AnalyticsCardPresentation(
            projectName: model.currentProject?.name ?? snapshot.projectName,
            selectedRange: snapshot.range,
            visitors: AnalyticsCardMetric(metric: snapshot.visitors),
            pageViews: AnalyticsCardMetric(metric: snapshot.pageViews),
            series: snapshot.series,
            topPages: snapshot.topPages,
            topReferrers: snapshot.topReferrers,
            updatedText: updatedText(for: snapshot),
            dashboardURL: model.currentProject?.analyticsDashboardURL(for: snapshot.range)
        )

        #if MOCK_MODE
            return presentation.applyingDemoOffsets(demoMetricTicker.offsets)
        #else
            return presentation
        #endif
    }

    private func updatedText(for snapshot: AnalyticsSnapshot) -> String {
        #if MOCK_MODE
            return "Opened \(openedAt.formatted(date: .omitted, time: .shortened))"
        #else
            let timestamp = snapshot.refreshedAt.formatted(date: .omitted, time: .shortened)
            return model.snapshotFreshness == .stale ? "Stale · Updated \(timestamp)" : "Updated \(timestamp)"
        #endif
    }

    private func statusContent(
        title: String,
        message: String,
        systemImage: String,
        showsRetry: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            if showsRetry {
                Button("Retry") {
                    Task {
                        await model.retryRefresh()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectSelectorView: View {
    private static let titleHeight: CGFloat = 17
    private static let searchFieldHeight: CGFloat = 22
    private static let emptyResultHeight: CGFloat = 17
    private static let projectRowHeight: CGFloat = 28
    private static let projectRowWithMetadataHeight: CGFloat = 44
    private static let rowSpacing: CGFloat = 2
    private static let contentSpacing: CGFloat = 10
    private static let verticalPadding: CGFloat = 24
    private static let maxProjectListHeight: CGFloat = 240

    let model: AppModel
    @Binding var searchQuery: String
    @Binding var isPresented: Bool

    var body: some View {
        let projects = model.selectedProjects(matching: searchQuery)

        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            Text("Projects")
                .font(.headline)
                .frame(height: Self.titleHeight)

            TextField("Find Project…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(height: Self.searchFieldHeight)

            if projects.isEmpty {
                Text("No selected projects match this search.")
                    .frame(maxWidth: .infinity, minHeight: Self.emptyResultHeight, alignment: .leading)
                    .foregroundStyle(.secondary)
            } else {
                if projectListHeight(projects) <= Self.maxProjectListHeight {
                    projectList(projects)
                } else {
                    ScrollView {
                        projectList(projects)
                    }
                    .frame(height: Self.maxProjectListHeight)
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: selectorHeight(projects), alignment: .topLeading)
    }

    private func projectList(_ projects: [VercelProject]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(projects) { project in
                projectRow(project)
            }
        }
    }

    private func projectListHeight(_ projects: [VercelProject]) -> CGFloat {
        let rowsHeight = projects.reduce(CGFloat.zero) { height, project in
            height + rowHeight(project)
        }
        let spacingHeight = CGFloat(max(projects.count - 1, 0)) * Self.rowSpacing
        return rowsHeight + spacingHeight
    }

    private func selectorHeight(_ projects: [VercelProject]) -> CGFloat {
        let resultsHeight = projects.isEmpty
            ? Self.emptyResultHeight
            : min(projectListHeight(projects), Self.maxProjectListHeight)
        return Self.titleHeight
            + Self.searchFieldHeight
            + resultsHeight
            + Self.contentSpacing * 2
            + Self.verticalPadding
    }

    private func rowHeight(_ project: VercelProject) -> CGFloat {
        model.teamMetadata(for: project) == nil
            ? Self.projectRowHeight
            : Self.projectRowWithMetadataHeight
    }

    private func projectRow(_ project: VercelProject) -> some View {
        Button {
            isPresented = false
            Task {
                await model.selectProject(project.id)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .lineLimit(1)
                    if let metadata = model.teamMetadata(for: project) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if project.id == model.currentProjectID {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(project.id == model.currentProjectID ? Color.primary.opacity(0.08) : .clear)
        )
        .frame(height: rowHeight(project))
    }
}
