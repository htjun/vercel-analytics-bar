import Foundation
import Testing
@testable import VercelAnalyticsBar

@Suite("Chart style")
struct ChartStyleTests {
    @Test func defaultsPreserveTheExistingChartPresentation() {
        let style = ChartStyle.default

        #expect(style.lineColor == .accent)
        #expect(style.lineWidth == 2)
        #expect(style.lineCap == .butt)
        #expect(style.lineJoin == .miter)
        #expect(style.areaTopOpacity == 0.24)
        #expect(style.areaBottomOpacity == 0.03)
        #expect(style.chartHeight == 140)
        #expect(style.axisMarkCount == 4)
        #expect(style.yScaleHeadroom == 0.1)
        #expect(style.showsGridLines)
        #expect(style.showsXAxisLabels)
        #expect(style.showsYAxisLabels)
    }

    @Test func colorAcceptsAccentAndCanonicalizesHexadecimalRGB() throws {
        #expect(ChartColor(rawValue: "accent") == .accent)
        #expect(ChartColor(rawValue: "#0a7fF0")?.rawValue == "#0A7FF0")
        #expect(ChartColor(rawValue: "blue") == nil)
        #expect(ChartColor(rawValue: "#12345") == nil)

        let decoded = try JSONDecoder().decode(ChartColor.self, from: Data("\"#0a7fF0\"".utf8))
        #expect(decoded.rawValue == "#0A7FF0")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartColor.self, from: Data("\"invalid\"".utf8))
        }
    }

    @Test func styleRejectsEveryInvalidNumericBoundary() {
        for mutation in invalidMutations {
            #expect(throws: ChartStyleValidationError.self) {
                try mutation()
            }
        }
    }

    @Test func decodingUsesTheSameValidationBoundary() throws {
        let encodedDefault = try JSONEncoder().encode(ChartStyle.default)
        var object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["lineWidth"] = 100
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: ChartStyleValidationError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidData)
        }

        let roundTrip = try JSONDecoder().decode(ChartStyle.self, from: encodedDefault)
        #expect(roundTrip == .default)
    }

    @MainActor
    @Test func storePublishesValidatedStyleWithoutTouchingApplicationState() throws {
        let accountStore = InMemoryAccountDataStore()
        let snapshotStore = InMemorySnapshotCacheStore()
        let appModel = AppModel(
            accountDataStore: accountStore,
            snapshotCacheStore: snapshotStore,
            launchAtLoginManager: InMemoryLaunchAtLoginManager()
        )
        let originalAppState = appModel.state
        let originalAccountState = appModel.accountState
        let originalProjectState = appModel.projectState
        let originalSelectedRange = appModel.selectedRange
        let styleStore = ChartStyleStore()
        let updatedStyle = try makeStyle(lineWidth: 5)

        styleStore.update(updatedStyle)

        #expect(styleStore.style == updatedStyle)
        #expect(appModel.state == originalAppState)
        #expect(appModel.accountState == originalAccountState)
        #expect(appModel.projectState == originalProjectState)
        #expect(appModel.selectedRange == originalSelectedRange)
        #expect(accountStore.analyticsRange == .last7Days)
        #expect(snapshotStore.entries.isEmpty)

        styleStore.reset()
        #expect(styleStore.style == .default)
    }

    private var invalidMutations: [() throws -> ChartStyle] {
        [
            { try makeStyle(lineWidth: .nan) },
            { try makeStyle(lineWidth: 0.49) },
            { try makeStyle(lineWidth: 12.01) },
            { try makeStyle(areaTopOpacity: -0.01) },
            { try makeStyle(areaBottomOpacity: 1.01) },
            { try makeStyle(chartHeight: 79) },
            { try makeStyle(chartHeight: 361) },
            { try makeStyle(axisMarkCount: 1) },
            { try makeStyle(axisMarkCount: 13) },
            { try makeStyle(yScaleHeadroom: -0.01) },
            { try makeStyle(yScaleHeadroom: .infinity) },
        ]
    }
}

private func makeStyle(
    lineColor: ChartColor = .accent,
    lineWidth: Double = 2,
    lineCap: ChartLineCap = .butt,
    lineJoin: ChartLineJoin = .miter,
    areaTopOpacity: Double = 0.24,
    areaBottomOpacity: Double = 0.03,
    chartHeight: Double = 140,
    axisMarkCount: Int = 4,
    yScaleHeadroom: Double = 0.1,
    showsGridLines: Bool = true,
    showsXAxisLabels: Bool = true,
    showsYAxisLabels: Bool = true
) throws -> ChartStyle {
    try ChartStyle(
        lineColor: lineColor,
        lineWidth: lineWidth,
        lineCap: lineCap,
        lineJoin: lineJoin,
        areaTopOpacity: areaTopOpacity,
        areaBottomOpacity: areaBottomOpacity,
        chartHeight: chartHeight,
        axisMarkCount: axisMarkCount,
        yScaleHeadroom: yScaleHeadroom,
        showsGridLines: showsGridLines,
        showsXAxisLabels: showsXAxisLabels,
        showsYAxisLabels: showsYAxisLabels
    )
}
