// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarScanner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "mbm-scan",
            path: "Sources/mbm-scan"
        ),
    ]
)
