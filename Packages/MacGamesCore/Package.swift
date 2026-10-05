// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacGamesCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MacGamesCore", targets: ["MacGamesCore"]),
        .library(name: "BridgeKit", targets: ["BridgeKit"]),
    ],
    targets: [
        .target(name: "BridgeKit"),
        .target(name: "MacGamesCore"),
        .testTarget(name: "MacGamesCoreTests", dependencies: ["MacGamesCore", "BridgeKit"]),
    ]
)
