// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "n0-spike",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "N0SpikeCore"),
        .executableTarget(name: "n0spike", dependencies: ["N0SpikeCore"]),
        .testTarget(name: "N0SpikeCoreTests", dependencies: ["N0SpikeCore"])
    ]
)
