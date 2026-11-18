// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AulaStudio",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AulaStudio",
            path: "Sources/AulaStudio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
