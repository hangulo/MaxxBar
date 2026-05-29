// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarStats",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MenuBarStats", targets: ["MenuBarStats"]),
        .executable(name: "MenuBarStatsSensorHelper", targets: ["MenuBarStatsSensorHelper"])
    ],
    targets: [
        .executableTarget(
            name: "MenuBarStats",
            path: "Sources/MenuBarStats",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "MenuBarStatsSensorHelper",
            path: "Sources/MenuBarStatsSensorHelper"
        )
    ]
)
