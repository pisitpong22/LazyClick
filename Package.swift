// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LazyClick",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LazyClick", targets: ["LazyClick"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Pure gesture logic + CGEvent posting. No private API, no AppKit.
        .target(name: "LazyClickCore", path: "Sources/LazyClickCore"),
        // Menu bar app + the only file that touches MultitouchSupport (MultitouchAdapter.swift).
        .executableTarget(
            name: "LazyClick",
            dependencies: ["LazyClickCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/LazyClick"
        ),
        .testTarget(
            name: "LazyClickCoreTests",
            dependencies: ["LazyClickCore"],
            path: "Tests/LazyClickCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
