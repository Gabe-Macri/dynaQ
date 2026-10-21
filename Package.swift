// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dynaQ",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "dynaQ", targets: ["DynaQApp"]),
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
            name: "DynaQDSP",
            dependencies: ["DynaQCore", "CDspKernel"]
        ),
        .target(
            name: "DynaQAudioDriver",
            dependencies: ["DynaQCore", "DynaQDSP", "CDspKernel"]
        ),
        .target(
            name: "DynaQUI",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver"]
        ),
        .executableTarget(
            name: "DynaQApp",
            dependencies: ["DynaQCore", "DynaQDSP", "DynaQAudioDriver", "DynaQUI", "CDspKernel"]
        ),
        .testTarget(
            name: "DynaQDSPTests",
            dependencies: ["DynaQDSP", "DynaQCore", "CDspKernel"]
        ),
        .testTarget(
            name: "DynaQCoreTests",
            dependencies: ["DynaQCore"]
        ),
    ]
)
