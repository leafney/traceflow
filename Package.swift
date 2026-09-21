// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Traceflow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TraceflowCore", targets: ["TraceflowCore"]),
        .executable(name: "traceflow-notify", targets: ["TraceflowNotify"]),
        .executable(name: "Traceflow", targets: ["TraceflowApp"]),
    ],
    targets: [
        .target(name: "TraceflowCore"),
        .executableTarget(name: "TraceflowNotify", dependencies: ["TraceflowCore"]),
        .executableTarget(name: "TraceflowApp", dependencies: ["TraceflowCore"]),
        .testTarget(name: "TraceflowCoreTests", dependencies: ["TraceflowCore"]),
    ]
)
