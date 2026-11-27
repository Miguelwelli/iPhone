// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusStore",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "NexusStore",
            targets: ["NexusStore"]
        ),
    ],
    targets: [
        .target(
            name: "NexusStore",
            path: "Sources/NexusStore"
        ),
    ]
)
