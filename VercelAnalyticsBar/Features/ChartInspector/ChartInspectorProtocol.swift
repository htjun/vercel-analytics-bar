#if CHART_INSPECTOR
    import Foundation

    struct ChartInspectorIncomingMessage: Decodable {
        let protocolVersion: Int
        let type: ChartInspectorIncomingMessageType
        let source: String
        let revision: Int?
        let values: ChartStyle?

        static func decode(body: Any) throws -> ChartInspectorIncomingMessage {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw ChartInspectorProtocolError.invalidBody
            }
            let data = try JSONSerialization.data(withJSONObject: body)
            return try JSONDecoder().decode(ChartInspectorIncomingMessage.self, from: data)
        }
    }

    struct ChartInspectorStateMessage: Encodable, Equatable {
        let protocolVersion = ChartInspectorProtocol.version
        let type = ChartInspectorProtocol.nativeStateMessage
        let source = ChartInspectorProtocol.nativeSource
        let revision: Int
        let values: ChartStyle

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
        let replaysAnimation: Bool
    }

    enum ChartInspectorProtocolError: Error, Equatable {
        case invalidBody
        case unexpectedProtocolVersion
        case unexpectedSource
        case missingStyle
        case notReady
        case invalidRevision
        case staleRevision
    }

    @MainActor
    final class ChartInspectorSession {
        private let styleStore: ChartStyleStore
        private(set) var isReady = false
        private(set) var revision = ChartInspectorProtocol.minimumRevision

        init(styleStore: ChartStyleStore) {
            self.styleStore = styleStore
        }

        func pageWillLoad() {
            isReady = false
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
            let previousStyle = styleStore.style
            let replaysAnimation: Bool
            switch message.type {
            case .ready:
                isReady = true
                copiedStyleJSON = nil
                replaysAnimation = false
            case .styleChanged:
                try requireReady()
                guard let style = message.values else {
                    throw ChartInspectorProtocolError.missingStyle
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
                copiedStyleJSON = nil
                replaysAnimation = previousStyle.introAnimation != style.introAnimation
            case .reset:
                try requireReady()
                guard revision < ChartInspectorProtocol.maximumRevision else {
                    throw ChartInspectorProtocolError.invalidRevision
                }
                styleStore.reset()
                revision += 1
                copiedStyleJSON = nil
                replaysAnimation = previousStyle.introAnimation != styleStore.style.introAnimation
            case .copyStyle:
                try requireReady()
                copiedStyleJSON = try canonicalStyleJSON()
                replaysAnimation = false
            case .replayAnimation:
                try requireReady()
                copiedStyleJSON = nil
                replaysAnimation = true
            }

            return ChartInspectorSessionResponse(
                state: stateMessage,
                copiedStyleJSON: copiedStyleJSON,
                replaysAnimation: replaysAnimation
            )
        }

        var stateMessage: ChartInspectorStateMessage {
            ChartInspectorStateMessage(revision: revision, values: styleStore.style)
        }

        private func requireReady() throws {
            guard isReady else {
                throw ChartInspectorProtocolError.notReady
            }
        }

        private func canonicalStyleJSON() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(styleStore.style)
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
