// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OneClick",
    platforms: [.macOS(.v15)],
    targets: [
        // Thin executable: defers entirely to OneClickKit (so all logic stays testable).
        .executableTarget(
            name: "oneclick",
            dependencies: ["OneClickKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // All app logic + views live here so the test target can import them.
        .target(
            name: "OneClickKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OneClickKitTests",
            dependencies: ["OneClickKit"],
            resources: [.copy("Fixtures")],   // sample .acf/.vdf + fake prefix trees
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
