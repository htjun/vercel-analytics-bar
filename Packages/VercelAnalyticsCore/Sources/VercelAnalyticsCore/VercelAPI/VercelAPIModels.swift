import Foundation

struct AuthenticatedUserResponseDTO: Decodable {
    let user: AuthenticatedUserDTO
}

struct AuthenticatedUserDTO: Decodable {
    let username: String?
}

struct TeamsResponseDTO: Decodable {
    let teams: [TeamDTO]
    let pagination: PaginationDTO
}

struct TeamDTO: Decodable {
    let id: String
    let name: String
    let slug: String?
}

struct ProjectsResponseDTO: Decodable {
    let projects: [ProjectDTO]
    let pagination: PaginationDTO
}

struct ProjectDTO: Decodable {
    let id: String
    let name: String
}

struct PaginationDTO: Decodable {
    let next: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decodeIfPresent(String.self, forKey: .next) {
            next = string
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .next) {
            next = String(number)
        } else {
            next = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case next
    }
}

struct AnalyticsCountResponseDTO: Decodable {
    let data: AnalyticsMetricsDTO
    let query: AnalyticsQueryDTO
}

struct AnalyticsOverviewResponseDTO: Decodable {
    let devices: Int
    let total: Int
}

struct AnalyticsSeriesResponseDTO: Decodable {
    let data: [AnalyticsPointDTO]
    let query: AnalyticsQueryDTO
}

struct AnalyticsBreakdownResponseDTO: Decodable {
    let data: [AnalyticsBreakdownPointDTO]
    let query: AnalyticsQueryDTO
}

struct AnalyticsMetricsDTO: Decodable {
    let visitors: Int
    let pageViews: Int

    private enum CodingKeys: String, CodingKey {
        case visitors
        case pageViews = "pageviews"
    }
}

struct AnalyticsPointDTO: Decodable {
    let timestamp: APIDate
    let visitors: Int
    let pageViews: Int

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case visitors
        case pageViews = "pageviews"
    }
}

struct AnalyticsBreakdownPointDTO: Decodable {
    let requestPath: String?
    let referrerHostname: String?
    let visitors: Int
    let pageViews: Int

    private enum CodingKeys: String, CodingKey {
        case requestPath
        case referrerHostname
        case visitors
        case pageViews = "pageviews"
    }
}

struct AnalyticsQueryDTO: Decodable {
    let since: APIDate
    let until: APIDate

    var window: VercelAnalyticsWindow {
        VercelAnalyticsWindow(since: since.value, until: until.value)
    }
}

struct APIDate: Decodable {
    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let date = Self.parse(string) {
            value = date
            return
        }
        if let milliseconds = try? container.decode(Double.self) {
            value = Date(timeIntervalSince1970: milliseconds / 1000)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an API date")
    }

    private static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

func formatDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
