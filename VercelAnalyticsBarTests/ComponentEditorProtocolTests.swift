#if COMPONENT_EDITOR
    // swiftlint:disable file_length
    import Foundation
    import Testing
    @testable import VercelAnalyticsBar
    import VercelAnalyticsCore

    // swiftlint:disable type_body_length
    @MainActor
    @Suite("Component Editor protocol")
    struct ComponentEditorProtocolTests {
        @Test func readyHydratesTheWebPanelFromCanonicalNativeState() throws {
            let session = ComponentEditorSession(styleStore: ComponentStyleStore())

            let response = try session.receive(readyMessage)

            #expect(session.isReady)
            #expect(response.state.protocolVersion == 7)
            #expect(response.state.revision == 0)
            #expect(response.state.values == .chart(.default))
        }

        @Test func styleChangeRequiresHydrationAndANewerRevision() throws {
            let store = ComponentStyleStore()
            let session = ComponentEditorSession(styleStore: store)
            let changedStyle = try makeEditorStyle(lineWidth: 4)
            let styleChange = ComponentEditorIncomingMessage(
                protocolVersion: 7,
                type: .styleChanged,
                source: "component-editor",
                revision: 1,
                values: changedStyle
            )

            #expect(throws: ComponentEditorProtocolError.notReady) {
                try session.receive(styleChange)
            }

            _ = try session.receive(readyMessage)
            let state = try session.receive(styleChange).state
            #expect(store.chartStyle == changedStyle)
            #expect(state.revision == 1)

            #expect(throws: ComponentEditorProtocolError.staleRevision) {
                try session.receive(styleChange)
            }

            let invalidRevision = ComponentEditorIncomingMessage(
                protocolVersion: 7,
                type: .styleChanged,
                source: "component-editor",
                revision: ComponentEditorProtocol.maximumRevision + 1,
                values: changedStyle
            )
            #expect(throws: ComponentEditorProtocolError.invalidRevision) {
                try session.receive(invalidRevision)
            }
        }

        @Test func maximumRevisionCannotOverflowDuringReset() throws {
            let store = ComponentStyleStore()
            let session = ComponentEditorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            _ = try session.receive(
                ComponentEditorIncomingMessage(
                    protocolVersion: 7,
                    type: .styleChanged,
                    source: "component-editor",
                    revision: ComponentEditorProtocol.maximumRevision,
                    values: .default
                )
            )

            #expect(throws: ComponentEditorProtocolError.invalidRevision) {
                try session.receive(commandMessage(.reset))
            }
        }

        @Test func resetCopyAndRehydrationUseCanonicalNativeState() throws {
            let store = try ComponentStyleStore(chartStyle: makeEditorStyle(lineWidth: 5))
            let session = ComponentEditorSession(styleStore: store)
            _ = try session.receive(readyMessage)

            let copiedResponse = try session.receive(commandMessage(.copyStyle))
            let copiedJSON = try #require(copiedResponse.copiedStyleJSON)
            let copiedStyle = try JSONDecoder().decode(ChartStyle.self, from: Data(copiedJSON.utf8))
            #expect(copiedStyle == store.chartStyle)

            let resetResponse = try session.receive(commandMessage(.reset))
            #expect(store.chartStyle == .default)
            #expect(resetResponse.state.values == .chart(.default))
            #expect(resetResponse.state.revision == 1)

            let reopenedSession = ComponentEditorSession(styleStore: store)
            let reopenedState = try reopenedSession.receive(readyMessage).state
            #expect(reopenedState.values == .chart(.default))
        }

        @Test func onlyAnimationCommandRequestsPreviewReplay() throws {
            let store = ComponentStyleStore()
            let session = ComponentEditorSession(styleStore: store)
            _ = try session.receive(readyMessage)

            let lineWidthResponse = try session.receive(
                ComponentEditorIncomingMessage(
                    protocolVersion: 7,
                    type: .styleChanged,
                    source: "component-editor",
                    revision: 1,
                    values: makeEditorStyle(lineWidth: 4)
                )
            )
            #expect(lineWidthResponse.replayedComponent == nil)

            let timingResponse = try session.receive(
                ComponentEditorIncomingMessage(
                    protocolVersion: 7,
                    type: .styleChanged,
                    source: "component-editor",
                    revision: 2,
                    values: makeEditorStyle(lineWidth: 4, lineRevealDuration: 1.4)
                )
            )
            #expect(timingResponse.replayedComponent == nil)

            let resetResponse = try session.receive(commandMessage(.reset))
            #expect(resetResponse.replayedComponent == nil)

            let revisionBeforeReplay = session.revision
            let replayResponse = try session.receive(commandMessage(.replayAnimation))
            #expect(replayResponse.replayedComponent == .chart)
            #expect(replayResponse.state.revision == revisionBeforeReplay)
            #expect(session.revision == revisionBeforeReplay)
        }

        @Test func nativeComponentSelectionRehydratesAtTheCurrentRevision() throws {
            let session = ComponentEditorSession(styleStore: ComponentStyleStore())
            _ = try session.receive(readyMessage)

            let chartState = session.stateMessage
            session.select(.list)
            let listState = session.stateMessage

            #expect(chartState.component == .chart)
            #expect(listState.component == .list)
            #expect(chartState.revision == listState.revision)
            #expect(listState.values == .list(.default))
        }

        @Test func componentEditorUsesThePlannedWindowTitleAndSizes() {
            #expect(ComponentEditorWindowConfiguration.title == "Component Editor")
            #expect(ComponentEditorWindowConfiguration.defaultContentSize == CGSize(width: 1000, height: 700))
            #expect(ComponentEditorWindowConfiguration.minimumContentSize == CGSize(width: 740, height: 560))
        }

        @Test func listActionsOnlyAffectTheSelectedComponent() throws {
            let chart = try makeEditorStyle(lineWidth: 5)
            let store = ComponentStyleStore(chartStyle: chart)
            let session = ComponentEditorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            session.select(.list)

            let list = try makeEditorListStyle(visibleRowCount: 4)
            let response = try session.receive(body: styleChangeBody(
                component: .list,
                values: list,
                revision: 1
            ))

            #expect(response.state.component == .list)
            #expect(store.chartStyle == chart)
            #expect(store.listStyle == list)

            let copiedResponse = try session.receive(commandMessage(.copyStyle, component: .list))
            let copiedJSON = try #require(copiedResponse.copiedStyleJSON)
            #expect(try JSONDecoder().decode(BreakdownListStyle.self, from: Data(copiedJSON.utf8)) == list)

            let replayResponse = try session.receive(commandMessage(.replayAnimation, component: .list))
            #expect(replayResponse.replayedComponent == .list)

            _ = try session.receive(commandMessage(.reset, component: .list))
            #expect(store.chartStyle == chart)
            #expect(store.listStyle == .default)
        }

        @Test func styleChangesRejectAComponentMismatch() throws {
            let session = ComponentEditorSession(styleStore: ComponentStyleStore())
            _ = try session.receive(readyMessage)

            #expect(throws: ComponentEditorProtocolError.unexpectedComponent) {
                try session.receive(body: styleChangeBody(
                    component: .list,
                    values: BreakdownListStyle.default,
                    revision: 1
                ))
            }

            #expect(throws: DecodingError.self) {
                try session.receive(body: styleChangeBody(
                    component: .chart,
                    values: BreakdownListStyle.default,
                    revision: 1
                ))
            }
        }

        @Test func protocolIdentityAndBodyValidationRejectUnexpectedMessages() throws {
            let session = ComponentEditorSession(styleStore: ComponentStyleStore())

            #expect(throws: ComponentEditorProtocolError.unexpectedProtocolVersion) {
                try session.receive(
                    ComponentEditorIncomingMessage(
                        protocolVersion: 8,
                        type: .ready,
                        source: "component-editor",
                        revision: nil,
                        values: nil
                    )
                )
            }
            #expect(throws: ComponentEditorProtocolError.unexpectedSource) {
                try session.receive(
                    ComponentEditorIncomingMessage(
                        protocolVersion: 7,
                        type: .ready,
                        source: "unexpected",
                        revision: nil,
                        values: nil
                    )
                )
            }
            #expect(throws: (any Error).self) {
                try session.receive(body: ["protocolVersion": 7, "type": "unknown"])
            }
        }

        @Test func sourceSelectionDefaultsToBundleAndRequiresExplicitDevelopmentMode() throws {
            let bundled = try ComponentEditorSource.resolve(environment: [:], arguments: [])
            guard case .bundled = bundled.kind else {
                Issue.record("Expected bundled Editor source")
                return
            }
            #expect(!ComponentEditorSource.isEditorEnabled(environment: [:], arguments: []))

            let bundledEditor = try ComponentEditorSource.resolve(
                environment: [:],
                arguments: [ComponentEditorSource.editorArgument]
            )
            guard case .bundled = bundledEditor.kind else {
                Issue.record("Expected an explicitly enabled bundled Editor source")
                return
            }
            #expect(
                ComponentEditorSource.isEditorEnabled(
                    environment: [:],
                    arguments: [ComponentEditorSource.editorArgument]
                )
            )

            let development = try ComponentEditorSource.resolve(
                environment: [ComponentEditorSource.developmentEnvironmentKey: "1"],
                arguments: []
            )
            #expect(development.kind == .developmentServer)
            #expect(development.entryURL == ComponentEditorSource.developmentURL)

            let argumentDevelopment = try ComponentEditorSource.resolve(
                environment: [:],
                arguments: [ComponentEditorSource.developmentArgument]
            )
            #expect(argumentDevelopment.kind == .developmentServer)
            #expect(
                ComponentEditorSource.isEditorEnabled(
                    environment: [:],
                    arguments: [ComponentEditorSource.developmentArgument]
                )
            )
        }

        @Test func developmentSourceRequiresTheExactLoopbackOrigin() throws {
            let source = ComponentEditorSource(
                entryURL: ComponentEditorSource.developmentURL,
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
            let rootURL = URL(fileURLWithPath: "/Applications/Test.app/Contents/Resources/ComponentEditor")
            let entryURL = rootURL.appendingPathComponent("index.html")
            let source = ComponentEditorSource(entryURL: entryURL, kind: .bundled(rootURL: rootURL))
            let assetURL = rootURL.appendingPathComponent("assets/index.js")
            let siblingURL = rootURL.deletingLastPathComponent()
                .appendingPathComponent("ComponentEditor-copy/index.html")

            #expect(source.allowsNavigation(to: entryURL))
            #expect(source.allowsNavigation(to: assetURL))
            #expect(!source.allowsNavigation(to: siblingURL))
            #expect(!source.allowsNavigation(to: ComponentEditorSource.developmentURL))
            #expect(source.allowsMessage(frameURL: entryURL, scheme: "file", host: "", port: 0))
            #expect(!source.allowsMessage(frameURL: siblingURL, scheme: "file", host: "", port: 0))
        }

        @Test func pageStateOffersARecoverableRetryTransition() {
            let state = ComponentEditorPageState()
            state.fail("Failed")
            #expect(state.phase == .failed("Failed"))

            state.retry()
            #expect(state.phase == .loading)
            #expect(state.reloadToken == 1)

            state.replayAnimation(for: .chart)
            #expect(state.chartAnimationReplayToken == 1)
        }

        private var readyMessage: ComponentEditorIncomingMessage {
            ComponentEditorIncomingMessage(
                protocolVersion: 7,
                type: .ready,
                source: "component-editor",
                revision: nil,
                values: nil
            )
        }

        private func commandMessage(
            _ type: ComponentEditorIncomingMessageType,
            component: EditableComponent = .chart
        ) -> ComponentEditorIncomingMessage {
            ComponentEditorIncomingMessage(
                protocolVersion: 7,
                type: type,
                source: "component-editor",
                revision: nil,
                component: component,
                values: nil
            )
        }

        private func styleChangeBody(
            component: EditableComponent,
            values: some Encodable,
            revision: Int
        ) throws -> [String: Any] {
            let data = try JSONEncoder().encode(values)
            let styleValues = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return [
                "protocolVersion": 7,
                "type": "styleChanged",
                "source": "component-editor",
                "revision": revision,
                "component": component.rawValue,
                "values": styleValues,
            ]
        }
    }

    extension ComponentEditorProtocolTests {
        // swiftlint:disable:next function_body_length
        @Test func everyStyleFieldRoundTripsThroughTheCanonicalNativeBoundary() throws {
            let store = ComponentStyleStore()
            let session = ComponentEditorSession(styleStore: store)
            _ = try session.receive(readyMessage)
            let response = try session.receive(body: [
                "protocolVersion": 7,
                "type": "styleChanged",
                "source": "component-editor",
                "revision": 4,
                "component": "chart",
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

            guard case let .chart(style) = response.state.values else {
                Issue.record("Expected a chart state")
                return
            }
            expectDetailedStyle(style)
            #expect(store.chartStyle == style)
        }

        @Test func previewUsesTheLoadedMockSeries() throws {
            let fixtureRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("DemoFixtures", isDirectory: true)
            let snapshot = try DemoFixtureLoader.load(
                from: fixtureRoot.appendingPathComponent("ideal.json")
            )

            #expect(ComponentEditorPreview(analyticsState: .loaded(snapshot)).points == snapshot.series)
        }

        @Test func previewUsesTheIdealMockSeriesUntilTheModelLoads() throws {
            let fixtureRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("DemoFixtures", isDirectory: true)
            let snapshot = try DemoFixtureLoader.load(
                from: fixtureRoot.appendingPathComponent("ideal.json")
            )

            #expect(ComponentEditorPreview().points == snapshot.series)
        }
    }

    // swiftlint:enable type_body_length

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

    private func makeEditorStyle(
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

    private func makeEditorListStyle(visibleRowCount: Int) throws -> BreakdownListStyle {
        let data = try JSONEncoder().encode(BreakdownListStyle.default)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["visibleRowCount"] = visibleRowCount
        return try JSONDecoder().decode(
            BreakdownListStyle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

#endif
