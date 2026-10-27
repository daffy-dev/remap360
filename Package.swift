// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Remap360",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "Remap360Core",
            path: "Sources/Remap360Core"
        ),
        .executableTarget(
            name: "Remap360",
            dependencies: ["Remap360Core"],
            path: "Sources/Remap360"
        ),
        .testTarget(
            name: "Remap360Tests",
            dependencies: ["Remap360Core"],
            path: "Tests/Remap360Tests"
        ),
    ]
)
