// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unbleep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Unbleep"),
        .testTarget(name: "UnbleepTests", dependencies: ["Unbleep"]),
    ]
)
