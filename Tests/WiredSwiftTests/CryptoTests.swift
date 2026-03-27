import XCTest
@testable import WiredSwift

final class CryptoTests: XCTestCase {

    // MARK: - ECDH key generation

    func testECDHPublicKeyIsNotEmpty() {
        let ecdh = ECDH()
        let publicKey = ecdh.publicKeyData()
        XCTAssertNotNil(publicKey)
        XCTAssertGreaterThan(publicKey!.count, 0)
    }

    func testECDHTwoInstancesHaveDifferentPublicKeys() {
        let a = ECDH()
        let b = ECDH()
        XCTAssertNotEqual(a.publicKeyData(), b.publicKeyData())
    }

    // MARK: - ECDH shared secret agreement

    func testECDHTwoPeersAgreeOnSameSecret() {
        let alice = ECDH()
        let bob = ECDH()

        guard
            let alicePub = alice.publicKeyData(),
            let bobPub = bob.publicKeyData()
        else {
            XCTFail("Could not get public keys")
            return
        }

        let aliceSecret = alice.computeSecret(withPublicKey: bobPub)
        let bobSecret = bob.computeSecret(withPublicKey: alicePub)

        XCTAssertNotNil(aliceSecret)
        XCTAssertNotNil(bobSecret)
        XCTAssertEqual(aliceSecret, bobSecret)
    }

    func testECDHSecretIsNotEmpty() {
        let alice = ECDH()
        let bob = ECDH()

        guard let bobPub = bob.publicKeyData() else {
            XCTFail("Could not get Bob's public key")
            return
        }

        let secret = alice.computeSecret(withPublicKey: bobPub)
        XCTAssertNotNil(secret)
        XCTAssertFalse(secret!.isEmpty)
    }

    func testECDHDifferentPeersDifferentSecrets() {
        let alice = ECDH()
        let bob = ECDH()
        let carol = ECDH()

        guard
            let bobPub = bob.publicKeyData(),
            let carolPub = carol.publicKeyData()
        else {
            XCTFail("Could not get public keys")
            return
        }

        let secretWithBob = alice.computeSecret(withPublicKey: bobPub)
        let secretWithCarol = alice.computeSecret(withPublicKey: carolPub)

        XCTAssertNotNil(secretWithBob)
        XCTAssertNotNil(secretWithCarol)
        XCTAssertNotEqual(secretWithBob, secretWithCarol)
    }

    // MARK: - ECDH derived key

    func testECDHDerivedSymmetricKeyNotNil() {
        let alice = ECDH()
        let bob = ECDH()

        guard let bobPub = bob.publicKeyData() else {
            XCTFail()
            return
        }

        _ = alice.computeSecret(withPublicKey: bobPub)
        let salt = Data("testsalt".utf8)
        let key = alice.derivedSymmetricKey(withSalt: salt)

        XCTAssertNotNil(key)
        XCTAssertFalse(key!.isEmpty)
    }

    func testECDHDerivedKeyWithIVNotNil() {
        let alice = ECDH()
        let bob = ECDH()

        guard let bobPub = bob.publicKeyData() else {
            XCTFail()
            return
        }

        _ = alice.computeSecret(withPublicKey: bobPub)
        let salt = Data("testsalt".utf8)
        let result = alice.derivedKey(withSalt: salt, andIVofLength: 16)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.0.count, 32) // key = 32 bytes
        XCTAssertEqual(result!.1.count, 16) // IV  = 16 bytes
    }

    func testECDHInitFromPublicKey() {
        let original = ECDH()
        guard let pubKeyData = original.publicKeyData() else {
            XCTFail()
            return
        }

        let reconstructed = ECDH(withPublicKey: pubKeyData)
        XCTAssertEqual(reconstructed.publicKeyData(), pubKeyData)
    }

    func testECDHComputeSecretWithInvalidPeerKeyReturnsNil() {
        let ecdh = ECDH()
        XCTAssertNil(ecdh.computeSecret(withPublicKey: Data(repeating: 0x55, count: 3)))
    }

    func testECDHPublicKeyInitWithInvalidDataIsSafe() {
        let reconstructed = ECDH(withPublicKey: Data(repeating: 0xAA, count: 7))
        XCTAssertNil(reconstructed.publicKeyData())
        XCTAssertNil(reconstructed.secret)
        XCTAssertNil(reconstructed.derivedSymmetricKey(withSalt: Data("salt".utf8)))
        XCTAssertNil(reconstructed.derivedKey(withSalt: Data("salt".utf8), andIVofLength: 16))
        XCTAssertNil(reconstructed.computeSecret(withPublicKey: Data(repeating: 0x33, count: 7)))
    }

    func testECDHDerivedValuesRequireSharedSecret() {
        let ecdh = ECDH()
        XCTAssertNil(ecdh.secret)
        XCTAssertNil(ecdh.derivedSymmetricKey(withSalt: Data("salt".utf8)))
        XCTAssertNil(ecdh.derivedKey(withSalt: Data("salt".utf8), andIVofLength: 8))
    }

    // MARK: - ECDSA sign / verify

    func testECDSASignAndVerify() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData) else {
            XCTFail("ECDSA init from private key failed")
            return
        }

        let data = Data("hello wired".utf8)
        guard let signature = signer.sign(data: data) else {
            XCTFail("Signing failed")
            return
        }

        XCTAssertTrue(signer.verify(data: data, withSignature: signature))
    }

    func testECDSAVerifyWithModifiedDataFails() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData) else {
            XCTFail()
            return
        }

        let original = Data("authentic message".utf8)
        let tampered = Data("tampered message".utf8)

        guard let signature = signer.sign(data: original) else {
            XCTFail()
            return
        }

        XCTAssertFalse(signer.verify(data: tampered, withSignature: signature))
    }

    func testECDSAVerifyWithWrongSignatureFails() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData) else {
            XCTFail()
            return
        }

        let data = Data("message".utf8)
        let bogusSignature = Data(repeating: 0x42, count: 64)

        XCTAssertFalse(signer.verify(data: data, withSignature: bogusSignature))
    }

    func testECDSAVerifyRejectsMalformedSignatureEncoding() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData) else {
            XCTFail()
            return
        }

        XCTAssertFalse(signer.verify(data: Data("message".utf8), withSignature: Data([0x01])))
    }

    func testECDSAVerifyWithDifferentKeyFails() {
        let key1 = P256.Signing.PrivateKey().rawRepresentation
        let key2 = P256.Signing.PrivateKey().rawRepresentation

        guard
            let signer1 = ECDSA(privateKey: key1),
            let signer2 = ECDSA(privateKey: key2)
        else {
            XCTFail()
            return
        }

        let data = Data("cross-key test".utf8)
        guard let signature = signer1.sign(data: data) else {
            XCTFail()
            return
        }

        XCTAssertFalse(signer2.verify(data: data, withSignature: signature))
    }

    func testECDSAPublicKeyOnlyVerifies() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData) else {
            XCTFail()
            return
        }

        let data = Data("public verify".utf8)
        guard let signature = signer.sign(data: data) else {
            XCTFail()
            return
        }

        // Init verifier with public key only
        guard let signerPublicKey = signer.publicKey?.rawRepresentation,
              let verifier = ECDSA(publicKey: signerPublicKey) else {
            XCTFail("ECDSA init from public key failed")
            return
        }

        XCTAssertTrue(verifier.verify(data: data, withSignature: signature))
    }

    func testECDSAInvalidPrivateKeyReturnsNil() {
        let badKey = Data(repeating: 0x00, count: 32)
        XCTAssertNil(ECDSA(privateKey: badKey))
    }

    func testECDSAInvalidPublicKeyReturnsNil() {
        let badKey = Data(repeating: 0x11, count: 31)
        XCTAssertNil(ECDSA(publicKey: badKey))
    }

    func testECDSAPublicOnlyCannotSign() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData),
              let publicKey = signer.publicKey?.rawRepresentation,
              let verifier = ECDSA(publicKey: publicKey) else {
            XCTFail("Could not initialize public-only verifier")
            return
        }

        XCTAssertNil(verifier.sign(data: Data("sign".utf8)))
    }

    func testECDSAVerifyReturnsFalseWithoutPublicKey() {
        let privateKeyData = P256.Signing.PrivateKey().rawRepresentation
        guard let signer = ECDSA(privateKey: privateKeyData),
              let signature = signer.sign(data: Data("message".utf8)) else {
            XCTFail()
            return
        }

        signer.publicKey = nil
        XCTAssertFalse(signer.verify(data: Data("message".utf8), withSignature: signature))
    }

}

// MARK: - Crypto import for test helpers
import Crypto
