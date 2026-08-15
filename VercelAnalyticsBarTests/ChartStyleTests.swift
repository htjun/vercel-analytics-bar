import Foundation
import SwiftUI
import Testing
@testable import VercelAnalyticsBar

@Suite("Chart style")
struct ChartStyleTests {
    @MainActor
    @Test func xAxisDatesAreEvenlySpacedAcrossTheSeriesRange() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(9 * 86400)
        let dates = VisitorsChart.evenlySpacedDates(from: start, through: end, count: 4)

        #expect(dates.count == 4)
        #expect(dates[0].timeIntervalSince(start) == 1.125 * 86400)
        #expect(dates[1].timeIntervalSince(dates[0]) == 2.25 * 86400)
        #expect(dates[2].timeIntervalSince(dates[1]) == 2.25 * 86400)
        #expect(dates[3].timeIntervalSince(dates[2]) == 2.25 * 86400)
        #expect(end.timeIntervalSince(dates[3]) == 1.125 * 86400)
    }

    @MainActor
    @Test func hourlyXAxisDatesUseEvenlySpacedObservedBuckets() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let dates = (0 ..< 24).map { index in
            start.addingTimeInterval(Double(index) * 3600)
        }

        let marks = VisitorsChart.xAxisDates(for: dates, count: 4)

        #expect(marks == [dates[3], dates[9], dates[15], dates[21]])
        #expect(VisitorsChart.usesHourlyXAxisLabels(from: dates[0], through: dates[23]))
    }

    @MainActor
    @Test func yAxisUsesItsHighestGridLineAsTheScaleMaximum() {
        let marks = VisitorsChart.yAxisValues(
            for: [15, 34, 24, 85, 13],
            desiredCount: 4,
            headroom: 0.1
        )

        #expect(marks == [0, 25, 50, 75, 100])
        #expect(marks.last! > 85)
    }

    @MainActor
    @Test func yAxisHandlesEmptyAndSmallDatasets() {
        #expect(VisitorsChart.yAxisValues(for: [], desiredCount: 4, headroom: 0.1) == [0, 1])
        #expect(VisitorsChart.yAxisValues(for: [1], desiredCount: 4, headroom: 0.1) == [0, 1, 2])
    }

    @Test func defaultsMatchTheCanonicalChartPresentation() {
        let style = ChartStyle.default

        #expect(style.lineColor.rawValue == "#006BFF")
        #expect(style.lineWidth == 1.5)
        #expect(style.lineCap == .round)
        #expect(style.lineJoin == .round)
        #expect(style.interpolation == .monotone)
        #expect(style.areaTopOpacity == 0.2)
        #expect(style.areaBottomOpacity == 0)
        #expect(style.chartHeight == 150)
        #expect(style.chartSidePadding == 12)
        #expect(style.chartVerticalPadding == 5)
        #expect(style.axisMarkCount == 4)
        #expect(style.yScaleHeadroom == 0.1)
        #expect(style.showsXAxisLabels)
        #expect(style.showsYAxisLabels)
        #expect(!style.showsVerticalGridLines)
        #expect(style.verticalGridLineColor.rawValue == "#8E8E93")
        #expect(style.verticalGridLineOpacity == 0.25)
        #expect(style.verticalGridLineWidth == 0.5)
        #expect(style.verticalGridLineStyle == .solid)
        #expect(style.showsHorizontalGridLines)
        #expect(style.horizontalGridLineColor.rawValue == "#8E8E93")
        #expect(style.horizontalGridLineOpacity == 0.25)
        #expect(style.horizontalGridLineWidth == 0.5)
        #expect(style.horizontalGridLineStyle == .solid)
        #expect(!style.showsVerticalAxisTicks)
        #expect(style.verticalAxisTickColor.rawValue == "#8E8E93")
        #expect(style.verticalAxisTickOpacity == 0.5)
        #expect(style.verticalAxisTickWidth == 0.5)
        #expect(style.verticalAxisTickLength == 4)
        #expect(!style.showsHorizontalAxisTicks)
        #expect(style.horizontalAxisTickColor.rawValue == "#8E8E93")
        #expect(style.horizontalAxisTickOpacity == 0.5)
        #expect(style.horizontalAxisTickWidth == 0.5)
        #expect(style.horizontalAxisTickLength == 4)
        #expect(!style.showsChartBorder)
        #expect(style.chartBorderColor.rawValue == "#8E8E93")
        #expect(style.chartBorderOpacity == 0.27)
        #expect(style.chartBorderWidth == 1)
        #expect(style.chartBorderStyle == .dashed)
        #expect(style.chartBorderRadius == 10)
        #expect(style.chartBorderDashLength == 3)
        #expect(style.chartBorderDashGap == 3)
        #expect(style.chartBorderDashPhase == 0)
        #expect(style.chartBorderDashCap == .round)
    }

    @Test func breakdownListDefaultsPreserveTheAnalyticsCardPresentation() {
        let style = BreakdownListStyle.default

        #expect(style.tabSpacing == 12)
        #expect(style.tabTextColor.rawValue == "#262626")
        #expect(style.inactiveTabOpacity == 0.4)
        #expect(style.hoveredTabOpacity == 0.6)
        #expect(style.visibleRowCount == 5)
        #expect(style.headerToRowsSpacing == 16)
        #expect(style.rowHeight == 16)
        #expect(style.rowSpacing == 8)
        #expect(style.columnSpacing == 8)
        #expect(style.countColumnWidth == 40)
        #expect(style.labelFontSize == 12)
        #expect(style.valueFontWeight == .medium)
        #expect(style.introAnimationEnabled)
        #expect(style.introAnimationEasing == .easeOut)
        #expect(style.rowAnimationDuration == 0.22)
        #expect(style.rowAnimationDelay == 0.04)
    }

    @Test func breakdownListValidationKeepsFiveRowsInsideTheCard() throws {
        let encodedDefault = try JSONEncoder().encode(BreakdownListStyle.default)
        var object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["rowHeight"] = 20
        let overflow = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: BreakdownListStyleValidationError.layoutOverflow) {
            try JSONDecoder().decode(BreakdownListStyle.self, from: overflow)
        }
    }

    @MainActor
    @Test func componentStyleStoreKeepsChartAndListStylesIsolated() throws {
        let store = ComponentStyleStore()
        let chart = try makeStyle(lineWidth: 5)
        let list = try makeBreakdownListStyle { style in
            style["visibleRowCount"] = 4
            style["rowHeight"] = 18
            style["headerToRowsSpacing"] = 12
            style["rowSpacing"] = 6
        }

        store.update(.chart(chart))
        store.update(.list(list))

        #expect(store.chartStyle == chart)
        #expect(store.listStyle == list)

        store.reset(.list)
        #expect(store.chartStyle == chart)
        #expect(store.listStyle == .default)
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

    @Test func decodingRejectsUnknownEnums() throws {
        let encodedDefault = try JSONEncoder().encode(ChartStyle.default)
        var object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["lineCap"] = "curved"
        let invalidCap = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidCap)
        }

        object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["lineJoin"] = "curved"
        let invalidJoin = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidJoin)
        }

        object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["interpolation"] = "smooth"
        let invalidInterpolation = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidInterpolation)
        }

        object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["verticalGridLineStyle"] = "longDash"
        let invalidGridLineStyle = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidGridLineStyle)
        }

        object = try #require(JSONSerialization.jsonObject(with: encodedDefault) as? [String: Any])
        object["chartBorderStyle"] = "dotted"
        let invalidBorderStyle = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartStyle.self, from: invalidBorderStyle)
        }
    }

    @Test func borderStrokeStyleUsesDashDetailsOnlyForDashedBorders() {
        let solid = ChartBorderStyle.solid.strokeStyle(
            lineWidth: 2.5,
            dashLength: 12,
            dashGap: 8,
            dashPhase: 5,
            dashCap: .round
        )
        #expect(solid.lineWidth == 2.5)
        #expect(solid.lineCap == .butt)
        #expect(solid.dash.isEmpty)
        #expect(solid.dashPhase == 0)

        let dashed = ChartBorderStyle.dashed.strokeStyle(
            lineWidth: 3.25,
            dashLength: 12,
            dashGap: 8,
            dashPhase: 5,
            dashCap: .square
        )
        #expect(dashed.lineWidth == 3.25)
        #expect(dashed.lineCap == .square)
        #expect(dashed.dash == [12, 8])
        #expect(dashed.dashPhase == 5)
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
            { try makeStyle(chartSidePadding: -0.01) },
            { try makeStyle(chartSidePadding: 64.01) },
            { try makeStyle(chartVerticalPadding: -0.01) },
            { try makeStyle(chartVerticalPadding: 64.01) },
            { try makeStyle(axisMarkCount: 1) },
            { try makeStyle(axisMarkCount: 13) },
            { try makeStyle(yScaleHeadroom: -0.01) },
            { try makeStyle(yScaleHeadroom: .infinity) },
            { try makeStyle(verticalGridLineOpacity: -0.01) },
            { try makeStyle(verticalGridLineOpacity: 1.01) },
            { try makeStyle(verticalGridLineWidth: 0.24) },
            { try makeStyle(verticalGridLineWidth: 4.01) },
            { try makeStyle(horizontalGridLineOpacity: -0.01) },
            { try makeStyle(horizontalGridLineOpacity: 1.01) },
            { try makeStyle(horizontalGridLineWidth: 0.24) },
            { try makeStyle(horizontalGridLineWidth: 4.01) },
            { try makeStyle(verticalAxisTickOpacity: -0.01) },
            { try makeStyle(verticalAxisTickOpacity: 1.01) },
            { try makeStyle(verticalAxisTickWidth: 0.24) },
            { try makeStyle(verticalAxisTickWidth: 4.01) },
            { try makeStyle(verticalAxisTickLength: 0.99) },
            { try makeStyle(verticalAxisTickLength: 16.01) },
            { try makeStyle(horizontalAxisTickOpacity: -0.01) },
            { try makeStyle(horizontalAxisTickOpacity: 1.01) },
            { try makeStyle(horizontalAxisTickWidth: 0.24) },
            { try makeStyle(horizontalAxisTickWidth: 4.01) },
            { try makeStyle(horizontalAxisTickLength: 0.99) },
            { try makeStyle(horizontalAxisTickLength: 16.01) },
            { try makeStyle(chartBorderOpacity: -0.01) },
            { try makeStyle(chartBorderOpacity: 1.01) },
            { try makeStyle(chartBorderWidth: 0.24) },
            { try makeStyle(chartBorderWidth: 8.01) },
            { try makeStyle(chartBorderRadius: -0.01) },
            { try makeStyle(chartBorderRadius: 64.01) },
            { try makeStyle(chartBorderDashLength: 0.99) },
            { try makeStyle(chartBorderDashLength: 32.01) },
            { try makeStyle(chartBorderDashGap: 0.99) },
            { try makeStyle(chartBorderDashGap: 32.01) },
            { try makeStyle(chartBorderDashPhase: -0.01) },
            { try makeStyle(chartBorderDashPhase: 64.01) },
        ]
    }
}

// swiftlint:disable:next function_body_length
private func makeStyle(
    lineColor: ChartColor = .accent,
    lineWidth: Double = 2,
    lineCap: ChartLineCap = .butt,
    lineJoin: ChartLineJoin = .miter,
    interpolation: ChartInterpolation = .linear,
    areaTopOpacity: Double = 0.24,
    areaBottomOpacity: Double = 0.03,
    chartHeight: Double = 140,
    chartSidePadding: Double = 14,
    chartVerticalPadding: Double = 0,
    axisMarkCount: Int = 4,
    yScaleHeadroom: Double = 0.1,
    showsXAxisLabels: Bool = true,
    showsYAxisLabels: Bool = true,
    showsVerticalGridLines: Bool = true,
    verticalGridLineColor: ChartColor = .rgb(red: 142, green: 142, blue: 147),
    verticalGridLineOpacity: Double = 0.25,
    verticalGridLineWidth: Double = 0.5,
    verticalGridLineStyle: ChartGridLineStyle = .solid,
    showsHorizontalGridLines: Bool = true,
    horizontalGridLineColor: ChartColor = .rgb(red: 142, green: 142, blue: 147),
    horizontalGridLineOpacity: Double = 0.25,
    horizontalGridLineWidth: Double = 0.5,
    horizontalGridLineStyle: ChartGridLineStyle = .solid,
    showsVerticalAxisTicks: Bool = true,
    verticalAxisTickColor: ChartColor = .rgb(red: 142, green: 142, blue: 147),
    verticalAxisTickOpacity: Double = 0.5,
    verticalAxisTickWidth: Double = 0.5,
    verticalAxisTickLength: Double = 4,
    showsHorizontalAxisTicks: Bool = true,
    horizontalAxisTickColor: ChartColor = .rgb(red: 142, green: 142, blue: 147),
    horizontalAxisTickOpacity: Double = 0.5,
    horizontalAxisTickWidth: Double = 0.5,
    horizontalAxisTickLength: Double = 4,
    showsChartBorder: Bool = false,
    chartBorderColor: ChartColor = .rgb(red: 142, green: 142, blue: 147),
    chartBorderOpacity: Double = 0.5,
    chartBorderWidth: Double = 1,
    chartBorderStyle: ChartBorderStyle = .solid,
    chartBorderRadius: Double = 16,
    chartBorderDashLength: Double = 6,
    chartBorderDashGap: Double = 4,
    chartBorderDashPhase: Double = 0,
    chartBorderDashCap: ChartLineCap = .round
) throws -> ChartStyle {
    try ChartStyle(
        lineColor: lineColor,
        lineWidth: lineWidth,
        lineCap: lineCap,
        lineJoin: lineJoin,
        interpolation: interpolation,
        areaTopOpacity: areaTopOpacity,
        areaBottomOpacity: areaBottomOpacity,
        chartIntroAnimationEnabled: true,
        lineRevealDuration: 0.8,
        lineRevealEasing: .easeOut,
        areaFadeDuration: 0.3,
        areaFadeDelay: 0.05,
        chartHeight: chartHeight,
        chartSidePadding: chartSidePadding,
        chartVerticalPadding: chartVerticalPadding,
        axisMarkCount: axisMarkCount,
        yScaleHeadroom: yScaleHeadroom,
        showsXAxisLabels: showsXAxisLabels,
        showsYAxisLabels: showsYAxisLabels,
        showsVerticalGridLines: showsVerticalGridLines,
        verticalGridLineColor: verticalGridLineColor,
        verticalGridLineOpacity: verticalGridLineOpacity,
        verticalGridLineWidth: verticalGridLineWidth,
        verticalGridLineStyle: verticalGridLineStyle,
        showsHorizontalGridLines: showsHorizontalGridLines,
        horizontalGridLineColor: horizontalGridLineColor,
        horizontalGridLineOpacity: horizontalGridLineOpacity,
        horizontalGridLineWidth: horizontalGridLineWidth,
        horizontalGridLineStyle: horizontalGridLineStyle,
        showsVerticalAxisTicks: showsVerticalAxisTicks,
        verticalAxisTickColor: verticalAxisTickColor,
        verticalAxisTickOpacity: verticalAxisTickOpacity,
        verticalAxisTickWidth: verticalAxisTickWidth,
        verticalAxisTickLength: verticalAxisTickLength,
        showsHorizontalAxisTicks: showsHorizontalAxisTicks,
        horizontalAxisTickColor: horizontalAxisTickColor,
        horizontalAxisTickOpacity: horizontalAxisTickOpacity,
        horizontalAxisTickWidth: horizontalAxisTickWidth,
        horizontalAxisTickLength: horizontalAxisTickLength,
        showsChartBorder: showsChartBorder,
        chartBorderColor: chartBorderColor,
        chartBorderOpacity: chartBorderOpacity,
        chartBorderWidth: chartBorderWidth,
        chartBorderStyle: chartBorderStyle,
        chartBorderRadius: chartBorderRadius,
        chartBorderDashLength: chartBorderDashLength,
        chartBorderDashGap: chartBorderDashGap,
        chartBorderDashPhase: chartBorderDashPhase,
        chartBorderDashCap: chartBorderDashCap
    )
}

private func makeBreakdownListStyle(
    _ update: (inout [String: Any]) -> Void
) throws -> BreakdownListStyle {
    let data = try JSONEncoder().encode(BreakdownListStyle.default)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    update(&object)
    return try JSONDecoder().decode(
        BreakdownListStyle.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
}
