import Foundation

let environment = ProcessInfo.processInfo.environment

guard environment["RIDECOACH_SIGN_IDENTITY"]?.contains("Developer ID Application") == true else {
    fatalError("Set RIDECOACH_SIGN_IDENTITY to your Developer ID Application certificate name.")
}

guard environment["RIDECOACH_NOTARY_PROFILE"]?.isEmpty == false else {
    fatalError("Set RIDECOACH_NOTARY_PROFILE to the notarytool keychain profile name.")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["Scripts/BuildDMG.swift"]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(
        domain: "BuildNotarizedDMG",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "BuildDMG.swift failed."]
    )
}
