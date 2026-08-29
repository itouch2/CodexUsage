// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsageApp"]),
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageApp",
            dependencies: ["UsageCore", "CodexUsageCore"]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"]
        )
    ]
)
