//
//  ServerIdentity.swift
//  WiredSwift
//
//  Manages the server's persistent P256 identity keypair used for TOFU
//  (Trust On First Use) client verification.
//
//  The private key is stored on disk at `<workingDir>/wired-identity.key`.
//  On each connection the server signs the ephemeral ECDH public key so
//  clients can verify they are talking to the same server across sessions.
//

import Foundation
import Crypto
import CryptoSwift

/// Server-side persistent identity key.
///
/// Usage on server:
///   1. Init once at startup: `ServerIdentity(workingDirectory: "…")`
///   2. On each connection: set as `identityProvider` on the P7Socket.
///   3. The socket will call `signWithIdentity(data:)` inside `acceptKeyExchange`.
public class ServerIdentity: ServerIdentityProvider {

    private let privateKey: P256.Signing.PrivateKey

    /// Path to the key file on disk.
    public let keyFilePath: String

    /// Hex SHA-256 fingerprint of the raw (64-byte) P256 public key.
    public let fingerprint: String

    /// Whether clients that detect a key change should hard-fail.
    /// Configurable via `[security] strict_identity` in config.ini.
    public var strictIdentity: Bool

    // MARK: - ServerIdentityProvider conformance

    public var identityPublicKey: Data {
        privateKey.publicKey.rawRepresentation
    }

    public func signWithIdentity(data: Data) -> Data? {
        let signature = try! privateKey.signature(for: data)
        return signature.rawRepresentation
    }

    // MARK: - Init

    public init?(workingDirectory: String, strictIdentity: Bool = true) {
        let keyPath = (workingDirectory as NSString).appendingPathComponent("wired-identity.key")
        self.keyFilePath = keyPath
        self.strictIdentity = strictIdentity

        if FileManager.default.fileExists(atPath: keyPath) {
            guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)),
                  let pk = try? P256.Signing.PrivateKey(rawRepresentation: rawData) else {
                Logger.error("ServerIdentity: failed to load identity key from \(keyPath)")
                return nil
            }
            privateKey = pk
        } else {
            let pk = P256.Signing.PrivateKey()
            do {
                // SECURITY: write via atomic temp file, then restrict to owner-read-write only (0600).
                // Data.write(options: .atomic) does not honour posixPermissions, so we set them explicitly.
                let keyURL = URL(fileURLWithPath: keyPath)
                try pk.rawRepresentation.write(to: keyURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600 as NSNumber],
                    ofItemAtPath: keyPath
                )
            } catch {
                Logger.error("ServerIdentity: failed to write identity key to \(keyPath): \(error)")
                return nil
            }
            privateKey = pk
        }

        fingerprint = ServerIdentity.computeFingerprint(privateKey.publicKey.rawRepresentation)
    }

    // MARK: - Public helpers

    /// Verify a signature produced by `signWithIdentity(data:)`.
    public func verify(data: Data, signature: Data) -> Bool {
        guard let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            return false
        }
        return privateKey.publicKey.isValidSignature(sig, for: data)
    }

    /// Human-readable fingerprint: "SHA256:xx:xx:xx:…"
    public func formattedFingerprint() -> String {
        return ServerIdentity.format(fingerprint: fingerprint)
    }

    /// Export the public key as Base64 (for manual verification / out-of-band pinning).
    public func exportPublicKeyBase64() -> String {
        return identityPublicKey.base64EncodedString()
    }

    // MARK: - Static helpers

    /// Compute fingerprint from raw public key bytes.
    public static func computeFingerprint(_ publicKeyData: Data) -> String {
        return publicKeyData.sha256().toHexString()
    }

    /// Load the raw P256 private key from a file and return its formatted fingerprint,
    /// or nil if the file doesn't exist or is not a valid key.
    /// Intended for use in GUI code that cannot import `Crypto` directly.
    public static func fingerprintFromKeyFile(at path: String) -> String? {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let pk = try? P256.Signing.PrivateKey(rawRepresentation: rawData) else {
            return nil
        }
        let fp = computeFingerprint(pk.publicKey.rawRepresentation)
        return format(fingerprint: fp)
    }

    /// Export the public key as base64 from a key file, or nil on failure.
    public static func publicKeyBase64FromKeyFile(at path: String) -> Data? {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let pk = try? P256.Signing.PrivateKey(rawRepresentation: rawData) else {
            return nil
        }
        return pk.publicKey.rawRepresentation.base64EncodedData()
    }

    /// Format a hex fingerprint as "SHA256:xx:xx:xx:…"
    public static func format(fingerprint: String) -> String {
        var parts: [String] = []
        var i = fingerprint.startIndex
        while i < fingerprint.endIndex {
            let end = fingerprint.index(i, offsetBy: 2, limitedBy: fingerprint.endIndex) ?? fingerprint.endIndex
            parts.append(String(fingerprint[i..<end]))
            i = end
        }
        return "SHA256:" + parts.joined(separator: ":")
    }
}
