// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppIntentsMigrator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "app-intents-migrator", targets: ["AppIntentsMigrator"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "AppIntentsMigrator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
