// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarStats",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MenuBarStats", targets: ["MenuBarStats"])
    ],
    targets: [
        .executableTarget(
            name: "MenuBarStats",
            path: "Sources/MenuBarStats",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
