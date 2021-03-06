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
dependencies.append(.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.3.0"))
dependencies.append(.package(name: "CryptorRSA", url: "https://github.com/IBM-Swift/BlueRSA", from: "1.0.35"))
dependencies.append(.package(name: "CZlib", url: "https://github.com/IBM-Swift/CZlib.git", from: "0.1.2"))
dependencies.append(.package(name: "Gzip", url: "https://github.com/1024jp/GzipSwift", from: "5.1.1"))
dependencies.append(.package(name: "SocketSwift", url: "https://github.com/BiAtoms/Socket.swift.git", from: "2.4.0"))



targetDependencies.append(.byName(name: "AEXML"))
targetDependencies.append(.byName(name: "CryptoSwift"))
targetDependencies.append(.byName(name: "CryptorRSA"))
targetDependencies.append(.byName(name: "CZlib"))
targetDependencies.append(.byName(name: "Gzip"))
targetDependencies.append(.byName(name: "SocketSwift"))




let package = Package(
    name: "WiredSwift",
    platforms: [.iOS(.v12), .macOS(.v10_13)],
    products: [
        .library(
            name: "WiredSwift",
            targets: ["WiredSwift"]),
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "WiredSwift",
            dependencies: targetDependencies),
        .testTarget(
            name: "WiredSwiftTests",
            dependencies: ["WiredSwift"]),
    ]
)
