// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NexusAdmin",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "NexusAdmin",
            targets: ["NexusAdmin"]
        ),
    ],
    targets: [
        .target(
            name: "NexusAdmin"
        ),
    ]
)
