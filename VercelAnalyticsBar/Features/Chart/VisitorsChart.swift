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
            AxisMarks(values: .automatic(desiredCount: style.axisMarkCount)) { value in
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
                    AxisValueLabel {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                            .font(AppTypography.geistMonoRegular11)
                            .textCase(.uppercase)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: style.axisMarkCount)) { _ in
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
        let maximum = points.map(\.visitors).max() ?? 0
        return max(1, maximum + max(1, Int(Double(maximum) * style.yScaleHeadroom)))
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
