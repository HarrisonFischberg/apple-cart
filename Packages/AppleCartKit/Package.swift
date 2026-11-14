// swift-tools-version: 6.2
import PackageDescription

// All app logic lives here so it can be tested with `swift test` without UI.
// Modules are added with the task that needs them (see prd.md).
let package = Package(
    name: "AppleCartKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
        .library(name: "UI", targets: ["UI"]),
        // Dev tool: renders views to PNG (light and dark) for review. Not shipped.
        .executable(name: "UIPreview", targets: ["UIPreview"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "HelperProtocol"),
        .target(name: "UI", dependencies: ["Core"]),
        .executableTarget(name: "UIPreview", dependencies: ["UI", "Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "HelperProtocolTests", dependencies: ["HelperProtocol"]),
    ]
)
