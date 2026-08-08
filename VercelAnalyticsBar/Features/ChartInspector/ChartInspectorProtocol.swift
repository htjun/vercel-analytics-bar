#if CHART_INSPECTOR
    import Foundation

    enum ChartInspectorProtocol {
        static let version = 1
        static let webSource = "chart-inspector"
        static let nativeSource = "vercel-analytics-bar"
    }

    enum ChartInspectorIncomingMessageType: String, Codable {
        case ready
        case styleChanged
    }

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
        let type = "state"
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

    enum ChartInspectorProtocolError: Error, Equatable {
        case invalidBody
        case unexpectedProtocolVersion
        case unexpectedSource
        case missingStyle
        case notReady
        case staleRevision
    }

    @MainActor
    final class ChartInspectorSession {
        private let styleStore: ChartStyleStore
        private(set) var isReady = false
        private(set) var revision = 0

        init(styleStore: ChartStyleStore) {
            self.styleStore = styleStore
        }

        func receive(body: Any) throws -> ChartInspectorStateMessage {
            try receive(ChartInspectorIncomingMessage.decode(body: body))
        }

        func receive(_ message: ChartInspectorIncomingMessage) throws -> ChartInspectorStateMessage {
            guard message.protocolVersion == ChartInspectorProtocol.version else {
                throw ChartInspectorProtocolError.unexpectedProtocolVersion
            }
            guard message.source == ChartInspectorProtocol.webSource else {
                throw ChartInspectorProtocolError.unexpectedSource
            }

            switch message.type {
            case .ready:
                isReady = true
            case .styleChanged:
                guard isReady else {
                    throw ChartInspectorProtocolError.notReady
                }
                guard let style = message.values else {
                    throw ChartInspectorProtocolError.missingStyle
                }
                guard let incomingRevision = message.revision, incomingRevision > revision else {
                    throw ChartInspectorProtocolError.staleRevision
                }
                styleStore.update(style)
                revision = incomingRevision
            }

            return stateMessage
        }

        var stateMessage: ChartInspectorStateMessage {
            ChartInspectorStateMessage(revision: revision, values: styleStore.style)
        }
    }

    enum ChartInspectorLocation {
        static let developmentURL = URL(string: "http://127.0.0.1:5173/")!

        static func allows(scheme: String, host: String, port: Int) -> Bool {
            scheme == developmentURL.scheme
                && host == developmentURL.host
                && port == developmentURL.port
        }
    }
#endif
