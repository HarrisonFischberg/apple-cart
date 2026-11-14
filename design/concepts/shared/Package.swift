// swift-tools-version: 6.2
import PackageDescription

// Shared mock data, state and screenshot harness for the design concepts.
// Concepts import only this module plus their own presentation code.
let package = Package(
    name: "ConceptShared",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ConceptShared", targets: ["ConceptShared"])],
    targets: [
        .target(name: "ConceptShared", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
