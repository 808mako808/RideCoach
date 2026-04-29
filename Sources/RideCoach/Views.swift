import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var store: RideCoachStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            if !store.analysisHistory.isEmpty {
                analysisPicker
            }

            if let analysis = store.selectedAnalysis {
                AnalysisView(record: analysis)
            } else {
                Text("Connect Strava, keep Ollama running, and Ride Coach will analyze your newest ride.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Checking \(store.cadence.title.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(store.isConnectedToStrava ? "Reconnect Strava" : "Connect Strava") {
                    store.connectStrava()
                }

                Button {
                    Task { await store.checkNow() }
                } label: {
                    if store.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Check Now")
                    }
                }
                .disabled(store.isChecking)
            }

            HStack {
                Button("Settings") {
                    store.showSettingsWindow()
                }

                Spacer()

                Button("Quit") {
                    store.quit()
                }
            }
        }
        .frame(width: 360)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bicycle")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text(AppInfo.displayName)
                    .font(.headline)
                Text("Version \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var analysisPicker: some View {
        Picker("Analysis", selection: $store.selectedAnalysisId) {
            ForEach(store.analysisHistory) { record in
                Text(historyLabel(for: record))
                    .tag(Optional(record.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func historyLabel(for record: AnalysisRecord) -> String {
        let date = shortMenuDate.string(from: record.analyzedAt)
        return "\(date) - \(record.historyTitle)"
    }
}

struct AnalysisView: View {
    let record: AnalysisRecord
    private var analysisText: String {
        let trimmed = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No analysis text was returned by Ollama." : trimmed
    }
    private var attributedAnalysisText: AttributedString {
        (try? AttributedString(
            markdown: analysisText,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(analysisText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.activityName)
                .font(.headline)

            Text("AI analysis can be inaccurate. Use it as coaching context, not medical, safety, or training-plan advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(attributedAnalysisText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            }
            .frame(width: 328, height: 240)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            )

            Text(record.analyzedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: RideCoachStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsHeader
                stravaSection
                ollamaSection
                checksSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 460)
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(AppInfo.displayName) Settings")
                .font(.title2.bold())

            Text("Version \(AppInfo.version). Connect Strava, choose your local Ollama model, and set how often Ride Coach looks for new rides.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stravaSection: some View {
        SettingsSection(title: "Strava") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Client ID", text: $store.clientId)
                    .textFieldStyle(.roundedBorder)

                SecureField("Client Secret", text: $store.clientSecret)
                    .textFieldStyle(.roundedBorder)

                Text("Set the Strava app callback domain to localhost and use http://localhost:8754/callback as the redirect URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link("Open Strava API Settings", destination: URL(string: "https://www.strava.com/settings/api")!)

                HStack {
                    Button(store.isConnectedToStrava ? "Reconnect Strava" : "Connect Strava") {
                        store.connectStrava()
                    }

                    if store.isConnectedToStrava {
                        Button("Disconnect") {
                            store.disconnectStrava()
                        }
                    }
                }
            }
        }
    }

    private var ollamaSection: some View {
        SettingsSection(title: "Ollama") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Base URL", text: $store.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: $store.ollamaModel) {
                    ForEach(OllamaModelOption.allCases) { model in
                        Text(model.menuTitle).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Choose one of the supported small local models in the Settings window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checksSection: some View {
        SettingsSection(title: "Checks") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check automatically", isOn: $store.autoCheckEnabled)

                Picker("Frequency", selection: $store.cadence) {
                    ForEach(CheckCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .pickerStyle(.segmented)

                Button("Check Now") {
                    Task { await store.checkNow() }
                }
                .disabled(store.isChecking)
            }
        }
    }
}

private let shortMenuDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content
        }
    }
}
