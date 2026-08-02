// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VercelAnalyticsCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VercelAnalyticsCore",
            targets: ["VercelAnalyticsCore"]
        ),
    ],
    targets: [
        .target(name: "VercelAnalyticsCore"),
        .testTarget(
            name: "VercelAnalyticsCoreTests",
            dependencies: ["VercelAnalyticsCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
