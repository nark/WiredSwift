// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var dependencies: [Package.Dependency] = []
var targetDependencies: [Target.Dependency] = []
var targets: [Target] = []

    

dependencies.append(.package(name: "AEXML", url: "https://github.com/tadija/AEXML.git", from: "4.5.0"))
dependencies.append(.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0")) // 1.3.0
dependencies.append(.package(path: "Vendor/SocketSwift"))
dependencies.append(.package(name: "Queuer", url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.0.0"))
#if !os(Linux)
dependencies.append(.package(name: "DataCompression", url: "https://github.com/mw99/DataCompression.git", from: "3.9.0"))
#endif
dependencies.append(.package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"))
dependencies.append(.package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"))
dependencies.append(.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.1"))
dependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"))
dependencies.append(.package(url: "https://github.com/Kitura/Configuration.git", from: "3.0.200"))

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
targetDependencies.append(.product(name: "Fluent", package: "fluent"))
targetDependencies.append(.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"))

targets.append(
    .target(
        name: "WiredSwift",
        dependencies: targetDependencies
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
        name: "wired3",
        dependencies: [
            .byName(name: "WiredSwift"),
            .byName(name: "Configuration"),
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]
    )
)
targets.append(
    .target(
        name: "WiredServerApp",
        dependencies: [
            .byName(name: "WiredSwift"),
            .byName(name: "CryptoSwift")
        ]
    )
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
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "WiredSwift",
            targets: ["WiredSwift"]),
        
        .executable(
            name: "wired3",
            targets: ["wired3"]),
        .executable(
            name: "WiredServerApp",
            targets: ["WiredServerApp"])
    ],
    dependencies: dependencies,
    targets: targets
)
