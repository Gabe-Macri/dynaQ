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
        .library(name: "DynaQAudioDriver", targets: ["DynaQAudioDriver"]),
        .library(name: "DynaQDynamics", targets: ["DynaQDynamics"]),
        .library(name: "DynaQAnalysis", targets: ["DynaQAnalysis"]),
        .library(name: "DynaQDSP", targets: ["DynaQDSP"]),
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
            name: "DynaQDynamics",
            dependencies: ["DynaQCore", "CDspKernel"]
        ),
        .target(
            name: "DynaQAnalysis",
            dependencies: ["DynaQCore", "CDspKernel"]
        ),
        .target(
            name: "DynaQDSP",
            dependencies: ["DynaQCore", "CDspKernel", "DynaQAudioDriver", "DynaQDynamics", "DynaQAnalysis"]
        ),
        .target(
            name: "DynaQUI",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQDynamics", "DynaQAnalysis", "DynaQAudioDriver"]
        ),
        .executableTarget(
            name: "DynaQApp",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQDynamics", "DynaQAnalysis", "DynaQAudioDriver", "DynaQUI", "CDspKernel"]
        ),
        .executableTarget(
            name: "DynaQRouter",
            dependencies: ["DynaQCore", "DynaQAudioDriver", "CDspKernel"]
        ),
        .testTarget(
            name: "DynaQDSPTests",
            dependencies: ["DynaQDSP", "DynaQDynamics", "DynaQAnalysis", "DynaQCore", "CDspKernel", "DynaQAudioDriver"]
        ),
        .testTarget(
            name: "DynaQCoreTests",
            dependencies: ["DynaQCore"]
        ),
    ]
)
