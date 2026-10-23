// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileMacOS",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FileMacOS", path: "Sources/FileMacOS")
    ]
)
