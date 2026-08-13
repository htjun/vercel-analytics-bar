import Charts
import SwiftUI
import VercelAnalyticsCore

struct VisitorsChart: View {
    let points: [VercelAnalyticsPoint]
    let style: ChartStyle

    var body: some View {
        let lineColor = Color(style.lineColor)

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
                if style.showsGridLines {
                    AxisGridLine()
                }
                AxisTick()
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
                if style.showsGridLines {
                    AxisGridLine()
                }
                AxisTick()
                if style.showsYAxisLabels {
                    AxisValueLabel()
                        .font(AppTypography.geistMonoRegular11)
                }
            }
        }
        .chartYScale(domain: 0 ... chartMaximum)
        .padding(.horizontal, 14)
        .frame(height: style.chartHeight)
        .accessibilityLabel("Visitors over time")
    }

    private var chartMaximum: Int {
        let maximum = points.map(\.visitors).max() ?? 0
        return max(1, maximum + max(1, Int(Double(maximum) * style.yScaleHeadroom)))
    }
}

struct VisitorsChartSection: View {
    let points: [VercelAnalyticsPoint]
    let style: ChartStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visitors over time")
                .font(.subheadline.weight(.medium))

            if points.isEmpty {
                Text("No trend data for this period.")
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .foregroundStyle(.secondary)
            } else {
                VisitorsChart(points: points, style: style)
            }
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
