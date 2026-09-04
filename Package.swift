// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastNET",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "FastNET", targets: ["FastNET"]),
        .executable(name: "FastNETHelper", targets: ["FastNETHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "FastNET",
            dependencies: [
                "FastNETShared",
                .product(name: "SystemSettingsKit", package: "PermissionFlow")
            ],
            path: "Sources/FastNET",
            resources: [.process("Resources")]
        ),
        .target(
            name: "FastNETShared",
            path: "Sources/FastNETShared"
        ),
        .executableTarget(
            name: "FastNETHelper",
            dependencies: ["FastNETShared"],
            path: "Sources/FastNETHelper"
        ),
        .testTarget(
            name: "FastNETTests",
            dependencies: ["FastNET", "FastNETShared"],
            path: "Tests/FastNETTests"
        )
    ]
)
