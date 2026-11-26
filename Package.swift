// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NextVR",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "NextVR",
            targets: ["NextVR"]
        ),
    ],
    targets: [
        .target(
            name: "NextVR"
        ),
    ]
)
