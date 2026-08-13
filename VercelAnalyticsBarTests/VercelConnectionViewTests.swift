import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Test func vercelConnectionLayoutMatchesTheReferenceFrames() {
    #expect(VercelConnectionLayout.introductionHeight == 466)
    #expect(VercelConnectionLayout.footerHeight == 80)
    #expect(VercelConnectionLayout.introductionWidth == 296)
    #expect(VercelConnectionLayout.introductionContentHeight == 174)
    #expect(VercelConnectionLayout.tokenManagementButtonSize == CGSize(width: 185, height: 32))
    #expect(VercelConnectionLayout.tokenFieldSize == CGSize(width: 258, height: 32))
    #expect(VercelConnectionLayout.connectButtonSize == CGSize(width: 68, height: 32))
    #expect(VercelConnectionLayout.formSpacing == 8)
    #expect(VercelConnectionLayout.formWidth == 334)
    #expect(VercelConnectionLayout.introductionHeight + VercelConnectionLayout.footerHeight ==
        AnalyticsCardLayout.cardSize.height)
}

@Test func vercelConnectionFormRequiresANonemptyTokenAndIdleState() {
    #expect(!VercelConnectionFormState.canSubmit(token: "", isBusy: false))
    #expect(!VercelConnectionFormState.canSubmit(token: "  \n", isBusy: false))
    #expect(VercelConnectionFormState.canSubmit(token: "vercel-token", isBusy: false))
    #expect(!VercelConnectionFormState.canSubmit(token: "vercel-token", isBusy: true))
}

@Test func vercelProjectSelectionLayoutMatchesTheReferenceFrame() {
    #expect(VercelProjectSelectionLayout.titleTopPadding == 32)
    #expect(VercelProjectSelectionLayout.titleHeight == 20)
    #expect(VercelProjectSelectionLayout.titleToListSpacing == 24)
    #expect(VercelProjectSelectionLayout.listSize == CGSize(width: 336, height: 390))
    #expect(VercelProjectSelectionLayout.listCornerRadius == 8)
    #expect(VercelProjectSelectionLayout.listHorizontalPadding == 12)
    #expect(VercelProjectSelectionLayout.listVerticalPadding == 8)
    #expect(VercelProjectSelectionLayout.projectRowHeight == 26)
    #expect(VercelProjectSelectionLayout.listToButtonsSpacing == 24)
    #expect(VercelProjectSelectionLayout.buttonSpacing == 8)
    #expect(VercelProjectSelectionLayout.buttonSize == CGSize(width: 164, height: 32))
    #expect(VercelProjectSelectionLayout.bottomPadding == 24)
}

@Test func vercelProjectSelectionRequiresASelectionAndIdleState() {
    #expect(!VercelProjectSelectionFormState.canConfirm(selectedProjectIDs: [], isBusy: false))
    #expect(VercelProjectSelectionFormState.canConfirm(selectedProjectIDs: ["project-a"], isBusy: false))
    #expect(!VercelProjectSelectionFormState.canConfirm(selectedProjectIDs: ["project-a"], isBusy: true))
}

@Test func menuBarContentModeRoutesLiveAndStandaloneProviders() {
    #expect(resolve(.disconnected) == .connection(error: nil, isValidating: false))
    #expect(resolve(.restoring) == .restoring)
    #expect(resolve(.validating) == .connection(error: nil, isValidating: true))
    #expect(resolve(.failed(.invalidToken)) == .connection(error: .invalidToken, isValidating: false))
    #expect(resolve(.connected, projectState: .idle) == .preparingProjects)
    #expect(resolve(.connected, projectState: .loading) == .preparingProjects)
    #expect(resolve(.connected, projectState: .failed("Unavailable")) == .projectSelection)
    #expect(resolve(.connected, projectState: .loaded([])) == .projectSelection)
    #expect(resolve(
        .connected,
        projectState: .loaded([VercelProject(id: "project-a", name: "Alpha")]),
        hasConfirmedProjectSelection: true
    ) == .analytics)
    #expect(resolve(
        .connected,
        projectState: .loading,
        hasConfirmedProjectSelection: true
    ) == .preparingProjects)
    #expect(resolve(
        .connected,
        projectState: .failed("Unavailable"),
        hasConfirmedProjectSelection: true
    ) == .analytics)
    #expect(MenuBarContentMode.resolve(
        accountState: .disconnected,
        projectState: .idle,
        hasConfirmedProjectSelection: false,
        hasStandaloneSnapshotProvider: true
    ) == .analytics)
}

@MainActor
@Test func vercelConnectionEmptyFixtureRendersAtRetinaScale() throws {
    try renderVercelConnectionFixture(
        initialToken: "",
        error: nil,
        outputName: "connection-empty-current.png"
    )
}

@MainActor
@Test func vercelConnectionFilledFixtureRendersAtRetinaScale() throws {
    try renderVercelConnectionFixture(
        initialToken: "vercel-fixture-token",
        error: nil,
        outputName: "connection-filled-current.png"
    )
}

@MainActor
@Test func vercelConnectionErrorFixtureRendersAtRetinaScale() throws {
    try renderVercelConnectionFixture(
        initialToken: "invalid-fixture-token",
        error: .invalidToken,
        outputName: "connection-error-current.png"
    )
}

@MainActor
@Test func vercelProjectSelectionPopulatedFixtureRendersAtRetinaScale() throws {
    try renderVercelProjectSelectionFixture(
        projectState: .loaded(projectSelectionFixtureProjects),
        initialSelectedProjectIDs: ["project-a", "project-b"],
        outputName: "project-selection-populated-current.png"
    )
}

@MainActor
@Test func vercelProjectSelectionEmptyFixtureRendersAtRetinaScale() throws {
    try renderVercelProjectSelectionFixture(
        projectState: .loaded([]),
        outputName: "project-selection-empty-current.png"
    )
}

@MainActor
@Test func vercelProjectSelectionLoadingFixtureRendersAtRetinaScale() throws {
    try renderVercelProjectSelectionFixture(
        projectState: .loading,
        outputName: "project-selection-loading-current.png"
    )
}

@MainActor
@Test func vercelProjectSelectionErrorFixtureRendersAtRetinaScale() throws {
    try renderVercelProjectSelectionFixture(
        projectState: .failed("Fixture failure"),
        outputName: "project-selection-error-current.png"
    )
}

private func resolve(
    _ accountState: AppModel.AccountState,
    projectState: AppModel.ProjectState = .idle,
    hasConfirmedProjectSelection: Bool = false
) -> MenuBarContentMode {
    MenuBarContentMode.resolve(
        accountState: accountState,
        projectState: projectState,
        hasConfirmedProjectSelection: hasConfirmedProjectSelection,
        hasStandaloneSnapshotProvider: false
    )
}

@MainActor
private func renderVercelConnectionFixture(
    initialToken: String,
    error: AccountConnectionError?,
    outputName: String
) throws {
    AppFontRegistry.registerBundledFonts()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: InMemoryLaunchAtLoginManager()
    )
    let renderer = ImageRenderer(content: VercelConnectionView(
        model: model,
        error: error,
        isValidating: false,
        initialToken: initialToken,
        rendersStaticTokenField: true
    ))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(
        width: AnalyticsCardLayout.rootSize.width,
        height: AnalyticsCardLayout.rootSize.height
    )

    guard let image = renderer.nsImage,
          let renderedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        Issue.record("Unable to render the Vercel connection fixture")
        return
    }

    #expect(renderedImage.width == 800)
    #expect(renderedImage.height == 1124)

    let outputDirectory = repositoryRoot.appendingPathComponent(".build/VisualDiff", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try writeConnectionPNG(renderedImage, to: outputDirectory.appendingPathComponent(outputName))
}

@MainActor
private func renderVercelProjectSelectionFixture(
    projectState: AppModel.ProjectState,
    initialSelectedProjectIDs: Set<String> = [],
    outputName: String
) throws {
    AppFontRegistry.registerBundledFonts()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: InMemoryLaunchAtLoginManager()
    )
    let hostingView = NSHostingView(rootView: VercelProjectSelectionView(
        model: model,
        initialSelectedProjectIDs: initialSelectedProjectIDs,
        projectStateOverride: projectState
    )
    .environment(\.controlActiveState, .key))
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: AnalyticsCardLayout.rootSize),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    hostingView.frame = CGRect(
        origin: .zero,
        size: AnalyticsCardLayout.rootSize
    )
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    guard let imageRepresentation = makeRetinaImageRepresentation() else {
        Issue.record("Unable to create the Vercel project selection image representation")
        return
    }
    imageRepresentation.size = NSSize(
        width: AnalyticsCardLayout.rootSize.width,
        height: AnalyticsCardLayout.rootSize.height
    )
    hostingView.cacheDisplay(in: hostingView.bounds, to: imageRepresentation)

    guard let renderedImage = imageRepresentation.cgImage else {
        Issue.record("Unable to render the Vercel project selection fixture")
        return
    }

    #expect(renderedImage.width == 800)
    #expect(renderedImage.height == 1124)

    let outputDirectory = repositoryRoot.appendingPathComponent(".build/VisualDiff", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try writeConnectionPNG(renderedImage, to: outputDirectory.appendingPathComponent(outputName))
}

private func makeRetinaImageRepresentation() -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(AnalyticsCardLayout.rootSize.width * 2),
        pixelsHigh: Int(AnalyticsCardLayout.rootSize.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

private let projectSelectionFixtureProjects = [
    VercelProject(id: "project-a", name: "jasonjun-dev-2024"),
    VercelProject(id: "project-b", name: "nodejourney-web"),
    VercelProject(id: "project-c", name: "github-profile-viewer"),
    VercelProject(id: "project-d", name: "hacker-news"),
    VercelProject(id: "project-e", name: "horizontal-masonry-demo"),
]

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func writeConnectionPNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ConnectionFixtureError.unableToCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ConnectionFixtureError.unableToWriteImage
    }
}

private enum ConnectionFixtureError: Error {
    case unableToCreateDestination
    case unableToWriteImage
}
