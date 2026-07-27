// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoPing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CoPingCore", targets: ["CoPingCore"]),
        .executable(name: "CoPing", targets: ["CoPing"]),
        .executable(name: "CoPingHook", targets: ["CoPingHook"]),
        .executable(name: "CoPingSelfTests", targets: ["CoPingSelfTests"]),
    ],
    targets: [
        .target(
            name: "CoPingCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "CoPingAppSupport"),
        .executableTarget(
            name: "CoPing",
            dependencies: ["CoPingCore", "CoPingAppSupport"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "CoPingHook",
            dependencies: ["CoPingCore"]
        ),
        .executableTarget(
            name: "CoPingSelfTests",
            dependencies: ["CoPingCore", "CoPingAppSupport"],
            path: "Tests/CoPingCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
