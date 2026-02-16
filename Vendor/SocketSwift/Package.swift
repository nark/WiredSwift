// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SocketSwift",
    products: [
        .library(
            name: "SocketSwift",
            targets: ["SocketSwift"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SocketSwift",
            path: "Sources"),
        .testTarget(
            name: "SocketSwiftTests",
            dependencies: ["SocketSwift"]),
    ]
)

