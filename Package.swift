// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RideCoach",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RideCoach", targets: ["RideCoach"])
    ],
    targets: [
        .executableTarget(
            name: "RideCoach",
            path: "Sources/RideCoach"
        )
    ]
)
