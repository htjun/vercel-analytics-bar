#if CHART_INSPECTOR
    import Foundation
    import Testing
    @testable import VercelAnalyticsBar

    @MainActor
    @Suite("Chart Inspector protocol")
    struct ChartInspectorProtocolTests {
        @Test func readyHydratesTheWebPanelFromCanonicalNativeState() throws {
            let session = ChartInspectorSession(styleStore: ChartStyleStore())

            let response = try session.receive(readyMessage)

            #expect(session.isReady)
            #expect(response.state.protocolVersion == 1)
            #expect(response.state.revision == 0)
            #expect(response.state.values == .default)
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
            let state = try session.receive(styleChange).state
            #expect(store.style == changedStyle)
            #expect(state.revision == 1)

            #expect(throws: ChartInspectorProtocolError.staleRevision) {
                try session.receive(styleChange)
            }
        }

        @Test func everyStyleFieldRoundTripsThroughTheCanonicalNativeBoundary() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            let response = try session.receive(body: [
                "protocolVersion": 1,
                "type": "styleChanged",
                "source": "chart-inspector",
                "revision": 4,
                "values": [
                    "lineColor": "#aabbcc",
                    "lineWidth": 6.5,
                    "lineCap": "round",
                    "lineJoin": "bevel",
                    "areaTopOpacity": 0.6,
                    "areaBottomOpacity": 0.12,
                    "chartHeight": 220,
                    "axisMarkCount": 8,
                    "yScaleHeadroom": 0.25,
                    "showsGridLines": false,
                    "showsXAxisLabels": false,
                    "showsYAxisLabels": false,
                ],
            ])

            #expect(response.state.values.lineColor.rawValue == "#AABBCC")
            #expect(response.state.values.lineWidth == 6.5)
            #expect(response.state.values.lineCap == .round)
            #expect(response.state.values.lineJoin == .bevel)
            #expect(response.state.values.areaTopOpacity == 0.6)
            #expect(response.state.values.areaBottomOpacity == 0.12)
            #expect(response.state.values.chartHeight == 220)
            #expect(response.state.values.axisMarkCount == 8)
            #expect(response.state.values.yScaleHeadroom == 0.25)
            #expect(!response.state.values.showsGridLines)
            #expect(!response.state.values.showsXAxisLabels)
            #expect(!response.state.values.showsYAxisLabels)
            #expect(store.style == response.state.values)
        }

        @Test func resetCopyAndRehydrationUseCanonicalNativeState() throws {
            let store = try ChartStyleStore(style: makeInspectorStyle(lineWidth: 5))
            let session = ChartInspectorSession(styleStore: store)
            _ = try session.receive(readyMessage)

            let copiedResponse = try session.receive(commandMessage(.copyStyle))
            let copiedJSON = try #require(copiedResponse.copiedStyleJSON)
            let copiedStyle = try JSONDecoder().decode(ChartStyle.self, from: Data(copiedJSON.utf8))
            #expect(copiedStyle == store.style)

            let resetResponse = try session.receive(commandMessage(.reset))
            #expect(store.style == .default)
            #expect(resetResponse.state.values == .default)
            #expect(resetResponse.state.revision == 1)

            let reopenedSession = ChartInspectorSession(styleStore: store)
            let reopenedState = try reopenedSession.receive(readyMessage).state
            #expect(reopenedState.values == .default)
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

        private func commandMessage(_ type: ChartInspectorIncomingMessageType) -> ChartInspectorIncomingMessage {
            ChartInspectorIncomingMessage(
                protocolVersion: 1,
                type: type,
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
