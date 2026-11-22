// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stare",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StareCore", targets: ["StareCore"]),
        .executable(name: "Stare", targets: ["Stare"]),
    ],
    targets: [
        .target(
            name: "StareCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Stare",
            dependencies: ["StareCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StareCoreTests",
            dependencies: ["StareCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StareTests",
            dependencies: ["Stare"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
