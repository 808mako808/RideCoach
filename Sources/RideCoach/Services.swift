import AppKit
import Foundation
import Network

final class CallbackServer {
    func waitForCode(port: UInt16) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
                var didResume = false

                listener.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                        defer {
                            connection.cancel()
                            listener.cancel()
                        }

                        guard !didResume else { return }
                        didResume = true

                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard
                            let data,
                            let request = String(data: data, encoding: .utf8),
                            let firstLine = request.components(separatedBy: "\r\n").first,
                            let target = firstLine.split(separator: " ").dropFirst().first,
                            let url = URL(string: "http://localhost:\(port)\(target)")
                        else {
                            Self.respond(to: connection, status: "400 Bad Request", body: "Ride Coach could not read Strava's response.")
                            continuation.resume(throwing: RideCoachError.invalidCallback)
                            return
                        }

                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                            Self.respond(to: connection, status: "400 Bad Request", body: "Strava authorization failed: \(error)")
                            continuation.resume(throwing: RideCoachError.stravaAuthorizationFailed(error))
                            return
                        }

                        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
                            Self.respond(to: connection, status: "400 Bad Request", body: "Ride Coach did not receive an authorization code.")
                            continuation.resume(throwing: RideCoachError.invalidCallback)
                            return
                        }

                        Self.respond(to: connection, status: "200 OK", body: "Ride Coach is connected. You can close this tab.")
                        continuation.resume(returning: code)
                    }
                }

                listener.start(queue: .main)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func respond(to connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Ride Coach</title></head><body><h1>\(body)</h1></body></html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }
}

struct StravaService {
    let clientId: String
    let clientSecret: String
    let callbackPort: UInt16

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var callbackURL: String {
        "http://localhost:\(callbackPort)/callback"
    }

    func authorizeURL() throws -> URL {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw RideCoachError.missingStravaCredentials
        }

        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: callbackURL),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all")
        ]
        return components.url!
    }

    func exchangeAuthorizationCode(_ code: String) async throws -> StravaTokenResponse {
        try await tokenRequest(parameters: [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ])
    }

    func refreshAccessToken(refreshToken: String) async throws -> StravaTokenResponse {
        guard !refreshToken.isEmpty else {
            throw RideCoachError.missingRefreshToken
        }

        return try await tokenRequest(parameters: [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
    }

    func recentActivities(accessToken: String, after: Date?) async throws -> [StravaActivitySummary] {
        try await activities(accessToken: accessToken, after: after, maxPages: 1)
    }

    func activities(accessToken: String, after: Date?, maxPages: Int = 5) async throws -> [StravaActivitySummary] {
        guard !accessToken.isEmpty else {
            throw RideCoachError.missingAccessToken
        }

        var allActivities: [StravaActivitySummary] = []
        for page in 1...max(1, maxPages) {
            let pageActivities = try await activitiesPage(accessToken: accessToken, after: after, page: page)
            allActivities.append(contentsOf: pageActivities)
            if pageActivities.count < 200 {
                break
            }
        }
        return allActivities
    }

    private func activitiesPage(accessToken: String, after: Date?, page: Int) async throws -> [StravaActivitySummary] {
        var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
        var queryItems = [
            URLQueryItem(name: "per_page", value: "200"),
            URLQueryItem(name: "page", value: String(page))
        ]
        if let after {
            queryItems.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode([StravaActivitySummary].self, from: data)
    }

    private func tokenRequest(parameters: [String: String]) async throws -> StravaTokenResponse {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw RideCoachError.missingStravaCredentials
        }

        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(StravaTokenResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server response."
            throw RideCoachError.badServerResponse(message)
        }
    }
}

struct OllamaService {
    let baseURL: URL
    let model: String

    func tags() async throws -> [OllamaLocalModel] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("tags"))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Ollama tags request failed."
            throw RideCoachError.badServerResponse(message)
        }
        return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
    }

    func pullModel() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaPullRequest(name: model, stream: false))

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 1800
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Ollama model pull failed."
            throw RideCoachError.badServerResponse(message)
        }

        let decoded = try JSONDecoder().decode(OllamaPullResponse.self, from: data)
        if let error = decoded.error, !error.isEmpty {
            throw RideCoachError.badServerResponse(error)
        }
        return decoded.status ?? "success"
    }

    func analyze(activity: StravaActivitySummary, history: [StravaActivitySummary], comparisonWindow: ComparisonWindow) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(
            model: model,
            prompt: prompt(for: activity, history: history, comparisonWindow: comparisonWindow),
            stream: false
        ))

        let session = URLSession(configuration: .rideCoachOllama)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Ollama request failed."
            throw RideCoachError.badServerResponse(message)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let text = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw RideCoachError.ollamaResponseEmpty
        }
        return text
    }

    private func prompt(for activity: StravaActivitySummary, history: [StravaActivitySummary], comparisonWindow: ComparisonWindow) -> String {
        let distanceMiles = activity.distance / 1609.344
        let averageMPH = (activity.averageSpeed ?? 0) * 2.236936
        let maxMPH = (activity.maxSpeed ?? 0) * 2.236936
        let movingMinutes = activity.movingTime / 60
        let historySummary = summary(for: history, comparingTo: activity, comparisonWindow: comparisonWindow)

        return """
        You are Ride Coach, a concise cycling coach. Analyze this Strava ride in 5 bullets:
        - one-sentence ride summary
        - comparison to the rider's \(comparisonWindow.promptTitle) of riding
        - pacing and endurance notes
        - intensity notes
        - one recovery recommendation

        \(comparisonWindow.promptTitle.capitalized) context:
        \(historySummary)

        Ride data:
        Name: \(activity.name)
        Type: \(activity.type)
        Date: \(activity.startDateLocal)
        Distance: \(String(format: "%.1f", distanceMiles)) mi
        Moving time: \(movingMinutes) min
        Elevation gain: \(String(format: "%.0f", activity.totalElevationGain * 3.28084)) ft
        Average speed: \(String(format: "%.1f", averageMPH)) mph
        Max speed: \(String(format: "%.1f", maxMPH)) mph
        Average watts: \(activity.averageWatts.map { String(format: "%.0f", $0) } ?? "n/a")
        Weighted average watts: \(activity.weightedAverageWatts.map { String(format: "%.0f", $0) } ?? "n/a")
        Kilojoules: \(activity.kilojoules.map { String(format: "%.0f", $0) } ?? "n/a")
        Average heart rate: \(activity.averageHeartrate.map { String(format: "%.0f", $0) } ?? "n/a")
        Max heart rate: \(activity.maxHeartrate.map { String(format: "%.0f", $0) } ?? "n/a")
        Suffer score: \(activity.sufferScore.map(String.init) ?? "n/a")
        """
    }

    private func summary(for history: [StravaActivitySummary], comparingTo activity: StravaActivitySummary, comparisonWindow: ComparisonWindow) -> String {
        let rides = history
            .filter { $0.type.lowercased().contains("ride") }
            .sorted { $0.startDateLocal > $1.startDateLocal }

        guard !rides.isEmpty else {
            return "No ride history was available."
        }

        let totalMiles = rides.reduce(0) { $0 + $1.distance } / 1609.344
        let totalElevationFeet = rides.reduce(0) { $0 + $1.totalElevationGain } * 3.28084
        let totalMovingHours = Double(rides.reduce(0) { $0 + $1.movingTime }) / 3600
        let averageMiles = totalMiles / Double(rides.count)
        let averageSpeedMPH = rides.compactMap(\.averageSpeed).reduce(0, +) / Double(max(1, rides.compactMap(\.averageSpeed).count)) * 2.236936
        let averageWatts = rides.compactMap(\.averageWatts)
        let averagePower = averageWatts.isEmpty ? nil : averageWatts.reduce(0, +) / Double(averageWatts.count)
        let longestRide = rides.max { $0.distance < $1.distance }
        let currentDistanceRatio = activity.distance > 0 && averageMiles > 0 ? (activity.distance / 1609.344) / averageMiles : 0

        let recentLines = rides.prefix(6).map { ride in
            "- \(shortDate.string(from: ride.startDateLocal)): \(ride.name), \(String(format: "%.1f", ride.distance / 1609.344)) mi, \(ride.movingTime / 60) min, \(String(format: "%.0f", ride.totalElevationGain * 3.28084)) ft, avg HR \(ride.averageHeartrate.map { String(format: "%.0f", $0) } ?? "n/a"), avg watts \(ride.averageWatts.map { String(format: "%.0f", $0) } ?? "n/a")"
        }.joined(separator: "\n")

        return """
        Ride count: \(rides.count)
        Total distance: \(String(format: "%.1f", totalMiles)) mi
        Total moving time: \(String(format: "%.1f", totalMovingHours)) hr
        Total elevation: \(String(format: "%.0f", totalElevationFeet)) ft
        Average ride distance: \(String(format: "%.1f", averageMiles)) mi
        Average ride speed: \(String(format: "%.1f", averageSpeedMPH)) mph
        Average power when available: \(averagePower.map { String(format: "%.0f W", $0) } ?? "n/a")
        Longest ride: \(longestRide.map { "\($0.name), \(String(format: "%.1f", $0.distance / 1609.344)) mi" } ?? "n/a")
        This ride distance versus \(comparisonWindow.promptTitle) average: \(String(format: "%.0f", currentDistanceRatio * 100))%
        Recent rides:
        \(recentLines)
        """
    }
}

private extension URLSessionConfiguration {
    static var rideCoachOllama: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 240
        return configuration
    }
}

private let shortDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()
