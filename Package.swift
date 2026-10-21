// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dynaQ",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "dynaQ", targets: ["DynaQApp"]),
        .executable(name: "dynaQ-router", targets: ["DynaQRouter"]),
        .library(name: "CDspKernel", targets: ["CDspKernel"]),
        .library(name: "DynaQCore", targets: ["DynaQCore"]),
        .library(name: "DynaQDSP", targets: ["DynaQDSP"]),
        .library(name: "DynaQAudioDriver", targets: ["DynaQAudioDriver"]),
        .library(name: "DynaQUI", targets: ["DynaQUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CDspKernel",
            dependencies: [],
            publicHeadersPath: "include"
        ),
        .target(
            name: "DynaQCore",
            dependencies: []
        ),
        .target(
            name: "DynaQAudioDriver",
            dependencies: ["DynaQCore", "CDspKernel"]
        ),
        .target(
            name: "DynaQDSP",
            dependencies: ["DynaQCore", "CDspKernel", "DynaQAudioDriver"]
        ),
        .target(
            name: "DynaQUI",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver"]
        ),
        .executableTarget(
            name: "DynaQApp",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver", "DynaQUI", "CDspKernel"]
        ),
        .executableTarget(
            name: "DynaQRouter",
            dependencies: ["DynaQCore", "DynaQAudioDriver", "CDspKernel"]
        ),
        .testTarget(
            name: "DynaQDSPTests",
            dependencies: ["DynaQDSP", "DynaQCore", "CDspKernel", "DynaQAudioDriver"]
        ),
        .testTarget(
            name: "DynaQCoreTests",
            dependencies: ["DynaQCore"]
        ),
    ]
)
