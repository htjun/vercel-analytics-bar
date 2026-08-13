import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Test func analyticsCardMetricMatchesDisplayFormatting() {
    let visitors = AnalyticsCardMetric(
        metric: AnalyticsMetric(label: "Visitors", value: 3234, previousValue: 1167)
    )
    let pageViews = AnalyticsCardMetric(
        metric: AnalyticsMetric(label: "Page Views", value: 6423, previousValue: 6554)
    )

    #expect(visitors.valueText == "3,234")
    #expect(visitors.comparisonText == "+177%")
    #expect(visitors.trend == .positive)
    #expect(pageViews.valueText == "6,423")
    #expect(pageViews.comparisonText == "-2%")
    #expect(pageViews.trend == .negative)
}

@Test func analyticsCountFormatterUsesCompactRoundedValues() {
    let cases = [
        (0, "0"),
        (999, "999"),
        (1000, "1K"),
        (1049, "1K"),
        (1050, "1.1K"),
        (9949, "9.9K"),
        (9950, "10K"),
        (10499, "10K"),
        (10500, "11K"),
        (999_499, "999K"),
        (999_500, "1M"),
        (1_049_999, "1M"),
        (1_050_000, "1.1M"),
        (9_949_999, "9.9M"),
        (9_950_000, "10M"),
        (10_499_999, "10M"),
        (10_500_000, "11M"),
        (999_499_999, "999M"),
        (999_500_000, "999M+"),
        (Int.max, "999M+"),
    ]

    for (value, expected) in cases {
        #expect(AnalyticsCountFormatter.compact(value) == expected)
    }
}

@Test func analyticsCardLayoutAndFixturesMatchTheReferenceFrame() {
    #expect(AnalyticsCardLayout.rootSize == CGSize(width: 400, height: 562))
    #expect(AnalyticsCardLayout.cardSize == CGSize(width: 384, height: 546))
    #expect(AnalyticsCardLayout.shellInset == 8)
    #expect(AnalyticsCardLayout.outerCornerRadius == 32)
    #expect(AnalyticsCardLayout.cardCornerRadius == 24)
    #expect(AnalyticsCardLayout.chartFrame == CGRect(x: 8, y: 166, width: 368, height: 150))
    #expect(AnalyticsCardLayout.breakdownRowWidth == 344)
    #expect(AnalyticsCardLayout.breakdownCountWidth == 40)
    #expect(AnalyticsCardLayout.breakdownColumnSpacing == 8)
    #expect(AnalyticsCardLayout.breakdownLabelWidth == 296)
    #expect(AnalyticsCardPresentation.sampleFixture.projectName == "example-site")
    #expect(AnalyticsCardPresentation.pageFixtures.count == 5)
    #expect(AnalyticsCardPresentation.sampleFixture.topPages.first?.visitors == 710)
    #expect(AnalyticsCardPresentation.sampleFixture.breakdownRows(for: .pages) ==
        AnalyticsCardPresentation.pageFixtures)
    #expect(AnalyticsCardPresentation.sampleFixture.breakdownRows(for: .referrals) ==
        AnalyticsCardPresentation.referralFixtures)
    #expect(AnalyticsCardPresentation.sampleFixture.emptyBreakdownText(for: .pages) == "No page data")
    #expect(AnalyticsCardPresentation.sampleFixture.emptyBreakdownText(for: .referrals) == "No referral data")
}

@Test func analyticsGlassAppearanceHonorsReducedTransparency() {
    let standard = AnalyticsGlassAppearance.resolve(reduceTransparency: false)
    let reducedTransparency = AnalyticsGlassAppearance.resolve(reduceTransparency: true)

    #expect(standard == .standard)
    #expect(standard.showsDispersion)
    #expect(!standard.usesOpaqueBackground)
    #expect(reducedTransparency == .reducedTransparency)
    #expect(!reducedTransparency.showsDispersion)
    #expect(reducedTransparency.usesOpaqueBackground)
}

@MainActor
@Test func analyticsGlassEdgeArtworkRendersAtRetinaScale() throws {
    let fixture = ZStack {
        LinearGradient(
            colors: [
                Color(red: 236 / 255, green: 225 / 255, blue: 207 / 255),
                Color(red: 67 / 255, green: 132 / 255, blue: 227 / 255),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        AnalyticsGlassEdgeArtwork(appearance: .standard)
    }
    .frame(
        width: AnalyticsCardLayout.rootSize.width,
        height: AnalyticsCardLayout.rootSize.height
    )

    let renderer = ImageRenderer(content: fixture)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(
        width: AnalyticsCardLayout.rootSize.width,
        height: AnalyticsCardLayout.rootSize.height
    )

    guard let image = renderer.nsImage,
          let renderedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        Issue.record("Unable to render the glass edge artwork fixture")
        return
    }

    #expect(renderedImage.width == 800)
    #expect(renderedImage.height == 1124)

    let outputDirectory = repositoryRoot.appendingPathComponent(".build/VisualDiff", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try writePNG(renderedImage, to: outputDirectory.appendingPathComponent("glass-edge-current-2x.png"))
}

@MainActor
@Test func analyticsCardVisualFixtureRendersAtRetinaScale() throws {
    try renderAnalyticsCardFixture(selection: .pages, outputName: "current.png")
}

@MainActor
@Test func analyticsCardReferralFixtureRendersAtRetinaScale() throws {
    try renderAnalyticsCardFixture(selection: .referrals, outputName: "referrals-current.png")
}

@MainActor
@Test func analyticsCardLongBreakdownLabelRendersWithMaximumCompactCount() throws {
    let base = AnalyticsCardPresentation.sampleFixture
    let presentation = AnalyticsCardPresentation(
        projectName: base.projectName,
        selectedRange: base.selectedRange,
        visitors: base.visitors,
        pageViews: base.pageViews,
        series: base.series,
        topPages: [
            VercelAnalyticsBreakdown(
                label: "/blog/example-release-with-an-intentionally-long-url-segment-for-layout-testing",
                visitors: 999_500_000,
                pageViews: 999_500_000
            ),
        ],
        topReferrers: base.topReferrers,
        updatedText: base.updatedText,
        dashboardURL: base.dashboardURL
    )

    try renderAnalyticsCardFixture(
        presentation: presentation,
        selection: .pages,
        outputName: "long-breakdown-current.png",
        comparesWithReference: false
    )
}

@MainActor
private func renderAnalyticsCardFixture(
    presentation: AnalyticsCardPresentation = .sampleFixture,
    selection: AnalyticsBreakdownSelection,
    outputName: String,
    comparesWithReference: Bool = true
) throws {
    AppFontRegistry.registerBundledFonts()
    let renderer = ImageRenderer(content: AnalyticsCardView(
        presentation: presentation,
        chartStyle: .default,
        isProjectSelectorPresented: .constant(false),
        selectedBreakdown: .constant(selection),
        projectSelectorContent: { EmptyView() },
        onSelectProject: {},
        onSelectRange: { _ in },
        onOpenSettings: {},
        onOpenDashboard: { _ in }
    ))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(
        width: AnalyticsCardLayout.rootSize.width,
        height: AnalyticsCardLayout.rootSize.height
    )

    guard let image = renderer.nsImage,
          let currentImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        Issue.record("Unable to render the analytics card fixture")
        return
    }

    #expect(currentImage.width == 800)
    #expect(currentImage.height == 1124)

    let outputDirectory = repositoryRoot.appendingPathComponent(".build/VisualDiff", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let currentURL = outputDirectory.appendingPathComponent(outputName)
    try writePNG(currentImage, to: currentURL)

    guard comparesWithReference, selection == .pages else { return }

    let referenceURL = outputDirectory.appendingPathComponent("reference-2x.png")
    guard let referenceImage = loadImage(at: referenceURL) else {
        print("Visual reference not found at \(referenceURL.path); rendered current fixture only.")
        return
    }

    let result = try makeVisualDiff(reference: referenceImage, current: currentImage)
    try writePNG(result.heatmap, to: outputDirectory.appendingPathComponent("heatmap.png"))
    print("Visual diff: \(result.mismatchedPixels) mismatched unmasked pixels (\(result.ratio * 100)%)")
}

private struct VisualDiffResult {
    let heatmap: CGImage
    let mismatchedPixels: Int
    let ratio: Double
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func loadImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw VisualDiffError.unableToCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw VisualDiffError.unableToWriteImage
    }
}

private func makeVisualDiff(reference: CGImage, current: CGImage) throws -> VisualDiffResult {
    guard reference.width == current.width, reference.height == current.height else {
        throw VisualDiffError.imageSizeMismatch
    }

    let width = reference.width
    let height = reference.height
    let referencePixels = try rgbaPixels(for: reference)
    let currentPixels = try rgbaPixels(for: current)
    var heatmapPixels = [UInt8](repeating: 0, count: width * height * 4)
    var comparedPixels = 0
    var mismatchedPixels = 0

    for row in 0 ..< height {
        let displayRow = height - 1 - row
        for column in 0 ..< width {
            guard !isMasked(column: column, row: displayRow, width: width, height: height) else { continue }

            comparedPixels += 1
            let offset = (row * width + column) * 4
            let maximumDifference = (0 ..< 3).reduce(0) { difference, channel in
                max(difference, abs(Int(referencePixels[offset + channel]) - Int(currentPixels[offset + channel])))
            }
            guard maximumDifference > 8 else { continue }

            mismatchedPixels += 1
            heatmapPixels[offset] = 255
            heatmapPixels[offset + 3] = 255
        }
    }

    var displayHeatmapPixels = verticallyFlipped(heatmapPixels, width: width, height: height)
    let heatmap = try image(width: width, height: height, pixels: &displayHeatmapPixels)
    let ratio = comparedPixels == 0 ? 0 : Double(mismatchedPixels) / Double(comparedPixels)
    return VisualDiffResult(heatmap: heatmap, mismatchedPixels: mismatchedPixels, ratio: ratio)
}

private func verticallyFlipped(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
    let bytesPerRow = width * 4
    var flipped = [UInt8](repeating: 0, count: pixels.count)
    for sourceRow in 0 ..< height {
        let sourceStart = sourceRow * bytesPerRow
        let destinationStart = (height - 1 - sourceRow) * bytesPerRow
        flipped.replaceSubrange(
            destinationStart ..< destinationStart + bytesPerRow,
            with: pixels[sourceStart ..< sourceStart + bytesPerRow]
        )
    }
    return flipped
}

private func isMasked(column: Int, row: Int, width: Int, height: Int) -> Bool {
    let scale = CGFloat(width) / AnalyticsCardLayout.rootSize.width
    let shellInset = Int(AnalyticsCardLayout.shellInset * scale)
    if column < shellInset || column >= width - shellInset || row < shellInset || row >= height - shellInset {
        return true
    }

    let chart = AnalyticsCardLayout.chartFrame.offsetBy(
        dx: AnalyticsCardLayout.shellInset,
        dy: AnalyticsCardLayout.shellInset
    )
    let scaledChart = CGRect(
        x: chart.minX * scale,
        y: chart.minY * scale,
        width: chart.width * scale,
        height: chart.height * scale
    )
    return scaledChart.contains(CGPoint(x: column, y: row))
}

private func rgbaPixels(for source: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
    try pixels.withUnsafeMutableBytes { buffer in
        guard let context = bitmapContext(width: source.width, height: source.height, data: buffer.baseAddress) else {
            throw VisualDiffError.unableToCreateContext
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.translateBy(x: 0, y: CGFloat(source.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    }
    return pixels
}

private func image(width: Int, height: Int, pixels: inout [UInt8]) throws -> CGImage {
    try pixels.withUnsafeMutableBytes { buffer in
        guard let context = bitmapContext(width: width, height: height, data: buffer.baseAddress),
              let image = context.makeImage()
        else {
            throw VisualDiffError.unableToCreateContext
        }
        return image
    }
}

private func bitmapContext(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext? {
    CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )
}

private enum VisualDiffError: Error {
    case imageSizeMismatch
    case unableToCreateContext
    case unableToCreateDestination
    case unableToWriteImage
}
