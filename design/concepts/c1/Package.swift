// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "C1Tape",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../shared")],
    targets: [
        .executableTarget(
            name: "Shots",
            dependencies: [.product(name: "ConceptShared", package: "shared")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
