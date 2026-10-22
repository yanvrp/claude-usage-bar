// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Limites",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Limites", path: "Sources/Limites"),
        .testTarget(name: "LimitesTests", dependencies: ["Limites"], path: "Tests/LimitesTests"),
    ]
)
