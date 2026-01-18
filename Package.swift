// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var dependencies: [Package.Dependency] = []
var targetDependencies: [Target.Dependency] = []

    

#if os(Linux)
    dependencies.append(.package(url: "https://github.com/IBM-Swift/OpenSSL.git", from: "2.2.0"))
    targetDependencies.append(.byName(name: "OpenSSL"))
#endif


dependencies.append(.package(name: "AEXML", url: "https://github.com/tadija/AEXML.git", from: "4.5.0"))
dependencies.append(.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0")) // 1.3.0
dependencies.append(.package(name: "SocketSwift", url: "https://github.com/BiAtoms/Socket.swift.git", from: "2.4.0"))
dependencies.append(.package(name: "Queuer", url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.0.0"))
dependencies.append(.package(name: "SWCompression", url: "https://github.com/tsolomko/SWCompression.git", from: "4.5.0"))
dependencies.append(.package(name: "DataCompression", url: "https://github.com/mw99/DataCompression.git", from: "3.9.0"))
dependencies.append(.package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"))
dependencies.append(.package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"))
dependencies.append(.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.1"))
dependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"))
dependencies.append(.package(url: "https://github.com/Kitura/Configuration.git", from: "3.0.200"))

targetDependencies.append(.byName(name: "AEXML"))
targetDependencies.append(.byName(name: "CryptoSwift"))
targetDependencies.append(.byName(name: "SocketSwift"))
targetDependencies.append(.byName(name: "Queuer"))
targetDependencies.append(.byName(name: "SWCompression"))
targetDependencies.append(.byName(name: "DataCompression"))
targetDependencies.append(.product(name: "Crypto", package: "swift-crypto"))
targetDependencies.append(.product(name: "Fluent", package: "fluent"))
targetDependencies.append(.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"))

let package = Package(
    name: "WiredSwift",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "WiredSwift",
            targets: ["WiredSwift"]),
        
        .executable(
            name: "wired3",
            targets: ["wired3"])
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "WiredSwift",
            dependencies: targetDependencies),
        .testTarget(
            name: "WiredSwiftTests",
            dependencies: ["WiredSwift"]),
        .target(
            name: "wired3",
            dependencies: [
                .byName(name: "WiredSwift"),
                .byName(name: "Configuration"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
    ]
)
