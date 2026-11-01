// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicMouseTap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MagicMouseTap", targets: ["MagicMouseTap"])
    ],
    targets: [
        // Pure gesture logic + CGEvent posting. No private API, no AppKit.
        .target(name: "MagicMouseTapCore", path: "Sources/MagicMouseTapCore"),
        // Menu bar app + the only file that touches MultitouchSupport (MultitouchAdapter.swift).
        .executableTarget(
            name: "MagicMouseTap",
            dependencies: ["MagicMouseTapCore"],
            path: "Sources/MagicMouseTap"
        ),
        .testTarget(
            name: "MagicMouseTapCoreTests",
            dependencies: ["MagicMouseTapCore"],
            path: "Tests/MagicMouseTapCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
