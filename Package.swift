// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnowDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SnowDesk", path: "Sources/SnowDesk")
    ]
)
