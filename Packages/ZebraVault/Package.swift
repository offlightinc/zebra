// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZebraVault",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ZebraVault",
            targets: ["ZebraVault"]
        ),
    ],
    dependencies: [
        .package(path: "../../vendor/bonsplit"),
        .package(path: "../CMUXDebugLog"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "ZebraVault",
            dependencies: [
                .product(name: "Bonsplit", package: "bonsplit"),
                .product(name: "CMUXDebugLog", package: "CMUXDebugLog"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(
            name: "ZebraVaultTests",
            dependencies: ["ZebraVault"]
        ),
    ]
)
