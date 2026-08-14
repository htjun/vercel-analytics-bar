import Charts
import SwiftUI
import VercelAnalyticsCore

struct VisitorsChart: View {
    let points: [VercelAnalyticsPoint]
    let style: ChartStyle

    var body: some View {
        let lineColor = Color(style.lineColor)
        let containerShape = RoundedRectangle(
            cornerRadius: style.chartBorderRadius,
            style: .continuous
        )

        Chart(points, id: \.timestamp) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Visitors", point.visitors)
            )
            .interpolationMethod(style.interpolation.chartInterpolationMethod)
            .foregroundStyle(
                .linearGradient(
                    colors: [
                        lineColor.opacity(style.areaTopOpacity),
                        lineColor.opacity(style.areaBottomOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Visitors", point.visitors)
            )
            .interpolationMethod(style.interpolation.chartInterpolationMethod)
            .foregroundStyle(lineColor)
            .lineStyle(
                StrokeStyle(
                    lineWidth: style.lineWidth,
                    lineCap: style.lineCap.cgLineCap,
                    lineJoin: style.lineJoin.cgLineJoin
                )
            )
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                if style.showsVerticalGridLines {
                    AxisGridLine(
                        stroke: style.verticalGridLineStyle.strokeStyle(
                            lineWidth: style.verticalGridLineWidth
                        )
                    )
                    .foregroundStyle(
                        Color(style.verticalGridLineColor)
                            .opacity(style.verticalGridLineOpacity)
                    )
                }
                if style.showsVerticalAxisTicks {
                    AxisTick(
                        length: style.verticalAxisTickLength,
                        stroke: StrokeStyle(lineWidth: style.verticalAxisTickWidth)
                    )
                    .foregroundStyle(
                        Color(style.verticalAxisTickColor)
                            .opacity(style.verticalAxisTickOpacity)
                    )
                }
                if style.showsXAxisLabels, let date = value.as(Date.self) {
                    AxisValueLabel(collisionResolution: .disabled) {
                        if usesHourlyXAxisLabels {
                            Text(date, format: .dateTime.hour())
                                .font(AppTypography.geistMonoRegular11)
                                .textCase(.uppercase)
                        } else {
                            Text(date, format: .dateTime.day().month(.abbreviated))
                                .font(AppTypography.geistMonoRegular11)
                                .textCase(.uppercase)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { _ in
                if style.showsHorizontalGridLines {
                    AxisGridLine(
                        stroke: style.horizontalGridLineStyle.strokeStyle(
                            lineWidth: style.horizontalGridLineWidth
                        )
                    )
                    .foregroundStyle(
                        Color(style.horizontalGridLineColor)
                            .opacity(style.horizontalGridLineOpacity)
                    )
                }
                if style.showsHorizontalAxisTicks {
                    AxisTick(
                        length: style.horizontalAxisTickLength,
                        stroke: StrokeStyle(lineWidth: style.horizontalAxisTickWidth)
                    )
                    .foregroundStyle(
                        Color(style.horizontalAxisTickColor)
                            .opacity(style.horizontalAxisTickOpacity)
                    )
                }
                if style.showsYAxisLabels {
                    AxisValueLabel()
                        .font(AppTypography.geistMonoRegular11)
                }
            }
        }
        .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
        .chartYScale(domain: 0 ... chartMaximum)
        .padding(.horizontal, style.chartSidePadding)
        .padding(.vertical, style.chartVerticalPadding)
        .frame(height: style.chartHeight)
        .clipShape(containerShape)
        .overlay {
            if style.showsChartBorder {
                containerShape
                    .strokeBorder(
                        Color(style.chartBorderColor)
                            .opacity(style.chartBorderOpacity),
                        style: style.chartBorderStyle.strokeStyle(
                            lineWidth: style.chartBorderWidth,
                            dashLength: style.chartBorderDashLength,
                            dashGap: style.chartBorderDashGap,
                            dashPhase: style.chartBorderDashPhase,
                            dashCap: style.chartBorderDashCap
                        )
                    )
            }
        }
        .accessibilityLabel("Visitors over time")
    }

    private var chartMaximum: Int {
        yAxisValues.last ?? 1
    }

    private var yAxisValues: [Int] {
        Self.yAxisValues(
            for: points.map(\.visitors),
            desiredCount: style.axisMarkCount,
            headroom: style.yScaleHeadroom
        )
    }

    private var xAxisValues: [Date] {
        Self.xAxisDates(
            for: points.map(\.timestamp),
            count: style.axisMarkCount
        )
    }

    private var usesHourlyXAxisLabels: Bool {
        guard let start = points.map(\.timestamp).min(),
              let end = points.map(\.timestamp).max()
        else {
            return false
        }

        return Self.usesHourlyXAxisLabels(from: start, through: end)
    }

    static func xAxisDates(for dates: [Date], count: Int) -> [Date] {
        let sortedDates = dates.sorted()
        guard let start = sortedDates.first,
              let end = sortedDates.last,
              count > 0
        else {
            return []
        }

        guard usesHourlyXAxisLabels(from: start, through: end) else {
            return evenlySpacedDates(from: start, through: end, count: count)
        }

        let markCount = min(count, sortedDates.count)
        return (0 ..< markCount).map { index in
            let position = (Double(index) + 0.5) * Double(sortedDates.count) / Double(markCount)
            return sortedDates[min(sortedDates.count - 1, Int(position.rounded(.down)))]
        }
    }

    static func usesHourlyXAxisLabels(from start: Date, through end: Date) -> Bool {
        end.timeIntervalSince(start) <= 36 * 60 * 60
    }

    static func yAxisValues(
        for values: [Int],
        desiredCount: Int,
        headroom: Double
    ) -> [Int] {
        let dataMaximum = max(0, values.max() ?? 0)
        let paddedMaximum = max(
            1,
            dataMaximum + max(1, Int(Double(dataMaximum) * headroom))
        )
        let roughStep = Double(paddedMaximum) / Double(max(1, desiredCount))
        let step = niceYAxisStep(for: roughStep)
        let axisMaximum = Int(ceil(Double(paddedMaximum) / Double(step))) * step

        return Array(stride(from: 0, through: axisMaximum, by: step))
    }

    private static func niceYAxisStep(for roughStep: Double) -> Int {
        guard roughStep > 0 else { return 1 }

        let magnitude = pow(10, floor(log10(roughStep)))
        let normalizedStep = roughStep / magnitude
        let niceNormalizedStep: Double = switch normalizedStep {
        case ...1.5:
            1
        case ...2.25:
            2
        case ...3.75:
            2.5
        case ...7.5:
            5
        default:
            10
        }

        return max(1, Int((niceNormalizedStep * magnitude).rounded()))
    }

    static func evenlySpacedDates(from start: Date, through end: Date, count: Int) -> [Date] {
        guard count > 1, end > start else { return [start] }

        let interval = end.timeIntervalSince(start) / Double(count)
        return (0 ..< count).map { index in
            start.addingTimeInterval((Double(index) + 0.5) * interval)
        }
    }
}

private extension Color {
    init(_ chartColor: ChartColor) {
        switch chartColor {
        case .accent:
            self = .accentColor
        case let .rgb(red, green, blue):
            self.init(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            )
        }
    }
}

private extension ChartLineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt: .butt
        case .round: .round
        case .square: .square
        }
    }
}

private extension ChartLineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: .miter
        case .round: .round
        case .bevel: .bevel
        }
    }
}

private extension ChartInterpolation {
    var chartInterpolationMethod: InterpolationMethod {
        switch self {
        case .linear: .linear
        case .monotone: .monotone
        case .cardinal: .cardinal
        case .catmullRom: .catmullRom
        }
    }
}

private extension ChartGridLineStyle {
    func strokeStyle(lineWidth: Double) -> StrokeStyle {
        switch self {
        case .solid:
            StrokeStyle(lineWidth: lineWidth)
        case .dashed:
            StrokeStyle(lineWidth: lineWidth, dash: [6, 4])
        case .dotted:
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [1, 3])
        }
    }
}

extension ChartBorderStyle {
    func strokeStyle(
        lineWidth: Double,
        dashLength: Double,
        dashGap: Double,
        dashPhase: Double,
        dashCap: ChartLineCap
    ) -> StrokeStyle {
        switch self {
        case .solid:
            StrokeStyle(lineWidth: lineWidth)
        case .dashed:
            StrokeStyle(
                lineWidth: lineWidth,
                lineCap: dashCap.cgLineCap,
                dash: [dashLength, dashGap],
                dashPhase: dashPhase
            )
        }
    }
}
