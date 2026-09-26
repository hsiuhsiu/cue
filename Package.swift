// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(
            name: "Cue",
            dependencies: ["CueCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"]),
    ],
    swiftLanguageModes: [.v6]
)
