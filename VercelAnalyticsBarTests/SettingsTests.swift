import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Test func settingsLayoutMatchesTheProductionAndDeveloperFigmaFrames() {
    #expect(SettingsLayout.contentWidth == 384)
    #expect(SettingsLayout.productionHeight == 528)
    #expect(SettingsLayout.developerHeight == 572)
    #expect(SettingsLayout.projectListSize == CGSize(width: 352, height: 300))
    #expect(SettingsLayout.projectRowHeight == 26)
    #expect(SettingsLayout.actionSize == CGSize(width: 112, height: 32))
    #expect(SettingsLayout.actionSpacing == 8)
    #expect(SettingsLayout.inspectorSize == CGSize(width: 352, height: 32))
    #expect(SettingsLayout.contentHeight(showsChartInspector: false) == 528)
    #expect(SettingsLayout.contentHeight(showsChartInspector: true) == 572)
}

@Test func settingsIdentityFormatsAvailableAccountNames() {
    #expect(SettingsAccountIdentity.label(for: VercelAccountProfile(
        name: "Jason Jun",
        username: "jasonjun"
    )) == "Jason Jun (jasonjun)")
    #expect(SettingsAccountIdentity.label(for: VercelAccountProfile(
        name: "Jason",
        username: "jason"
    )) == "Jason")
    #expect(SettingsAccountIdentity.label(for: VercelAccountProfile(username: "jasonjun")) == "jasonjun")
    #expect(SettingsAccountIdentity.label(for: VercelAccountProfile(name: "Jason Jun")) == "Jason Jun")
    #expect(SettingsAccountIdentity.label(for: VercelAccountProfile(name: " ", username: "\n")) ==
        "Vercel account")
    #expect(SettingsAccountIdentity.label(for: nil) == "Vercel account")
}

@MainActor
@Test func manualProjectRefreshRetainsDataUpdatesProfileAndDoesNotLoadAnalytics() async {
    let fixture = makeManualRefreshFixture()
    await fixture.model.connect(token: "valid-token")
    let refreshTask = Task { await fixture.model.refreshProjects() }
    await fixture.discoveryProvider.waitUntilRefreshRequested()

    #expect(fixture.model.isRefreshingProjects)
    #expect(fixture.model.connectedAccount == fixture.oldProfile)
    #expect(fixture.model.projectState == .loaded([fixture.retainedProject, fixture.removedProject]))
    #expect(await fixture.analyticsProvider.requestedRanges.isEmpty)

    await fixture.discoveryProvider.succeed(with: VercelAccountDiscovery(
        profile: fixture.newProfile,
        projects: [fixture.retainedProject, fixture.newestProject]
    ))
    await refreshTask.value

    #expect(!fixture.model.isRefreshingProjects)
    #expect(fixture.model.projectRefreshError == nil)
    #expect(fixture.model.connectedAccount == fixture.newProfile)
    #expect(fixture.model.projectState == .loaded([fixture.newestProject, fixture.retainedProject]))
    #expect(fixture.model.selectedProjectIDs == [fixture.retainedProject.id])
    #expect(fixture.model.currentProjectID == fixture.retainedProject.id)
    #expect(await fixture.analyticsProvider.requestedRanges.isEmpty)
}

@MainActor
@Test func failedManualProjectRefreshRetainsExistingDataAndExposesDismissibleError() async {
    let profile = VercelAccountProfile(name: "Fixture User", username: "fixture-user")
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let discoveryProvider = ControlledAccountDiscoveryProvider(
        initialDiscovery: VercelAccountDiscovery(profile: profile, projects: [project])
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(
            selectedProjectIDs: [project.id],
            currentProjectID: project.id
        ),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in discoveryProvider },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    let refreshTask = Task { await model.refreshProjects() }
    await discoveryProvider.waitUntilRefreshRequested()

    #expect(model.isRefreshingProjects)
    #expect(model.projectState == .loaded([project]))

    await discoveryProvider.fail(with: SnapshotError.unavailable)
    await refreshTask.value

    #expect(!model.isRefreshingProjects)
    #expect(model.projectState == .loaded([project]))
    #expect(model.connectedAccount == profile)
    #expect(model.projectRefreshError != nil)

    model.clearProjectRefreshError()
    #expect(model.projectRefreshError == nil)
}

@MainActor
@Test func settingsPopulatedFixturesRenderAtRetinaScale() async throws {
    let model = makeSettingsModel(
        provider: SettingsFixtureAccountDiscoveryProvider(discovery: VercelAccountDiscovery(
            profile: VercelAccountProfile(name: "Jason Jun", username: "jasonjun"),
            projects: settingsFixtureProjects
        )),
        selectedProjectIDs: ["project-personal", "project-team"]
    )
    await model.connect(token: "fixture-token")

    try renderSettingsFixture(
        model: model,
        showsChartInspector: false,
        outputName: "settings-populated-current.png"
    )
    try renderSettingsFixture(
        model: model,
        showsChartInspector: true,
        outputName: "settings-developer-current.png"
    )
}

@MainActor
@Test func settingsEmptyFixtureRendersAtRetinaScale() async throws {
    let model = makeSettingsModel(provider: SettingsFixtureAccountDiscoveryProvider(discovery: VercelAccountDiscovery(
        profile: VercelAccountProfile(username: "fixture-user"),
        projects: []
    )))
    await model.connect(token: "fixture-token")

    try renderSettingsFixture(model: model, outputName: "settings-empty-current.png")
}

@MainActor
@Test func settingsFailureFixtureRendersAtRetinaScale() async throws {
    let model = makeSettingsModel(provider: FailingProjectListingProvider(error: SnapshotError.unavailable))
    await model.connect(token: "fixture-token")

    try renderSettingsFixture(model: model, outputName: "settings-failure-current.png")
}

@MainActor
@Test func settingsLoadingFixtureRendersAtRetinaScale() async throws {
    let provider = PendingAccountDiscoveryProvider()
    let model = makeSettingsModel(provider: provider)
    let connectTask = Task { await model.connect(token: "fixture-token") }
    await provider.waitUntilRequested()

    try renderSettingsFixture(model: model, outputName: "settings-loading-current.png")

    await provider.succeed(with: VercelAccountDiscovery(profile: nil, projects: []))
    await connectTask.value
}

@MainActor
private func makeSettingsModel(
    provider: any VercelProjectListingProviding,
    selectedProjectIDs: Set<String> = []
) -> AppModel {
    AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(
            selectedProjectIDs: selectedProjectIDs,
            currentProjectID: selectedProjectIDs.sorted().first
        ),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in provider },
        launchAtLoginManager: InMemoryLaunchAtLoginManager(),
        tokenValidator: { _ in }
    )
}

@MainActor
private func renderSettingsFixture(
    model: AppModel,
    showsChartInspector: Bool = false,
    outputName: String
) throws {
    AppFontRegistry.registerBundledFonts()
    let size = CGSize(
        width: SettingsLayout.contentWidth,
        height: SettingsLayout.contentHeight(showsChartInspector: showsChartInspector)
    )
    let hostingView = NSHostingView(rootView: SettingsRootView(
        model: model,
        isChartInspectorEnabled: showsChartInspector,
        onOpenChartInspector: {}
    )
    .environment(\.controlActiveState, .key))
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    guard let imageRepresentation = makeSettingsRetinaImageRepresentation(size: size) else {
        Issue.record("Unable to create the settings image representation")
        return
    }
    imageRepresentation.size = size
    hostingView.cacheDisplay(in: hostingView.bounds, to: imageRepresentation)

    guard let renderedImage = imageRepresentation.cgImage else {
        Issue.record("Unable to render the settings fixture")
        return
    }

    #expect(renderedImage.width == Int(size.width * 2))
    #expect(renderedImage.height == Int(size.height * 2))

    let outputDirectory = settingsRepositoryRoot.appendingPathComponent(".build/VisualDiff", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try writeSettingsPNG(renderedImage, to: outputDirectory.appendingPathComponent(outputName))
}

private func makeSettingsRetinaImageRepresentation(size: CGSize) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * 2),
        pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

private func writeSettingsPNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw SettingsFixtureError.unableToCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw SettingsFixtureError.unableToWriteImage
    }
}

private let settingsFixtureProjects = [
    VercelProject(
        id: "project-personal",
        name: "nodejourney-web",
        updatedAt: Date(timeIntervalSince1970: 300)
    ),
    VercelProject(
        id: "project-team",
        name: "nodejourney-web",
        updatedAt: Date(timeIntervalSince1970: 200),
        teamID: "team-a",
        teamName: "Team A"
    ),
    VercelProject(
        id: "project-news",
        name: "hacker-news",
        updatedAt: Date(timeIntervalSince1970: 100)
    ),
]

private let settingsRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private enum SettingsFixtureError: Error {
    case unableToCreateDestination
    case unableToWriteImage
}
