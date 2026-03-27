import XCTest
@testable import WiredSwift

final class CipherTests: XCTestCase {
    private let key32 = Data((0..<32).map { UInt8($0) })
    private let nonce12 = Data((0..<12).map { UInt8($0 + 1) })
    private let nonce24 = Data((0..<24).map { UInt8($0 + 2) })

    func testInitRejectsInvalidKeyLength() {
        XCTAssertThrowsError(
            try Cipher(cipher: .ECDH_AES256_SHA256, keyData: Data([0x01, 0x02]), iv: nil)
        ) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .invalidKey)
        }
    }

    func testInitRejectsUnsupportedCipherType() {
        XCTAssertThrowsError(
            try Cipher(cipher: .NONE, keyData: key32, iv: nil)
        ) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .unsupportedCipher)
        }
    }

    func testInitRejectsMissingOrInvalidNonceForAEADModes() {
        XCTAssertThrowsError(
            try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: nil)
        ) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .invalidNonce)
        }

        XCTAssertThrowsError(
            try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: Data(repeating: 0, count: 11))
        ) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .invalidNonce)
        }

        XCTAssertThrowsError(
            try Cipher(cipher: .ECDH_XCHACHA20_POLY1305, keyData: key32, iv: Data(repeating: 0, count: 12))
        ) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .invalidNonce)
        }
    }

    func testAES256CBCRoundTripAndFrameContainsIV() throws {
        let cipher = try Cipher(cipher: .ECDH_AES256_SHA256, keyData: key32, iv: nil)
        let plaintext = Data("legacy-cbc".utf8)

        let encrypted = try cipher.encrypt(data: plaintext)
        XCTAssertGreaterThan(encrypted.count, plaintext.count)
        XCTAssertGreaterThanOrEqual(encrypted.count, 16, "Legacy CBC frame must include IV prefix")

        let decrypted = try cipher.decrypt(data: encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testAES128GCMRoundTripWithAAD() throws {
        let sender = try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: nonce12)
        let receiver = try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: nonce12)
        let plaintext = Data("aes128-gcm".utf8)
        let aad = Data("aead-metadata".utf8)

        let box = try sender.encrypt(data: plaintext, additionalData: aad)
        let opened = try receiver.decrypt(data: box, additionalData: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testAES128GCMDecryptFailsWithWrongAAD() throws {
        let sender = try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: nonce12)
        let receiver = try Cipher(cipher: .ECDH_AES128_GCM, keyData: key32, iv: nonce12)
        let box = try sender.encrypt(data: Data("payload".utf8), additionalData: Data("good".utf8))

        XCTAssertThrowsError(
            try receiver.decrypt(data: box, additionalData: Data("bad".utf8))
        )
    }

    func testAES256GCMRoundTrip() throws {
        let sender = try Cipher(cipher: .ECDH_AES256_GCM, keyData: key32, iv: nonce12)
        let receiver = try Cipher(cipher: .ECDH_AES256_GCM, keyData: key32, iv: nonce12)
        let plaintext = Data("aes256-gcm".utf8)

        let box = try sender.encrypt(data: plaintext)
        let opened = try receiver.decrypt(data: box)
        XCTAssertEqual(opened, plaintext)
    }

    func testChaCha20Poly1305RoundTrip() throws {
        let sender = try Cipher(cipher: .ECDH_CHACHA20_POLY1305, keyData: key32, iv: nonce12)
        let receiver = try Cipher(cipher: .ECDH_CHACHA20_POLY1305, keyData: key32, iv: nonce12)
        let plaintext = Data("chacha20-poly1305".utf8)

        let box = try sender.encrypt(data: plaintext)
        let opened = try receiver.decrypt(data: box)
        XCTAssertEqual(opened, plaintext)
    }

    func testXChaCha20Poly1305RoundTrip() throws {
        let sender = try Cipher(cipher: .ECDH_XCHACHA20_POLY1305, keyData: key32, iv: nonce24)
        let receiver = try Cipher(cipher: .ECDH_XCHACHA20_POLY1305, keyData: key32, iv: nonce24)
        let plaintext = Data("xchacha20-poly1305".utf8)
        let aad = Data("meta".utf8)

        let box = try sender.encrypt(data: plaintext, additionalData: aad)
        let opened = try receiver.decrypt(data: box, additionalData: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testCounterOverflowThrowsOnEncryptAndDecrypt() throws {
        let cipher = try Cipher(cipher: .ECDH_AES256_GCM, keyData: key32, iv: nonce12)
        cipher.resetCounters(send: .max, recv: 0)

        XCTAssertThrowsError(try cipher.encrypt(data: Data("x".utf8))) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .counterOverflow)
        }

        let sender = try Cipher(cipher: .ECDH_AES256_GCM, keyData: key32, iv: nonce12)
        let box = try sender.encrypt(data: Data("x".utf8))

        let receiver = try Cipher(cipher: .ECDH_AES256_GCM, keyData: key32, iv: nonce12)
        receiver.resetCounters(send: 0, recv: .max)
        XCTAssertThrowsError(try receiver.decrypt(data: box)) { error in
            XCTAssertEqual(error as? Cipher.CipherError, .counterOverflow)
        }
    }

    func testIVLengthAndRandomIVCompatibilityHelpers() {
        XCTAssertEqual(Cipher.IVlength(forCipher: .ECDH_AES256_SHA256), 16)
        XCTAssertEqual(Cipher.IVlength(forCipher: .ECDH_AES128_GCM), 12)
        XCTAssertEqual(Cipher.IVlength(forCipher: .ECDH_AES256_GCM), 12)
        XCTAssertEqual(Cipher.IVlength(forCipher: .ECDH_CHACHA20_POLY1305), 12)
        XCTAssertEqual(Cipher.IVlength(forCipher: .ECDH_XCHACHA20_POLY1305), 24)
        XCTAssertEqual(Cipher.IVlength(forCipher: .NONE), 0)

        XCTAssertEqual(Cipher.randomIV(forCipher: .ECDH_AES256_SHA256)?.count, 16)
        XCTAssertNil(Cipher.randomIV(forCipher: .ECDH_AES128_GCM))
        XCTAssertNil(Cipher.randomIV(forCipher: .ECDH_XCHACHA20_POLY1305))
    }
}
