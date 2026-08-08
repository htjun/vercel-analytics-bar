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

        @Test func sourceSelectionDefaultsToBundleAndRequiresExplicitDevelopmentMode() throws {
            let bundled = try ChartInspectorSource.resolve(environment: [:], arguments: [])
            guard case .bundled = bundled.kind else {
                Issue.record("Expected bundled Inspector source")
                return
            }

            let development = try ChartInspectorSource.resolve(
                environment: [ChartInspectorSource.developmentEnvironmentKey: "1"],
                arguments: []
            )
            #expect(development.kind == .developmentServer)
            #expect(development.entryURL == ChartInspectorSource.developmentURL)

            let argumentDevelopment = try ChartInspectorSource.resolve(
                environment: [:],
                arguments: [ChartInspectorSource.developmentArgument]
            )
            #expect(argumentDevelopment.kind == .developmentServer)
        }

        @Test func developmentSourceRequiresTheExactLoopbackOrigin() throws {
            let source = ChartInspectorSource(
                entryURL: ChartInspectorSource.developmentURL,
                kind: .developmentServer
            )
            let allowedURL = try #require(URL(string: "http://127.0.0.1:5173/settings"))
            let localhostURL = try #require(URL(string: "http://localhost:5173/"))
            let wrongPortURL = try #require(URL(string: "http://127.0.0.1:5174/"))

            #expect(source.allowsNavigation(to: allowedURL))
            #expect(!source.allowsNavigation(to: localhostURL))
            #expect(!source.allowsNavigation(to: wrongPortURL))
            #expect(
                source.allowsMessage(
                    frameURL: allowedURL,
                    scheme: "http",
                    host: "127.0.0.1",
                    port: 5173
                )
            )
            #expect(!source.allowsMessage(frameURL: allowedURL, scheme: "https", host: "127.0.0.1", port: 5173))
        }

        @Test func bundledSourceAllowsOnlyFilesInsideItsResourceRoot() {
            let rootURL = URL(fileURLWithPath: "/Applications/Test.app/Contents/Resources/ChartInspector")
            let entryURL = rootURL.appendingPathComponent("index.html")
            let source = ChartInspectorSource(entryURL: entryURL, kind: .bundled(rootURL: rootURL))
            let assetURL = rootURL.appendingPathComponent("assets/index.js")
            let siblingURL = rootURL.deletingLastPathComponent()
                .appendingPathComponent("ChartInspector-copy/index.html")

            #expect(source.allowsNavigation(to: entryURL))
            #expect(source.allowsNavigation(to: assetURL))
            #expect(!source.allowsNavigation(to: siblingURL))
            #expect(!source.allowsNavigation(to: ChartInspectorSource.developmentURL))
            #expect(source.allowsMessage(frameURL: entryURL, scheme: "file", host: "", port: 0))
            #expect(!source.allowsMessage(frameURL: siblingURL, scheme: "file", host: "", port: 0))
        }

        @Test func pageStateOffersARecoverableRetryTransition() {
            let state = ChartInspectorPageState()
            state.fail("Failed")
            #expect(state.phase == .failed("Failed"))

            state.retry()
            #expect(state.phase == .loading)
            #expect(state.reloadToken == 1)
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
