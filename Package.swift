// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppIntentsMigrator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "app-intents-migrator", targets: ["app-intents-migrator"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "app-intents-migrator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/AppIntentsMigrator"
        ),
        .testTarget(
            name: "AppIntentsMigratorTests",
            dependencies: [.target(name: "app-intents-migrator")]
        ),
        // Read-only by design: no writeToPackageDirectory permission, so the plugin
        // cannot modify the package it inspects.
        .plugin(
            name: "AppIntentsScan",
            capability: .command(
                intent: .custom(
                    verb: "app-intents-scan",
                    description: "Scan this package for SiriKit patterns that need migrating to App Intents"
                )
            ),
            dependencies: [.target(name: "app-intents-migrator")]
        )
    ]
)
