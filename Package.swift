// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NexusWZ",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "NexusWZ",
            targets: ["NexusWZ"]
        ),
    ],
    targets: [
        .target(
            name: "NexusWZ"
        ),
    ]
)
