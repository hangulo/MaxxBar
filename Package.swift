// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MaxxBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MaxxBar", targets: ["MaxxBar"]),
        .executable(name: "MaxxBarSensorHelper", targets: ["MaxxBarSensorHelper"])
    ],
    targets: [
        .executableTarget(
            name: "MaxxBar",
            path: "Sources/MaxxBar",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "MaxxBarSensorHelper",
            path: "Sources/MaxxBarSensorHelper"
        )
    ]
)
