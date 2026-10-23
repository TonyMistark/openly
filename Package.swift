// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Openly",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LaunchServicesKit", targets: ["LaunchServicesKit"]),
        .executable(name: "lsk", targets: ["LSKTool"]),
        .executable(name: "Openly", targets: ["Openly"]),
    ],
    targets: [
        .target(
            name: "LaunchServicesKit",
            path: "Sources/LaunchServicesKit"
        ),
        .executableTarget(
            name: "LSKTool",
            dependencies: ["LaunchServicesKit"],
            path: "Sources/LSKTool"
        ),
        .executableTarget(
            name: "Openly",
            dependencies: ["LaunchServicesKit"],
            path: "Sources/Openly"
        ),
        .testTarget(
            name: "LaunchServicesKitTests",
            dependencies: ["LaunchServicesKit"],
            path: "Tests/LaunchServicesKitTests"
        ),
        .testTarget(
            name: "OpenlyTests",
            dependencies: ["Openly"],
            path: "Tests/OpenlyTests"
        ),
    ]
)
