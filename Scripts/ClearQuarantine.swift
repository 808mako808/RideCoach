import Foundation

let appPath = CommandLine.arguments.dropFirst().first ?? "/Applications/Ride Coach Beta.app"

func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "ClearQuarantine",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(launchPath) \(arguments.joined(separator: " ")) failed."]
        )
    }
}

try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", appPath])
print("Cleared quarantine from \(appPath)")
