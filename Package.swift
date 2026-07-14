// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snip",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Snip",
            path: "Sources/Snip",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
