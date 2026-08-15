#if CHART_INSPECTOR
    // swiftlint:disable file_length
    import Foundation
    import Testing
    @testable import VercelAnalyticsBar
    import VercelAnalyticsCore

    @MainActor
    @Suite("Chart Inspector protocol")
    struct ChartInspectorProtocolTests {
        @Test func readyHydratesTheWebPanelFromCanonicalNativeState() throws {
            let session = ChartInspectorSession(styleStore: ChartStyleStore())

            let response = try session.receive(readyMessage)

            #expect(session.isReady)
            #expect(response.state.protocolVersion == 6)
            #expect(response.state.revision == 0)
            #expect(response.state.values == .default)
        }

        @Test func styleChangeRequiresHydrationAndANewerRevision() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            let changedStyle = try makeInspectorStyle(lineWidth: 4)
            let styleChange = ChartInspectorIncomingMessage(
                protocolVersion: 6,
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

            let invalidRevision = ChartInspectorIncomingMessage(
                protocolVersion: 6,
                type: .styleChanged,
                source: "chart-inspector",
                revision: ChartInspectorProtocol.maximumRevision + 1,
                values: changedStyle
            )
            #expect(throws: ChartInspectorProtocolError.invalidRevision) {
                try session.receive(invalidRevision)
            }
        }

        @Test func maximumRevisionCannotOverflowDuringReset() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            _ = try session.receive(
                ChartInspectorIncomingMessage(
                    protocolVersion: 6,
                    type: .styleChanged,
                    source: "chart-inspector",
                    revision: ChartInspectorProtocol.maximumRevision,
                    values: .default
                )
            )

            #expect(throws: ChartInspectorProtocolError.invalidRevision) {
                try session.receive(commandMessage(.reset))
            }
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

        @Test func onlyAnimationCommandRequestsPreviewReplay() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            _ = try session.receive(readyMessage)

            let lineWidthResponse = try session.receive(
                ChartInspectorIncomingMessage(
                    protocolVersion: 6,
                    type: .styleChanged,
                    source: "chart-inspector",
                    revision: 1,
                    values: makeInspectorStyle(lineWidth: 4)
                )
            )
            #expect(!lineWidthResponse.replaysAnimation)

            let timingResponse = try session.receive(
                ChartInspectorIncomingMessage(
                    protocolVersion: 6,
                    type: .styleChanged,
                    source: "chart-inspector",
                    revision: 2,
                    values: makeInspectorStyle(lineWidth: 4, lineRevealDuration: 1.4)
                )
            )
            #expect(!timingResponse.replaysAnimation)

            let resetResponse = try session.receive(commandMessage(.reset))
            #expect(!resetResponse.replaysAnimation)

            let revisionBeforeReplay = session.revision
            let replayResponse = try session.receive(commandMessage(.replayAnimation))
            #expect(replayResponse.replaysAnimation)
            #expect(replayResponse.state.revision == revisionBeforeReplay)
            #expect(session.revision == revisionBeforeReplay)
        }

        @Test func protocolIdentityAndBodyValidationRejectUnexpectedMessages() throws {
            let session = ChartInspectorSession(styleStore: ChartStyleStore())

            #expect(throws: ChartInspectorProtocolError.unexpectedProtocolVersion) {
                try session.receive(
                    ChartInspectorIncomingMessage(
                        protocolVersion: 7,
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
                        protocolVersion: 6,
                        type: .ready,
                        source: "unexpected",
                        revision: nil,
                        values: nil
                    )
                )
            }
            #expect(throws: (any Error).self) {
                try session.receive(body: ["protocolVersion": 6, "type": "unknown"])
            }
        }

        @Test func sourceSelectionDefaultsToBundleAndRequiresExplicitDevelopmentMode() throws {
            let bundled = try ChartInspectorSource.resolve(environment: [:], arguments: [])
            guard case .bundled = bundled.kind else {
                Issue.record("Expected bundled Inspector source")
                return
            }
            #expect(!ChartInspectorSource.isInspectorEnabled(environment: [:], arguments: []))

            let bundledInspector = try ChartInspectorSource.resolve(
                environment: [:],
                arguments: [ChartInspectorSource.inspectorArgument]
            )
            guard case .bundled = bundledInspector.kind else {
                Issue.record("Expected an explicitly enabled bundled Inspector source")
                return
            }
            #expect(
                ChartInspectorSource.isInspectorEnabled(
                    environment: [:],
                    arguments: [ChartInspectorSource.inspectorArgument]
                )
            )

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
            #expect(
                ChartInspectorSource.isInspectorEnabled(
                    environment: [:],
                    arguments: [ChartInspectorSource.developmentArgument]
                )
            )
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

            state.replayAnimation()
            #expect(state.animationReplayToken == 1)
        }

        private var readyMessage: ChartInspectorIncomingMessage {
            ChartInspectorIncomingMessage(
                protocolVersion: 6,
                type: .ready,
                source: "chart-inspector",
                revision: nil,
                values: nil
            )
        }

        private func commandMessage(_ type: ChartInspectorIncomingMessageType) -> ChartInspectorIncomingMessage {
            ChartInspectorIncomingMessage(
                protocolVersion: 6,
                type: type,
                source: "chart-inspector",
                revision: nil,
                values: nil
            )
        }
    }

    extension ChartInspectorProtocolTests {
        // swiftlint:disable:next function_body_length
        @Test func everyStyleFieldRoundTripsThroughTheCanonicalNativeBoundary() throws {
            let store = ChartStyleStore()
            let session = ChartInspectorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            let response = try session.receive(body: [
                "protocolVersion": 6,
                "type": "styleChanged",
                "source": "chart-inspector",
                "revision": 4,
                "values": [
                    "lineColor": "#aabbcc",
                    "lineWidth": 6.5,
                    "lineCap": "round",
                    "lineJoin": "bevel",
                    "interpolation": "catmullRom",
                    "areaTopOpacity": 0.6,
                    "areaBottomOpacity": 0.12,
                    "chartIntroAnimationEnabled": true,
                    "lineRevealDuration": 1.2,
                    "lineRevealEasing": "easeInOut",
                    "areaFadeDuration": 0.55,
                    "areaFadeDelay": 0.15,
                    "chartHeight": 220,
                    "chartSidePadding": 24,
                    "chartVerticalPadding": 12,
                    "axisMarkCount": 8,
                    "yScaleHeadroom": 0.25,
                    "showsXAxisLabels": false,
                    "showsYAxisLabels": false,
                    "showsVerticalGridLines": false,
                    "verticalGridLineColor": "#112233",
                    "verticalGridLineOpacity": 0.4,
                    "verticalGridLineWidth": 1.25,
                    "verticalGridLineStyle": "dashed",
                    "showsHorizontalGridLines": true,
                    "horizontalGridLineColor": "#445566",
                    "horizontalGridLineOpacity": 0.7,
                    "horizontalGridLineWidth": 2.5,
                    "horizontalGridLineStyle": "dotted",
                    "showsVerticalAxisTicks": false,
                    "verticalAxisTickColor": "#223344",
                    "verticalAxisTickOpacity": 0.35,
                    "verticalAxisTickWidth": 1.5,
                    "verticalAxisTickLength": 7,
                    "showsHorizontalAxisTicks": true,
                    "horizontalAxisTickColor": "#556677",
                    "horizontalAxisTickOpacity": 0.8,
                    "horizontalAxisTickWidth": 2.25,
                    "horizontalAxisTickLength": 11,
                    "showsChartBorder": true,
                    "chartBorderColor": "#778899",
                    "chartBorderOpacity": 0.65,
                    "chartBorderWidth": 3.25,
                    "chartBorderStyle": "dashed",
                    "chartBorderRadius": 28,
                    "chartBorderDashLength": 12,
                    "chartBorderDashGap": 8,
                    "chartBorderDashPhase": 5,
                    "chartBorderDashCap": "square",
                ],
            ])

            expectDetailedStyle(response.state.values)
            #expect(store.style == response.state.values)
        }

        @Test func previewUsesTheLiveSnapshotSeries() {
            let snapshot = AnalyticsSnapshot.fixture
            let preview = ChartInspectorPreview(analyticsState: .loaded(snapshot))

            #expect(preview.points == snapshot.series)
        }

        @Test func previewUsesSampleDataUntilANonEmptyLiveSeriesIsAvailable() {
            let emptySnapshot = AnalyticsSnapshot(
                projectName: "Empty",
                range: .last7Days,
                visitors: AnalyticsMetric(label: "Visitors", value: 0, previousValue: 0),
                pageViews: AnalyticsMetric(label: "Page Views", value: 0, previousValue: 0),
                series: [],
                last24HoursVisitors: 0,
                refreshedAt: .distantPast
            )

            let loadingPreview = ChartInspectorPreview(analyticsState: .loading)
            let emptyStatePreview = ChartInspectorPreview(analyticsState: .empty("No data"))
            let failedPreview = ChartInspectorPreview(analyticsState: .failed("Unavailable"))
            let emptySeriesPreview = ChartInspectorPreview(analyticsState: .loaded(emptySnapshot))
            let livePreview = ChartInspectorPreview(analyticsState: .loaded(.fixture))

            #expect(loadingPreview.points == ChartInspectorPreview.samplePoints)
            #expect(emptyStatePreview == loadingPreview)
            #expect(failedPreview == loadingPreview)
            #expect(emptySeriesPreview == loadingPreview)
            #expect(livePreview.points == AnalyticsSnapshot.fixture.series)
        }
    }

    private func expectDetailedStyle(_ style: ChartStyle) {
        #expect(style.lineColor.rawValue == "#AABBCC")
        #expect(style.lineWidth == 6.5)
        #expect(style.lineCap == .round)
        #expect(style.lineJoin == .bevel)
        #expect(style.interpolation == .catmullRom)
        #expect(style.areaTopOpacity == 0.6)
        #expect(style.areaBottomOpacity == 0.12)
        #expect(style.chartIntroAnimationEnabled)
        #expect(style.lineRevealDuration == 1.2)
        #expect(style.lineRevealEasing == .easeInOut)
        #expect(style.areaFadeDuration == 0.55)
        #expect(style.areaFadeDelay == 0.15)
        #expect(style.chartHeight == 220)
        #expect(style.chartSidePadding == 24)
        #expect(style.chartVerticalPadding == 12)
        #expect(style.axisMarkCount == 8)
        #expect(style.yScaleHeadroom == 0.25)
        #expect(!style.showsXAxisLabels)
        #expect(!style.showsYAxisLabels)
        #expect(!style.showsVerticalGridLines)
        #expect(style.verticalGridLineColor.rawValue == "#112233")
        #expect(style.verticalGridLineOpacity == 0.4)
        #expect(style.verticalGridLineWidth == 1.25)
        #expect(style.verticalGridLineStyle == .dashed)
        #expect(style.showsHorizontalGridLines)
        #expect(style.horizontalGridLineColor.rawValue == "#445566")
        #expect(style.horizontalGridLineOpacity == 0.7)
        #expect(style.horizontalGridLineWidth == 2.5)
        #expect(style.horizontalGridLineStyle == .dotted)
        #expect(!style.showsVerticalAxisTicks)
        #expect(style.verticalAxisTickColor.rawValue == "#223344")
        #expect(style.verticalAxisTickOpacity == 0.35)
        #expect(style.verticalAxisTickWidth == 1.5)
        #expect(style.verticalAxisTickLength == 7)
        #expect(style.showsHorizontalAxisTicks)
        #expect(style.horizontalAxisTickColor.rawValue == "#556677")
        #expect(style.horizontalAxisTickOpacity == 0.8)
        #expect(style.horizontalAxisTickWidth == 2.25)
        #expect(style.horizontalAxisTickLength == 11)
        #expect(style.showsChartBorder)
        #expect(style.chartBorderColor.rawValue == "#778899")
        #expect(style.chartBorderOpacity == 0.65)
        #expect(style.chartBorderWidth == 3.25)
        #expect(style.chartBorderStyle == .dashed)
        #expect(style.chartBorderRadius == 28)
        #expect(style.chartBorderDashLength == 12)
        #expect(style.chartBorderDashGap == 8)
        #expect(style.chartBorderDashPhase == 5)
        #expect(style.chartBorderDashCap == .square)
    }

    private func makeInspectorStyle(
        lineWidth: Double,
        lineRevealDuration: Double = ChartStyle.default.lineRevealDuration
    ) throws -> ChartStyle {
        let data = try JSONEncoder().encode(ChartStyle.default)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["lineWidth"] = lineWidth
        object["lineRevealDuration"] = lineRevealDuration
        return try JSONDecoder().decode(
            ChartStyle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
#endif
