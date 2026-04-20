// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var dependencies: [Package.Dependency] = []
var products: [Product] = []
var targetDependencies: [Target.Dependency] = []
var targets: [Target] = []

    

dependencies.append(.package(name: "AEXML", url: "https://github.com/tadija/AEXML.git", from: "4.5.0"))
dependencies.append(.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0")) // 1.3.0
dependencies.append(.package(name: "Queuer", url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.0.0"))
#if !os(Linux)
dependencies.append(.package(name: "DataCompression", url: "https://github.com/mw99/DataCompression.git", from: "3.9.0"))
#endif
dependencies.append(.package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"))
dependencies.append(.package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"))
dependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"))
dependencies.append(.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"))

targetDependencies.append(.byName(name: "AEXML"))
targetDependencies.append(.byName(name: "CryptoSwift"))
targetDependencies.append(.byName(name: "SocketSwift"))
targetDependencies.append(.byName(name: "Queuer"))
#if !os(Linux)
targetDependencies.append(.byName(name: "DataCompression"))
#else
targetDependencies.append(.byName(name: "CZlib"))
targetDependencies.append(.byName(name: "CLZ4"))
#endif
targetDependencies.append(.product(name: "Crypto", package: "swift-crypto"))
// Note: GRDB is added directly to the wired3 target below, not to WiredSwift lib

targets.append(
    .target(
        name: "SocketSwift",
        path: "Vendor/SocketSwift/Sources"
    )
)
targets.append(
    .target(
        name: "WiredSwift",
        dependencies: targetDependencies,
        resources: [.copy("Resources/wired.xml")]
    )
)
targets.append(
    .testTarget(
        name: "WiredSwiftTests",
        dependencies: ["WiredSwift"]
    )
)
targets.append(
    .target(
        name: "wired3Lib",
        dependencies: [
            .byName(name: "WiredSwift"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ],
        path: "Sources/wired3",
        exclude: ["main.swift"]
    )
)
targets.append(
    .executableTarget(
        name: "wired3",
        dependencies: ["wired3Lib"],
        path: "Sources/wired3",
        sources: ["main.swift"]
    )
)
targets.append(
    .testTarget(
        name: "wired3Tests",
        dependencies: [
            "wired3Lib",
            "WiredSwift",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    )
)
targets.append(
    .testTarget(
        name: "wired3IntegrationTests",
        dependencies: [
            "wired3Lib",
            "WiredSwift",
        ]
    )
)

#if !os(Linux)
targets.append(
    .executableTarget(
        name: "WiredServerApp",
        dependencies: [
            .byName(name: "WiredSwift"),
            .byName(name: "CryptoSwift")
        ],
        resources: [
            .process("Resources")
        ]
    )
)
#endif
targets.append(
    .executableTarget(
        name: "WiredChatBot",
        dependencies: [
            .byName(name: "WiredSwift"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/WiredChatBot"
    )
)

products.append(
    .library(
        name: "WiredSwift",
        targets: ["WiredSwift"])
)
products.append(
    .library(
        name: "SocketSwift",
        targets: ["SocketSwift"])
)
products.append(
    .executable(
        name: "wired3",
        targets: ["wired3"])
)
#if !os(Linux)
products.append(
    .executable(
        name: "WiredServerApp",
        targets: ["WiredServerApp"])
)
#endif
products.append(
    .executable(
        name: "WiredChatBot",
        targets: ["WiredChatBot"])
)

#if os(Linux)
targets.append(
    .systemLibrary(
        name: "CZlib",
        pkgConfig: "zlib",
        providers: [
            .apt(["zlib1g-dev"]),
            .brew(["zlib"])
        ]
    )
)
targets.append(
    .systemLibrary(
        name: "CLZ4",
        pkgConfig: "liblz4",
        providers: [
            .apt(["liblz4-dev"]),
            .brew(["lz4"])
        ]
    )
)
#endif

let package = Package(
    name: "WiredSwift",
    defaultLocalization: "en",
    platforms: [.iOS(.v13), .macOS("13.0")],
    products: products,
    dependencies: dependencies,
    targets: targets
)
