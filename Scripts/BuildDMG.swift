import Foundation

let packageDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appName = "Ride Coach Beta"
let version = "0.0.1.15"
let signingIdentity = ProcessInfo.processInfo.environment["RIDECOACH_SIGN_IDENTITY"]
let notaryProfile = ProcessInfo.processInfo.environment["RIDECOACH_NOTARY_PROFILE"]
let appURL = packageDirectory.appendingPathComponent(".build/\(appName).app")
let stagingURL = packageDirectory.appendingPathComponent(".build/dmg-staging")
let outputURL = packageDirectory.appendingPathComponent(".build/\(appName)-\(version).dmg")
let volumeName = "\(appName) \(version)"

func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "BuildDMG",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(launchPath) \(arguments.joined(separator: " ")) failed."]
        )
    }
}

let fileManager = FileManager.default
try run("/usr/bin/swift", ["Scripts/BuildAppBundle.swift"])

if fileManager.fileExists(atPath: stagingURL.path) {
    try fileManager.removeItem(at: stagingURL)
}
if fileManager.fileExists(atPath: outputURL.path) {
    try fileManager.removeItem(at: outputURL)
}

try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
try fileManager.copyItem(at: appURL, to: stagingURL.appendingPathComponent("\(appName).app"))
try fileManager.createSymbolicLink(at: stagingURL.appendingPathComponent("Applications"), withDestinationURL: URL(fileURLWithPath: "/Applications"))

let stravaIconURL = packageDirectory.appendingPathComponent("Assets/RideCoach-Strava-Icon.png")
if fileManager.fileExists(atPath: stravaIconURL.path) {
    try fileManager.copyItem(at: stravaIconURL, to: stagingURL.appendingPathComponent("Strava API Icon.png"))
}

let guide = """
Ride Coach Beta \(version)

Install
1. Drag Ride Coach Beta.app to Applications.
2. Open Ride Coach Beta from Applications.
3. Open Settings from the menu bar icon.

Strava setup
1. Click Open Strava API Settings in Ride Coach Settings.
2. Create a Strava API app.
3. Set the callback domain to localhost.
4. Upload the included Strava API Icon.png when Strava asks for an application icon.
5. Copy your Strava client ID and client secret into Ride Coach Settings.
6. Click Connect Strava.

Ollama setup
Ride Coach does not bundle Ollama or model weights. This keeps the download small and avoids redistributing model files.

1. Install Ollama from https://ollama.com/download.
2. Start Ollama.
3. In Ride Coach Settings, choose a model.
4. Click Install Selected Model.
5. Click Check Ollama to confirm the model is installed.

AI analysis caution
Ride Coach Beta uses local AI analysis from Ollama. AI output may be incomplete, inaccurate, or overconfident, and it may miss important training, medical, weather, equipment, traffic, or safety context. Treat the analysis as a helpful reflection aid, not professional coaching, medical advice, or a substitute for your own judgment.
"""

try guide.write(to: stagingURL.appendingPathComponent("Setup Guide.txt"), atomically: true, encoding: .utf8)

try run("/usr/bin/hdiutil", [
    "create",
    "-volname",
    volumeName,
    "-srcfolder",
    stagingURL.path,
    "-ov",
    "-format",
    "UDZO",
    outputURL.path
])

if let signingIdentity, signingIdentity.contains("Developer ID") {
    try run("/usr/bin/codesign", [
        "--force",
        "--sign",
        signingIdentity,
        "--timestamp",
        outputURL.path
    ])
}

if let notaryProfile, !notaryProfile.isEmpty {
    try run("/usr/bin/xcrun", [
        "notarytool",
        "submit",
        outputURL.path,
        "--keychain-profile",
        notaryProfile,
        "--wait"
    ])

    try run("/usr/bin/xcrun", [
        "stapler",
        "staple",
        outputURL.path
    ])
}

print(outputURL.path)
