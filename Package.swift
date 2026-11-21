// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SocialAccountVault",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SocialAccountVault",
            targets: ["SocialAccountVaultApp"]
        ),
        .library(
            name: "SocialAccountVaultCore",
            targets: ["SocialAccountVaultCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SocialAccountVaultCore",
            dependencies: [],
            path: "Sources/SocialAccountVaultCore",
            exclude: [
                "Resources/Info.plist",
                "Resources/SocialAccountVault.entitlements"
            ],
            resources: [
                .process("Resources/OfficialDomains.json")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SocialAccountVaultApp",
            dependencies: [
                "SocialAccountVaultCore"
            ],
            path: "Sources/SocialAccountVaultApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SocialAccountVaultTests",
            dependencies: [
                "SocialAccountVaultCore"
            ],
            path: "Tests/SocialAccountVaultTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
