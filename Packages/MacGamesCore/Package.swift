// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacGamesCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MacGamesCore", targets: ["MacGamesCore"]),
        .library(name: "BridgeKit", targets: ["BridgeKit"]),
        .executable(name: "MacGamesBridge", targets: ["MacGamesBridge"]),
    ],
    targets: [
        .target(name: "BridgeKit"),
        .target(name: "MacGamesCore"),
        .executableTarget(name: "MacGamesBridge", dependencies: ["BridgeKit"]),
        .testTarget(name: "MacGamesCoreTests", dependencies: ["MacGamesCore", "BridgeKit", "MacGamesBridge"]),
    ]
)
