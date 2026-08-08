import AppKit
import SwiftUI
import VercelAnalyticsCore

struct MenuBarRootView: View {
    let model: AppModel
    let chartStyle: ChartStyleStore
    @State private var isProjectSelectorPresented = false
    @State private var projectSearchQuery = ""
    #if CHART_INSPECTOR
        @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings")
                }

                #if CHART_INSPECTOR
                    Button("Chart Inspector") {
                        openWindow(id: ChartInspectorScene.id)
                    }
                #endif

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
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

        case let .empty(message):
            VStack(alignment: .leading, spacing: 10) {
                Label("No analytics data", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(snapshot):
            snapshotContent(snapshot)

        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Analytics unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                if let refreshMessage = model.refreshMessage, refreshMessage != message {
                    Text(refreshMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Retry") {
                    Task {
                        await model.retryRefresh()
                    }
                }
            }
        }
    }

    private func snapshotContent(_ snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let currentProject = model.currentProject {
                    projectSelectorButton(for: currentProject)
                } else {
                    Text(snapshot.projectName)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Picker("Range", selection: rangeSelection) {
                    ForEach(VercelAnalyticsRange.allCases, id: \.self) { range in
                        Text(range.title)
                            .tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if model.snapshotFreshness == .stale {
                staleRefreshContent
            }

            HStack(alignment: .top, spacing: 12) {
                MetricSummaryView(metric: snapshot.visitors)
                MetricSummaryView(metric: snapshot.pageViews)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Visitors over time")
                    .font(.subheadline.weight(.medium))

                if snapshot.series.isEmpty {
                    Text("No trend data for this period.")
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .foregroundStyle(.secondary)
                } else {
                    VisitorsChart(points: snapshot.series, style: chartStyle.style)
                }
            }

            snapshotFooter(snapshot)
        }
    }

    private func snapshotFooter(_ snapshot: AnalyticsSnapshot) -> some View {
        let dashboardURL = model.currentProject?.analyticsDashboardURL(for: snapshot.range)

        return HStack {
            Text(snapshot.range.title)
                .foregroundStyle(.secondary)

            if let dashboardURL {
                Link(destination: dashboardURL) {
                    Label("View in Vercel", systemImage: "arrow.up.right.square")
                }
                .help("Open this project's analytics in Vercel")
            }

            Spacer()

            Text(updatedText(for: snapshot))
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func updatedText(for snapshot: AnalyticsSnapshot) -> String {
        let timestamp = snapshot.refreshedAt.formatted(date: .omitted, time: .shortened)
        return model.snapshotFreshness == .stale ? "Stale · Updated \(timestamp)" : "Updated \(timestamp)"
    }

    private var staleRefreshContent: some View {
        HStack(spacing: 8) {
            Label("Stale data", systemImage: "clock.badge.exclamationmark")
            if let refreshMessage = model.refreshMessage {
                Text(refreshMessage)
                    .lineLimit(1)
            }
            Spacer()
            Button("Retry") {
                Task {
                    await model.retryRefresh()
                }
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private func projectSelectorButton(for project: VercelProject) -> some View {
        Button {
            projectSearchQuery = ""
            isProjectSelectorPresented = true
        } label: {
            HStack(spacing: 5) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isProjectSelectorPresented, arrowEdge: .top) {
            ProjectSelectorView(
                model: model,
                searchQuery: $projectSearchQuery,
                isPresented: $isProjectSelectorPresented
            )
        }
        .help("Switch project")
    }

    private var rangeSelection: Binding<VercelAnalyticsRange> {
        Binding(
            get: { model.selectedRange },
            set: { range in
                Task {
                    await model.selectAnalyticsRange(range)
                }
            }
        )
    }
}

private struct MetricSummaryView: View {
    let metric: AnalyticsMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(metric.value, format: .number)
                .font(.system(size: 26, weight: .semibold, design: .rounded))

            Text(comparisonText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var comparisonText: String {
        switch metric.comparison {
        case let .percentage(change):
            let sign = change > 0 ? "+" : ""
            let value = change.formatted(.number.precision(.fractionLength(0 ... 1)))
            return "\(sign)\(value)% vs previous period"
        case .new:
            return "New vs previous period"
        }
    }
}

private struct ProjectSelectorView: View {
    let model: AppModel
    @Binding var searchQuery: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Projects")
                .font(.headline)

            TextField("Find Project…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)

            let projects = model.selectedProjects(matching: searchQuery)
            if projects.isEmpty {
                Text("No selected projects match this search.")
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(projects) { project in
                            projectRow(project)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: 340)
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
    }
}
