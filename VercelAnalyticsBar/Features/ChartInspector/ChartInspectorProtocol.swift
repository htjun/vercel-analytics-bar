#if CHART_INSPECTOR
    import Foundation

    struct ChartInspectorIncomingMessage: Decodable {
        private enum CodingKeys: String, CodingKey {
            case protocolVersion, type, source, revision, component, values
        }

        let protocolVersion: Int
        let type: ChartInspectorIncomingMessageType
        let source: String
        let revision: Int?
        let component: EditableComponent?
        let values: ComponentStyle?

        init(
            protocolVersion: Int,
            type: ChartInspectorIncomingMessageType,
            source: String,
            revision: Int?,
            component: EditableComponent? = nil,
            values: ChartStyle?
        ) {
            self.protocolVersion = protocolVersion
            self.type = type
            self.source = source
            self.revision = revision
            self.component = component ?? (values == nil ? nil : .chart)
            self.values = values.map(ComponentStyle.chart)
        }

        static func decode(body: Any) throws -> ChartInspectorIncomingMessage {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw ChartInspectorProtocolError.invalidBody
            }
            let data = try JSONSerialization.data(withJSONObject: body)
            return try JSONDecoder().decode(ChartInspectorIncomingMessage.self, from: data)
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
            type = try container.decode(ChartInspectorIncomingMessageType.self, forKey: .type)
            source = try container.decode(String.self, forKey: .source)
            revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            component = try container.decodeIfPresent(EditableComponent.self, forKey: .component)

            guard let component, container.contains(.values) else {
                values = nil
                return
            }
            switch component {
            case .chart:
                values = try .chart(container.decode(ChartStyle.self, forKey: .values))
            case .list:
                values = try .list(container.decode(BreakdownListStyle.self, forKey: .values))
            }
        }
    }

    struct ChartInspectorStateMessage: Encodable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case protocolVersion, type, source, revision, component, values
        }

        let protocolVersion = ChartInspectorProtocol.version
        let type = ChartInspectorProtocol.nativeStateMessage
        let source = ChartInspectorProtocol.nativeSource
        let revision: Int
        let component: EditableComponent
        let values: ComponentStyle

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(type, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(revision, forKey: .revision)
            try container.encode(component, forKey: .component)
            switch values {
            case let .chart(style):
                try container.encode(style, forKey: .values)
            case let .list(style):
                try container.encode(style, forKey: .values)
            }
        }

        func jsonObject() throws -> [String: Any] {
            let data = try JSONEncoder().encode(self)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ChartInspectorProtocolError.invalidBody
            }
            return object
        }
    }

    struct ChartInspectorSessionResponse: Equatable {
        let state: ChartInspectorStateMessage
        let copiedStyleJSON: String?
        let replayedComponent: EditableComponent?
    }

    enum ChartInspectorProtocolError: Error, Equatable {
        case invalidBody
        case unexpectedProtocolVersion
        case unexpectedSource
        case missingComponent
        case unexpectedComponent
        case missingStyle
        case notReady
        case invalidRevision
        case staleRevision
    }

    @MainActor
    final class ChartInspectorSession {
        private let styleStore: ComponentStyleStore
        private(set) var isReady = false
        private(set) var revision = ChartInspectorProtocol.minimumRevision
        private(set) var selectedComponent: EditableComponent = .chart

        init(styleStore: ComponentStyleStore) {
            self.styleStore = styleStore
        }

        func pageWillLoad() {
            isReady = false
        }

        func select(_ component: EditableComponent) {
            selectedComponent = component
        }

        func receive(body: Any) throws -> ChartInspectorSessionResponse {
            try receive(ChartInspectorIncomingMessage.decode(body: body))
        }

        func receive(_ message: ChartInspectorIncomingMessage) throws -> ChartInspectorSessionResponse {
            guard message.protocolVersion == ChartInspectorProtocol.version else {
                throw ChartInspectorProtocolError.unexpectedProtocolVersion
            }
            guard message.source == ChartInspectorProtocol.webSource else {
                throw ChartInspectorProtocolError.unexpectedSource
            }

            let copiedStyleJSON: String?
            let replayedComponent: EditableComponent?
            switch message.type {
            case .ready:
                isReady = true
                copiedStyleJSON = nil
                replayedComponent = nil
            case .styleChanged:
                try applyStyleChange(message)
                copiedStyleJSON = nil
                replayedComponent = nil
            case .reset:
                try requireSelectedComponent(message)
                guard revision < ChartInspectorProtocol.maximumRevision else {
                    throw ChartInspectorProtocolError.invalidRevision
                }
                styleStore.reset(selectedComponent)
                revision += 1
                copiedStyleJSON = nil
                replayedComponent = nil
            case .copyStyle:
                try requireSelectedComponent(message)
                copiedStyleJSON = try canonicalStyleJSON()
                replayedComponent = nil
            case .replayAnimation:
                try requireSelectedComponent(message)
                copiedStyleJSON = nil
                replayedComponent = selectedComponent
            }

            return ChartInspectorSessionResponse(
                state: stateMessage,
                copiedStyleJSON: copiedStyleJSON,
                replayedComponent: replayedComponent
            )
        }

        var stateMessage: ChartInspectorStateMessage {
            ChartInspectorStateMessage(
                revision: revision,
                component: selectedComponent,
                values: styleStore.style(for: selectedComponent)
            )
        }

        private func requireReady() throws {
            guard isReady else {
                throw ChartInspectorProtocolError.notReady
            }
        }

        private func requireSelectedComponent(_ message: ChartInspectorIncomingMessage) throws {
            try requireReady()
            guard let component = message.component else {
                throw ChartInspectorProtocolError.missingComponent
            }
            guard component == selectedComponent else {
                throw ChartInspectorProtocolError.unexpectedComponent
            }
        }

        private func applyStyleChange(_ message: ChartInspectorIncomingMessage) throws {
            try requireSelectedComponent(message)
            guard let style = message.values else {
                throw ChartInspectorProtocolError.missingStyle
            }
            guard style.component == selectedComponent else {
                throw ChartInspectorProtocolError.unexpectedComponent
            }
            guard let incomingRevision = message.revision,
                  ChartInspectorProtocol.styleChangeRevisionRange.contains(incomingRevision)
            else {
                throw ChartInspectorProtocolError.invalidRevision
            }
            guard incomingRevision > revision else {
                throw ChartInspectorProtocolError.staleRevision
            }
            styleStore.update(style)
            revision = incomingRevision
        }

        private func canonicalStyleJSON() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data: Data = switch styleStore.style(for: selectedComponent) {
            case let .chart(style):
                try encoder.encode(style)
            case let .list(style):
                try encoder.encode(style)
            }
            guard let json = String(data: data, encoding: .utf8) else {
                throw ChartInspectorProtocolError.invalidBody
            }
            return json
        }
    }

    struct ChartInspectorSource: Equatable {
        enum Kind: Equatable {
            case bundled(rootURL: URL)
            case developmentServer
        }

        static let developmentURL = URL(string: "http://127.0.0.1:5173/")!
        static let inspectorArgument = "--chart-inspector"
        static let developmentEnvironmentKey = "CHART_INSPECTOR_DEV_SERVER"
        static let developmentArgument = "--chart-inspector-dev-server"

        let entryURL: URL
        let kind: Kind

        static func resolve(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            arguments: [String] = ProcessInfo.processInfo.arguments,
            bundle: Bundle = .main
        ) throws -> ChartInspectorSource {
            if usesDevelopmentServer(environment: environment, arguments: arguments) {
                return ChartInspectorSource(entryURL: developmentURL, kind: .developmentServer)
            }

            guard let entryURL = bundle.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "ChartInspector"
            ) else {
                throw ChartInspectorSourceError.missingBundledInspector
            }
            return ChartInspectorSource(
                entryURL: entryURL,
                kind: .bundled(rootURL: entryURL.deletingLastPathComponent())
            )
        }

        static func isInspectorEnabled(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> Bool {
            arguments.contains(inspectorArgument) || usesDevelopmentServer(
                environment: environment,
                arguments: arguments
            )
        }

        func allowsNavigation(to url: URL) -> Bool {
            switch kind {
            case .developmentServer:
                return Self.hasDevelopmentOrigin(url)
            case let .bundled(rootURL):
                guard url.isFileURL else { return false }
                let rootPath = rootURL.standardizedFileURL.path + "/"
                let candidatePath = url.standardizedFileURL.path
                return candidatePath == entryURL.standardizedFileURL.path
                    || candidatePath.hasPrefix(rootPath)
            }
        }

        func allowsMessage(
            frameURL: URL?,
            scheme: String,
            host: String,
            port: Int
        ) -> Bool {
            switch kind {
            case .developmentServer:
                scheme == "http"
                    && host == "127.0.0.1"
                    && port == 5173
                    && frameURL.map(Self.hasDevelopmentOrigin) == true
            case .bundled:
                scheme == "file"
                    && host.isEmpty
                    && frameURL.map { allowsNavigation(to: $0) } == true
            }
        }

        private static func hasDevelopmentOrigin(_ url: URL) -> Bool {
            url.scheme == developmentURL.scheme
                && url.host == developmentURL.host
                && url.port == developmentURL.port
                && url.user == nil
                && url.password == nil
        }

        private static func usesDevelopmentServer(
            environment: [String: String],
            arguments: [String]
        ) -> Bool {
            environment[developmentEnvironmentKey] == "1" || arguments.contains(developmentArgument)
        }
    }

    enum ChartInspectorSourceError: Error, Equatable {
        case missingBundledInspector
    }
#endif
