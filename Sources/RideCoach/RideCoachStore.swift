import AppKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class RideCoachStore: ObservableObject {
    @Published var isChecking = false
    @Published var status = "Ready"
    @Published var lastAnalysis: AnalysisRecord?
    @Published var analysisHistory: [AnalysisRecord] = []
    @Published var selectedAnalysisId: String?

    @Published var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: Keys.clientId) }
    }

    @Published var clientSecret: String {
        didSet { UserDefaults.standard.set(clientSecret, forKey: Keys.clientSecret) }
    }

    @Published var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }

    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var cadence: CheckCadence {
        didSet {
            UserDefaults.standard.set(cadence.rawValue, forKey: Keys.cadence)
            scheduleChecks()
        }
    }

    @Published var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: Keys.autoCheckEnabled)
            scheduleChecks()
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var scheduledHour: Int {
        didSet {
            UserDefaults.standard.set(scheduledHour, forKey: Keys.scheduledHour)
            scheduleChecks()
        }
    }

    @Published var scheduledMinute: Int {
        didSet {
            UserDefaults.standard.set(scheduledMinute, forKey: Keys.scheduledMinute)
            scheduleChecks()
        }
    }

    @Published var scheduledWeekday: Int {
        didSet {
            UserDefaults.standard.set(scheduledWeekday, forKey: Keys.scheduledWeekday)
            scheduleChecks()
        }
    }

    @Published var comparisonWindow: ComparisonWindow {
        didSet { UserDefaults.standard.set(comparisonWindow.rawValue, forKey: Keys.comparisonWindow) }
    }

    @Published var autoCheckForUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates) }
    }

    private var accessToken: String {
        get { UserDefaults.standard.string(forKey: Keys.accessToken) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.accessToken) }
    }

    private var refreshToken: String {
        get { UserDefaults.standard.string(forKey: Keys.refreshToken) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.refreshToken) }
    }

    private var tokenExpiresAt: Int {
        get { UserDefaults.standard.integer(forKey: Keys.tokenExpiresAt) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.tokenExpiresAt) }
    }

    private var lastSeenActivityId: Int64 {
        get { Int64(UserDefaults.standard.string(forKey: Keys.lastSeenActivityId) ?? "") ?? 0 }
        set { UserDefaults.standard.set(String(newValue), forKey: Keys.lastSeenActivityId) }
    }

    private var analyzedActivityIds: Set<Int64> {
        get {
            let ids = UserDefaults.standard.stringArray(forKey: Keys.analyzedActivityIds) ?? []
            var parsed = Set(ids.compactMap(Int64.init))
            if lastSeenActivityId != 0 {
                parsed.insert(lastSeenActivityId)
            }
            return parsed
        }
        set {
            let ids = newValue.sorted().suffix(1000).map(String.init)
            UserDefaults.standard.set(Array(ids), forKey: Keys.analyzedActivityIds)
        }
    }

    private var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastCheckDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastCheckDate) }
    }

    private var lastAnalysisActivityDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastAnalysisActivityDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastAnalysisActivityDate) }
    }

    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private let notificationManager = NotificationManager()
    private let callbackPort: UInt16 = 8754

    var isConnectedToStrava: Bool {
        !refreshToken.isEmpty
    }

    var selectedAnalysis: AnalysisRecord? {
        if let selectedAnalysisId,
           let selected = analysisHistory.first(where: { $0.id == selectedAnalysisId }) {
            return selected
        }
        return lastAnalysis
    }

    init() {
        Self.migrateLegacyDefaultsIfNeeded()
        Self.configureNotifications(delegate: notificationManager)

        clientId = UserDefaults.standard.string(forKey: Keys.clientId) ?? ""
        clientSecret = UserDefaults.standard.string(forKey: Keys.clientSecret) ?? ""
        ollamaBaseURL = UserDefaults.standard.string(forKey: Keys.ollamaBaseURL) ?? "http://localhost:11434/api"
        ollamaModel = UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? OllamaModelOption.llamaSmall.rawValue
        cadence = CheckCadence(rawValue: UserDefaults.standard.string(forKey: Keys.cadence) ?? "") ?? .hourly
        autoCheckEnabled = UserDefaults.standard.object(forKey: Keys.autoCheckEnabled) as? Bool ?? true
        notificationsEnabled = UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        scheduledHour = UserDefaults.standard.object(forKey: Keys.scheduledHour) as? Int ?? 8
        scheduledMinute = UserDefaults.standard.object(forKey: Keys.scheduledMinute) as? Int ?? 0
        scheduledWeekday = UserDefaults.standard.object(forKey: Keys.scheduledWeekday) as? Int ?? 2
        comparisonWindow = ComparisonWindow(rawValue: UserDefaults.standard.string(forKey: Keys.comparisonWindow) ?? "") ?? .oneYear
        autoCheckForUpdates = UserDefaults.standard.object(forKey: Keys.autoCheckForUpdates) as? Bool ?? true

        analysisHistory = Self.loadAnalysisHistory()
        if let newest = analysisHistory.first {
            lastAnalysis = newest
            selectedAnalysisId = newest.id
            status = "Last analyzed: \(newest.activityName)"
        } else if
            let data = UserDefaults.standard.data(forKey: Keys.lastAnalysis),
            let record = try? JSONDecoder().decode(AnalysisRecord.self, from: data)
        {
            saveAnalysisRecord(record)
            status = "Last analyzed: \(record.activityName)"
        }

        scheduleChecks()

        if autoCheckForUpdates {
            Task { await checkForUpdates(silent: true) }
        }
    }

    func connectStrava() {
        Task {
            do {
                let service = stravaService()
                let callbackServer = CallbackServer()
                let authURL = try service.authorizeURL()
                status = "Waiting for Strava authorization..."

                Task.detached {
                    await MainActor.run {
                        NSWorkspace.shared.open(authURL)
                    }
                }

                let code = try await callbackServer.waitForCode(port: callbackPort)
                let tokens = try await service.exchangeAuthorizationCode(code)
                save(tokens)
                status = "Strava connected"
                await checkNow()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let service = stravaService()
            let token = try await validAccessToken(using: service)
            let historyStart = comparisonWindow.startDate(before: Date())
            status = "Fetching \(comparisonWindow.title) of rides..."
            let activities = try await service.activities(accessToken: token, after: historyStart, maxPages: comparisonWindow.maxPages)
            let rides = activities
                .filter { $0.type.lowercased().contains("ride") }
                .sorted { $0.startDateLocal > $1.startDateLocal }

            guard let newestRide = rides.first else {
                lastCheckDate = Date()
                status = "No rides found in the last \(comparisonWindow.title)"
                return
            }

            let idsAlreadyAnalyzed = analyzedActivityIds
            let cutoffDate = lastAnalysisActivityDate ?? lastCheckDate
            let newRides: [StravaActivitySummary]
            if let cutoffDate {
                newRides = rides
                    .filter { $0.startDateLocal > cutoffDate && !idsAlreadyAnalyzed.contains($0.id) }
                    .sorted { $0.startDateLocal < $1.startDateLocal }
            } else if !idsAlreadyAnalyzed.contains(newestRide.id) {
                newRides = Array(rides.prefix(3)).sorted { $0.startDateLocal < $1.startDateLocal }
            } else {
                newRides = []
            }

            guard !newRides.isEmpty else {
                lastCheckDate = Date()
                status = "No new rides. Compared \(rides.count) rides from \(comparisonWindow.title)."
                return
            }

            let ollamaURL = URL(string: ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "http://localhost:11434/api")!
            let ollama = OllamaService(baseURL: ollamaURL, model: ollamaModel)
            var completedIds = idsAlreadyAnalyzed
            var analysisSections: [String] = []
            var failedRideCount = 0
            var newestAnalyzedRide = newRides.last ?? newestRide

            for (index, ride) in newRides.enumerated() {
                status = "Analyzing \(index + 1) of \(newRides.count): \(ride.name)"
                do {
                    let analysis = try await ollama.analyze(activity: ride, history: rides, comparisonWindow: comparisonWindow)
                    let displayAnalysis = analysis.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !displayAnalysis.isEmpty else {
                        throw RideCoachError.ollamaResponseEmpty
                    }
                    completedIds.insert(ride.id)
                    newestAnalyzedRide = ride
                    analysisSections.append("""
                    **\(ride.name)**
                    \(shortDisplayDate.string(from: ride.startDateLocal))

                    \(displayAnalysis)
                    """)
                } catch {
                    failedRideCount += 1
                    analysisSections.append("""
                    **\(ride.name)**
                    \(shortDisplayDate.string(from: ride.startDateLocal))

                    Analysis failed: \(error.localizedDescription)
                    """)
                }
            }

            guard completedIds != idsAlreadyAnalyzed else {
                throw RideCoachError.noRideAnalysisCompleted(newRides.count)
            }

            let combinedAnalysis = analysisSections.joined(separator: "\n\n")
            let title = newRides.count == 1 ? newestAnalyzedRide.name : "\(newRides.count) new rides"
            let record = AnalysisRecord(
                activityId: newestAnalyzedRide.id,
                activityName: title,
                activityStartDate: newestAnalyzedRide.startDateLocal,
                analyzedAt: Date(),
                analyzedRideCount: newRides.count,
                text: combinedAnalysis
            )
            saveAnalysisRecord(record)
            analyzedActivityIds = completedIds
            lastSeenActivityId = newestAnalyzedRide.id
            lastAnalysisActivityDate = newestAnalyzedRide.startDateLocal
            lastCheckDate = Date()
            let failureNote = failedRideCount > 0 ? ", \(failedRideCount) failed" : ""
            status = "Analyzed \(newRides.count - failedRideCount) new ride\(newRides.count - failedRideCount == 1 ? "" : "s")\(failureNote) using \(rides.count) rides from \(comparisonWindow.title) (\(combinedAnalysis.count) chars)"
            notifyAnalysisComplete(successCount: newRides.count - failedRideCount, failedCount: failedRideCount, latestRideName: newestAnalyzedRide.name)
        } catch {
            status = error.localizedDescription
        }
    }

    func checkForUpdates(silent: Bool = false) async {
        do {
            var request = URLRequest(url: AppInfo.latestReleaseAPIURL)
            request.timeoutInterval = 15
            request.setValue("RideCoachBeta/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                if !silent {
                    status = "Could not check for updates."
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isVersion(latestVersion, newerThan: AppInfo.version) {
                status = "Update available: \(release.tagName)"
                if autoCheckForUpdates || !silent {
                    NSWorkspace.shared.open(release.htmlURL)
                }
            } else if !silent {
                status = "Ride Coach Beta is up to date."
            }
        } catch {
            if !silent {
                status = "Could not check for updates: \(error.localizedDescription)"
            }
        }
    }

    func disconnectStrava() {
        accessToken = ""
        refreshToken = ""
        tokenExpiresAt = 0
        status = "Strava disconnected"
    }

    func reanalyzeLatest() async {
        clearAnalysisState()
        status = "Ready to reanalyze latest rides"
        await checkNow()
    }

    func sendTestNotification() {
        sendNotification(
            title: AppInfo.displayName,
            subtitle: "Notifications are enabled",
            body: "Ride Coach Beta can notify you when new rides are analyzed."
        )
    }

    func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(AppInfo.bundleIdentifier)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func checkOllama() async {
        let ollamaURL = URL(string: ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "http://localhost:11434/api")!
        do {
            let models = try await OllamaService(baseURL: ollamaURL, model: ollamaModel).tags()
            let hasSelectedModel = models.contains { $0.name == ollamaModel || $0.name == "\(ollamaModel):latest" }
            if hasSelectedModel {
                status = "Ollama is running and \(ollamaModel) is installed."
            } else if models.isEmpty {
                status = "Ollama is running, but no models are installed."
            } else {
                status = "Ollama is running. Install \(ollamaModel) before analyzing rides."
            }
        } catch {
            status = "Ollama is not reachable at \(ollamaBaseURL)."
        }
    }

    func installSelectedOllamaModel() async {
        let ollamaURL = URL(string: ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "http://localhost:11434/api")!
        do {
            status = "Pulling \(ollamaModel). This can take a while..."
            let result = try await OllamaService(baseURL: ollamaURL, model: ollamaModel).pullModel()
            status = "Installed \(ollamaModel): \(result)"
        } catch {
            status = "Could not install \(ollamaModel): \(error.localizedDescription)"
        }
    }

    func openOllamaDownload() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    }

    func openLatestRelease() {
        NSWorkspace.shared.open(AppInfo.releasesURL)
    }

    func revealStravaIcon() {
        guard let url = stravaIconURL() else {
            status = "Strava icon was not found."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyStravaIconPath() {
        guard let url = stravaIconURL() else {
            status = "Strava icon was not found."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        status = "Copied Strava icon path."
    }

    func clearAnalysisState() {
        lastAnalysis = nil
        analysisHistory = []
        selectedAnalysisId = nil
        lastSeenActivityId = 0
        analyzedActivityIds = []
        lastCheckDate = nil
        lastAnalysisActivityDate = nil
        UserDefaults.standard.removeObject(forKey: Keys.lastAnalysis)
        UserDefaults.standard.removeObject(forKey: Keys.analysisHistory)
        UserDefaults.standard.removeObject(forKey: Keys.lastSeenActivityId)
        UserDefaults.standard.removeObject(forKey: Keys.analyzedActivityIds)
        UserDefaults.standard.removeObject(forKey: Keys.lastCheckDate)
        UserDefaults.standard.removeObject(forKey: Keys.lastAnalysisActivityDate)
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let controller = SettingsViewController(store: self)
            let window = SettingsWindow(contentViewController: controller)
            window.title = "\(AppInfo.displayName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 560))
            window.minSize = NSSize(width: 500, height: 460)
            window.isReleasedWhenClosed = false
            window.delegate = controller
            window.center()
            settingsWindow = window
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.makeFirstResponder(settingsWindow?.contentView)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func saveAnalysisRecord(_ record: AnalysisRecord) {
        lastAnalysis = record
        selectedAnalysisId = record.id
        analysisHistory = ([record] + analysisHistory)
            .filterUnique { $0.activityId }
            .prefix(50)
            .map { $0 }

        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Keys.lastAnalysis)
        }
        saveAnalysisHistory()
    }

    private func saveAnalysisHistory() {
        if let data = try? JSONEncoder().encode(analysisHistory) {
            UserDefaults.standard.set(data, forKey: Keys.analysisHistory)
        }
    }

    func scheduleChecks() {
        timer?.invalidate()
        timer = nil

        guard autoCheckEnabled else { return }

        let delay = max(1, nextCheckDate(after: Date()).timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.checkNow()
                self.scheduleChecks()
            }
        }
    }

    func nextCheckDate(after date: Date) -> Date {
        switch cadence {
        case .hourly:
            return date.addingTimeInterval(cadence.interval)
        case .daily:
            return nextDate(after: date, weekday: nil)
        case .weekly:
            return nextDate(after: date, weekday: scheduledWeekday)
        }
    }

    private func nextDate(after date: Date, weekday: Int?) -> Date {
        var components = DateComponents()
        components.hour = scheduledHour
        components.minute = scheduledMinute
        components.second = 0
        if let weekday {
            components.weekday = weekday
        }

        return Calendar.current.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? date.addingTimeInterval(cadence.interval)
    }

    private func validAccessToken(using service: StravaService) async throws -> String {
        let expiresSoon = tokenExpiresAt <= Int(Date().addingTimeInterval(300).timeIntervalSince1970)
        if accessToken.isEmpty || expiresSoon {
            let tokens = try await service.refreshAccessToken(refreshToken: refreshToken)
            save(tokens)
        }
        return accessToken
    }

    private func save(_ tokens: StravaTokenResponse) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenExpiresAt = tokens.expiresAt
    }

    private func stravaService() -> StravaService {
        StravaService(
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            callbackPort: callbackPort
        )
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }

        return false
    }

    private func stravaIconURL() -> URL? {
        let bundledIcon = Bundle.main.resourceURL?.appendingPathComponent("RideCoach-Strava-Icon.png")
        if let bundledIcon, FileManager.default.fileExists(atPath: bundledIcon.path) {
            return bundledIcon
        }

        let projectIcon = URL(fileURLWithPath: "/Users/joncover/dev/RideCoach/Assets/RideCoach-Strava-Icon.png")
        if FileManager.default.fileExists(atPath: projectIcon.path) {
            return projectIcon
        }

        return nil
    }

    private func notifyAnalysisComplete(successCount: Int, failedCount: Int, latestRideName: String) {
        guard notificationsEnabled, successCount > 0 else { return }

        let body: String
        if successCount == 1 {
            body = "Analyzed \(latestRideName)."
        } else {
            body = "Analyzed \(successCount) new rides. Latest: \(latestRideName)."
        }
        let subtitle = failedCount > 0 ? "\(failedCount) ride\(failedCount == 1 ? "" : "s") could not be analyzed." : nil
        sendNotification(title: AppInfo.displayName, subtitle: subtitle, body: body)
    }

    private func sendNotification(title: String, subtitle: String?, body: String) {
        guard notificationsEnabled else { return }
        guard Bundle.main.bundleIdentifier != nil else {
            status = "Notifications require launching Ride Coach as an app bundle."
            return
        }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            center.delegate = notificationManager

            var settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else {
                    status = "Notifications were not allowed."
                    return
                }
                settings = await center.notificationSettings()
            case .denied:
                status = "Notifications are disabled in macOS Settings."
                return
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }

            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                status = "Notifications are not authorized: \(settings.authorizationStatus)"
                return
            }

            guard settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else {
                status = "Notifications are authorized, but alerts are off in macOS Settings."
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let subtitle {
                content.subtitle = subtitle
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "ride-coach-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                status = "Notification sent."
            } catch {
                status = "Could not send notification: \(error.localizedDescription)"
            }
        }
    }

    private static func configureNotifications(delegate: NotificationManager) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        guard let legacyDefaults = UserDefaults(suiteName: "RideCoach") else { return }

        let defaults = UserDefaults.standard
        let keys = [
            Keys.clientId,
            Keys.clientSecret,
            Keys.accessToken,
            Keys.refreshToken,
            Keys.tokenExpiresAt,
            Keys.ollamaBaseURL,
            Keys.ollamaModel,
            Keys.cadence,
            Keys.autoCheckEnabled,
            Keys.notificationsEnabled,
            Keys.scheduledHour,
            Keys.scheduledMinute,
            Keys.scheduledWeekday,
            Keys.comparisonWindow,
            Keys.autoCheckForUpdates,
            Keys.lastSeenActivityId,
            Keys.analyzedActivityIds,
            Keys.lastCheckDate,
            Keys.lastAnalysisActivityDate,
            Keys.lastAnalysis,
            Keys.analysisHistory
        ]

        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}

final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private enum Keys {
    static let clientId = "clientId"
    static let clientSecret = "clientSecret"
    static let accessToken = "accessToken"
    static let refreshToken = "refreshToken"
    static let tokenExpiresAt = "tokenExpiresAt"
    static let ollamaBaseURL = "ollamaBaseURL"
    static let ollamaModel = "ollamaModel"
    static let cadence = "cadence"
    static let autoCheckEnabled = "autoCheckEnabled"
    static let notificationsEnabled = "notificationsEnabled"
    static let scheduledHour = "scheduledHour"
    static let scheduledMinute = "scheduledMinute"
    static let scheduledWeekday = "scheduledWeekday"
    static let comparisonWindow = "comparisonWindow"
    static let autoCheckForUpdates = "autoCheckForUpdates"
    static let lastSeenActivityId = "lastSeenActivityId"
    static let analyzedActivityIds = "analyzedActivityIds"
    static let lastCheckDate = "lastCheckDate"
    static let lastAnalysisActivityDate = "lastAnalysisActivityDate"
    static let lastAnalysis = "lastAnalysis"
    static let analysisHistory = "analysisHistory"
}

private extension RideCoachStore {
    static func loadAnalysisHistory() -> [AnalysisRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.analysisHistory),
            let records = try? JSONDecoder().decode([AnalysisRecord].self, from: data)
        else {
            return []
        }

        return records.sorted { $0.analyzedAt > $1.analyzedAt }
    }
}

private extension Sequence {
    func filterUnique<ID: Hashable>(by id: (Element) -> ID) -> [Element] {
        var seen = Set<ID>()
        var values: [Element] = []
        for element in self where seen.insert(id(element)).inserted {
            values.append(element)
        }
        return values
    }
}

private let shortDisplayDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
