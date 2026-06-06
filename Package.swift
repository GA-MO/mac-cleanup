// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacCleanup",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacCleanup", targets: ["MacCleanup"]),
        .library(name: "CleanupKit", targets: ["CleanupKit"]),
    ],
    targets: [
        // Core engine: scanners + deletion. Pure Swift, no UI — testable via CLI.
        .target(name: "CleanupKit"),

        // SwiftUI app shell that drives CleanupKit.
        .executableTarget(
            name: "MacCleanup",
            dependencies: ["CleanupKit"]
        ),

        .testTarget(
            name: "CleanupKitTests",
            dependencies: ["CleanupKit"]
        ),
    ]
)
