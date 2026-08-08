#if CHART_INSPECTOR
    import Foundation
    import Testing
    @testable import VercelAnalyticsBar

    @MainActor
    @Suite("Chart Inspector protocol")
    struct ChartInspectorProtocolTests {
        @Test func readyHydratesTheWebPanelFromCanonicalNativeState() throws {
            let session = ChartInspectorSession(styleStore: ChartStyleStore())

            let state = try session.receive(readyMessage)

            #expect(session.isReady)
            #expect(state.protocolVersion == 1)
            #expect(state.revision == 0)
            #expect(state.values == .default)
        }

        @Test func styleChangeRequiresHydrationAndANewerRevision() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            let changedStyle = try makeInspectorStyle(lineWidth: 4)
            let styleChange = ChartInspectorIncomingMessage(
                protocolVersion: 1,
                type: .styleChanged,
                source: "chart-inspector",
                revision: 1,
                values: changedStyle
            )

            #expect(throws: ChartInspectorProtocolError.notReady) {
                try session.receive(styleChange)
            }

            _ = try session.receive(readyMessage)
            let state = try session.receive(styleChange)
            #expect(store.style == changedStyle)
            #expect(state.revision == 1)

            #expect(throws: ChartInspectorProtocolError.staleRevision) {
                try session.receive(styleChange)
            }
        }

        @Test func protocolIdentityAndBodyValidationRejectUnexpectedMessages() throws {
            let session = ChartInspectorSession(styleStore: ChartStyleStore())

            #expect(throws: ChartInspectorProtocolError.unexpectedProtocolVersion) {
                try session.receive(
                    ChartInspectorIncomingMessage(
                        protocolVersion: 2,
                        type: .ready,
                        source: "chart-inspector",
                        revision: nil,
                        values: nil
                    )
                )
            }
            #expect(throws: ChartInspectorProtocolError.unexpectedSource) {
                try session.receive(
                    ChartInspectorIncomingMessage(
                        protocolVersion: 1,
                        type: .ready,
                        source: "unexpected",
                        revision: nil,
                        values: nil
                    )
                )
            }
            #expect(throws: (any Error).self) {
                try session.receive(body: ["protocolVersion": 1, "type": "unknown"])
            }
        }

        @Test func developmentLocationRequiresTheExactLoopbackOrigin() {
            #expect(ChartInspectorLocation.allows(scheme: "http", host: "127.0.0.1", port: 5173))
            #expect(!ChartInspectorLocation.allows(scheme: "http", host: "localhost", port: 5173))
            #expect(!ChartInspectorLocation.allows(scheme: "https", host: "127.0.0.1", port: 5173))
            #expect(!ChartInspectorLocation.allows(scheme: "http", host: "127.0.0.1", port: 5174))
        }

        private var readyMessage: ChartInspectorIncomingMessage {
            ChartInspectorIncomingMessage(
                protocolVersion: 1,
                type: .ready,
                source: "chart-inspector",
                revision: nil,
                values: nil
            )
        }
    }

    private func makeInspectorStyle(lineWidth: Double) throws -> ChartStyle {
        let style = ChartStyle.default
        return try ChartStyle(
            lineColor: style.lineColor,
            lineWidth: lineWidth,
            lineCap: style.lineCap,
            lineJoin: style.lineJoin,
            areaTopOpacity: style.areaTopOpacity,
            areaBottomOpacity: style.areaBottomOpacity,
            chartHeight: style.chartHeight,
            axisMarkCount: style.axisMarkCount,
            yScaleHeadroom: style.yScaleHeadroom,
            showsGridLines: style.showsGridLines,
            showsXAxisLabels: style.showsXAxisLabels,
            showsYAxisLabels: style.showsYAxisLabels
        )
    }
#endif
