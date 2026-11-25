// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TesteApp",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "TesteApp",
            targets: ["TesteApp"]
        ),
    ],
    targets: [
        .target(
            name: "TesteApp"
        ),
    ]
)
