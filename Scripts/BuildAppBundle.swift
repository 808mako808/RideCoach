import Foundation

let packageDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appName = "Ride Coach Beta"
let executableName = "RideCoach"
let bundleIdentifier = "com.joncover.RideCoachBeta"
let version = "0.0.1.16"
let signingIdentity = ProcessInfo.processInfo.environment["RIDECOACH_SIGN_IDENTITY"] ?? "-"
let isDeveloperIDBuild = signingIdentity.contains("Developer ID Application")
let appURL = packageDirectory.appendingPathComponent(".build/\(appName).app")
let contentsURL = appURL.appendingPathComponent("Contents")
let macOSURL = contentsURL.appendingPathComponent("MacOS")
let resourcesURL = contentsURL.appendingPathComponent("Resources")

func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "BuildAppBundle",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(launchPath) \(arguments.joined(separator: " ")) failed."]
        )
    }
}

try run("/usr/bin/swift", ["build", "-c", "release"])
try run("/usr/bin/swift", ["Scripts/GenerateAppIcon.swift"])

let fileManager = FileManager.default
if fileManager.fileExists(atPath: appURL.path) {
    try fileManager.removeItem(at: appURL)
}
try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

let builtExecutableURL = packageDirectory.appendingPathComponent(".build/release/\(executableName)")
let bundledExecutableURL = macOSURL.appendingPathComponent(executableName)
try fileManager.copyItem(at: builtExecutableURL, to: bundledExecutableURL)

let iconURL = packageDirectory.appendingPathComponent("Assets/RideCoach-Strava-Icon.png")
if fileManager.fileExists(atPath: iconURL.path) {
    try fileManager.copyItem(at: iconURL, to: resourcesURL.appendingPathComponent("RideCoach-Strava-Icon.png"))
}

let appIconURL = packageDirectory.appendingPathComponent("Assets/RideCoach-AppIcon.icns")
if fileManager.fileExists(atPath: appIconURL.path) {
    try fileManager.copyItem(at: appIconURL, to: resourcesURL.appendingPathComponent("RideCoach-AppIcon.icns"))
}

let infoPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>\(appName)</string>
    <key>CFBundleExecutable</key>
    <string>\(executableName)</string>
    <key>CFBundleIdentifier</key>
    <string>\(bundleIdentifier)</string>
    <key>CFBundleIconFile</key>
    <string>RideCoach-AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>\(appName)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>\(version)</string>
    <key>CFBundleVersion</key>
    <string>\(version)</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
"""

try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
try "APPL????".write(to: contentsURL.appendingPathComponent("PkgInfo"), atomically: true, encoding: .ascii)

var codesignArguments = [
    "--force",
    "--deep",
    "--sign",
    signingIdentity,
]

if isDeveloperIDBuild {
    codesignArguments.append(contentsOf: [
        "--options",
        "runtime",
        "--timestamp"
    ])
}

codesignArguments.append(
    appURL.path
)

try run("/usr/bin/codesign", codesignArguments)

print(appURL.path)

try run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", [
    "-f",
    appURL.path
])
