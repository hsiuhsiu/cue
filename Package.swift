// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(
            name: "Cue",
            dependencies: ["CueCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"]),
    ],
    swiftLanguageModes: [.v6]
)
