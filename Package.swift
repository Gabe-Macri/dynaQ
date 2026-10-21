// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dynaQ",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "dynaQ", targets: ["DynaQApp"]),
        .library(name: "DynaQCore", targets: ["DynaQCore"]),
        .library(name: "DynaQDSP", targets: ["DynaQDSP"]),
        .library(name: "DynaQAudioDriver", targets: ["DynaQAudioDriver"]),
        .library(name: "DynaQUI", targets: ["DynaQUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DynaQCore",
            dependencies: []
        ),
        .target(
            name: "DynaQDSP",
            dependencies: ["DynaQCore"]
        ),
        .target(
            name: "DynaQAudioDriver",
            dependencies: ["DynaQCore", "DynaQDSP"]
        ),
        .target(
            name: "DynaQUI",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver"]
        ),
        .executableTarget(
            name: "DynaQApp",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver", "DynaQUI"]
        ),
        .testTarget(
            name: "DynaQDSPTests",
            dependencies: ["DynaQDSP", "DynaQCore"]
        ),
        .testTarget(
            name: "DynaQCoreTests",
            dependencies: ["DynaQCore"]
        ),
    ]
)

