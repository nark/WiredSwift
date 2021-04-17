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
dependencies.append(.package(name: "DataCompression", url: "https://github.com/mw99/DataCompression", from: "3.6.0"))
dependencies.append(.package(name: "SocketSwift", url: "https://github.com/BiAtoms/Socket.swift.git", from: "2.4.0"))
dependencies.append(.package(name: "GRDB", url: "https://github.com/groue/GRDB.swift.git", from: "5.7.0"))
dependencies.append(.package(name: "Queuer", url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.0.0"))


targetDependencies.append(.byName(name: "AEXML"))
targetDependencies.append(.byName(name: "CryptoSwift"))
targetDependencies.append(.byName(name: "CryptorRSA"))
targetDependencies.append(.byName(name: "DataCompression"))
targetDependencies.append(.byName(name: "SocketSwift"))
targetDependencies.append(.byName(name: "GRDB"))
targetDependencies.append(.byName(name: "Queuer"))


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
