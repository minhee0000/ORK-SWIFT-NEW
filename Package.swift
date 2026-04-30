// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ORK-SWIFT-NEW",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ORKSwiftNewCore",
            targets: ["ORKSwiftNewCore"]
        ),
        .executable(
            name: "ork-swift-new",
            targets: ["ORKSwiftNewCLI"]
        )
    ],
    targets: [
        .target(name: "ORKSwiftNewCore"),
        .executableTarget(
            name: "ORKSwiftNewCLI",
            dependencies: ["ORKSwiftNewCore"]
        ),
        .testTarget(
            name: "ORKSwiftNewCoreTests",
            dependencies: ["ORKSwiftNewCore"]
        )
    ]
)
