//
//  TLS.swift
//  SocketSwift (local no-TLS fork)
//

import Foundation

#if os(Linux)
public typealias Certificate = (cert: Data, key: Data)
#else
public typealias Certificate = CFArray
#endif

open class TLS {
    public struct Configuration {
        public var peer: String?
        public var certificate: Certificate?
        public var allowSelfSigned: Bool
        public var isServer: Bool { certificate != nil }

        public init(peer: String? = nil, certificate: Certificate? = nil, allowSelfSigned: Bool = false) {
            self.peer = peer
            self.certificate = certificate
            self.allowSelfSigned = allowSelfSigned
        }
    }

    #if os(Linux)
    public static func initialize() throws {
        // No-op: TLS backend intentionally removed from this fork.
    }
    #endif

    public init(_ fd: FileDescriptor, _ config: Configuration) throws {
        throw Socket.Error(errno: ENOTSUP)
    }

    open func handshake() throws {
        throw Socket.Error(errno: ENOTSUP)
    }

    open func write(_ buffer: UnsafeRawPointer, size: Int) throws -> Int {
        throw Socket.Error(errno: ENOTSUP)
    }

    open func read(_ buffer: UnsafeMutableRawPointer, size: Int) throws -> Int {
        throw Socket.Error(errno: ENOTSUP)
    }

    open func close() {
        // No-op
    }
}

extension TLS {
    #if os(Linux)
    open class func importCert(at path: URL, withKey key: URL, password: String?) -> Certificate {
        let cert = (try? Data(contentsOf: path)) ?? Data()
        let keyData = (try? Data(contentsOf: key)) ?? Data()
        return (cert, keyData)
    }
    #else
    open class func importCert(at path: URL, password: String) -> Certificate {
        return [] as CFArray
    }
    #endif
}
