import Foundation

enum AppInfo {
    static let displayName = "Ride Coach Beta"
    static let version = "0.0.1.15"
    static let bundleIdentifier = "com.joncover.RideCoachBeta"
    static let repositoryURL = URL(string: "https://github.com/808mako808/RideCoach")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/808mako808/RideCoach/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/808mako808/RideCoach/releases/latest")!
    static let fullName = "\(displayName) \(version)"
}

enum CheckCadence: String, CaseIterable, Identifiable, Codable {
    case hourly
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .hourly: 60 * 60
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }
}

enum OllamaModelOption: String, CaseIterable, Identifiable {
    case llamaSmall = "llama3.2:1b"
    case qwenSmall = "qwen2.5:1.5b"
    case qwenMedium = "qwen2.5:3b"
    case llamaMedium = "llama3.2:3b"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llamaSmall: "Llama 3.2 1B"
        case .qwenSmall: "Qwen 2.5 1.5B"
        case .qwenMedium: "Qwen 2.5 3B"
        case .llamaMedium: "Llama 3.2 3B"
        }
    }

    var menuTitle: String {
        "\(rawValue) - \(description)"
    }

    var description: String {
        switch self {
        case .llamaSmall:
            "fastest; good quick summaries"
        case .qwenSmall:
            "fast; good structured notes"
        case .qwenMedium:
            "balanced; better detail"
        case .llamaMedium:
            "stronger; slower analysis"
        }
    }
}

enum ComparisonWindow: String, CaseIterable, Identifiable, Codable {
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        }
    }

    var promptTitle: String {
        switch self {
        case .threeMonths: "last 3 months"
        case .sixMonths: "last 6 months"
        case .oneYear: "last year"
        }
    }

    var maxPages: Int {
        switch self {
        case .threeMonths: 8
        case .sixMonths: 12
        case .oneYear: 24
        }
    }

    func startDate(before date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: date) ?? date.addingTimeInterval(-90 * 24 * 60 * 60)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: date) ?? date.addingTimeInterval(-180 * 24 * 60 * 60)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: date) ?? date.addingTimeInterval(-365 * 24 * 60 * 60)
        }
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum RideCoachError: LocalizedError {
    case missingStravaCredentials
    case missingRefreshToken
    case missingAccessToken
    case invalidCallback
    case ollamaResponseEmpty
    case noRideAnalysisCompleted(Int)
    case stravaAuthorizationFailed(String)
    case badServerResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingStravaCredentials:
            "Add your Strava client ID and client secret in Settings first."
        case .missingRefreshToken:
            "Connect Strava before checking for rides."
        case .missingAccessToken:
            "Strava did not return an access token."
        case .invalidCallback:
            "The Strava callback did not include an authorization code."
        case .ollamaResponseEmpty:
            "Ollama returned an empty analysis."
        case .noRideAnalysisCompleted(let count):
            "Ollama could not complete analysis for \(count) ride\(count == 1 ? "" : "s"). Try a smaller/faster model or check Ollama."
        case .stravaAuthorizationFailed(let message):
            "Strava authorization failed: \(message)"
        case .badServerResponse(let message):
            message
        }
    }
}

struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct StravaActivitySummary: Decodable, Identifiable {
    let id: Int64
    let name: String
    let type: String
    let startDateLocal: Date
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageWatts: Double?
    let weightedAverageWatts: Double?
    let kilojoules: Double?
    let sufferScore: Int?
    let averageHeartrate: Double?
    let maxHeartrate: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case startDateLocal = "start_date_local"
        case distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageWatts = "average_watts"
        case weightedAverageWatts = "weighted_average_watts"
        case kilojoules
        case sufferScore = "suffer_score"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
    }
}

struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

struct OllamaGenerateResponse: Decodable {
    let response: String
}

struct OllamaPullRequest: Encodable {
    let name: String
    let stream: Bool
}

struct OllamaPullResponse: Decodable {
    let status: String?
    let error: String?
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaLocalModel]
}

struct OllamaLocalModel: Decodable {
    let name: String
}

struct AnalysisRecord: Codable {
    let activityId: Int64
    let activityName: String
    let activityStartDate: Date?
    let analyzedAt: Date
    let analyzedRideCount: Int?
    let text: String
}
