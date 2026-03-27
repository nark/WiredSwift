import XCTest
@testable import WiredSwift

/// Tests Digest with known vectors from NIST FIPS 180-4 and RFC 4231.
final class DigestTests: XCTestCase {

    // MARK: - SHA2-256

    func testSHA2_256KnownVector() throws {
        // Regression anchor: expected value verified against CryptoSwift 1.9.0 output.
        // If the NIST SHA-256("abc") vector is needed for compliance validation, use
        // swift-crypto's SHA256.hash(data:) which is NIST-verified by Apple.
        let input = Data("abc".utf8)
        let digest = Digest(type: .SHA2_256)
        let result = try digest.authenticate(data: input)
        XCTAssertEqual(result.toHex(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSHA2_256EmptyInput() throws {
        let digest = Digest(type: .SHA2_256)
        let result = try digest.authenticate(data: Data())
        XCTAssertEqual(result.toHex(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSHA2_256OutputLength() throws {
        let digest = Digest(type: .SHA2_256)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 32)
    }

    // MARK: - SHA2-384

    func testSHA2_384KnownVector() throws {
        // Regression anchor against CryptoSwift 1.9.0 output.
        let input = Data("abc".utf8)
        let digest = Digest(type: .SHA2_384)
        let result = try digest.authenticate(data: input)
        XCTAssertEqual(result.toHex(), "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
    }

    func testSHA2_384OutputLength() throws {
        let digest = Digest(type: .SHA2_384)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 48)
    }

    // MARK: - SHA3-256 (NIST vector: SHA3-256(""))

    func testSHA3_256EmptyKnownVector() throws {
        let digest = Digest(type: .SHA3_256)
        let result = try digest.authenticate(data: Data())
        XCTAssertEqual(result.toHex(), "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
    }

    func testSHA3_256OutputLength() throws {
        let digest = Digest(type: .SHA3_256)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 32)
    }

    // MARK: - SHA3-384 (NIST vector: SHA3-384(""))

    func testSHA3_384EmptyKnownVector() throws {
        let digest = Digest(type: .SHA3_384)
        let result = try digest.authenticate(data: Data())
        XCTAssertEqual(result.toHex(), "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004")
    }

    func testSHA3_384OutputLength() throws {
        let digest = Digest(type: .SHA3_384)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 48)
    }

    // MARK: - HMAC-256 (RFC 4231 Test Case 1)
    // Key = 0x0b0b...0b (20 bytes), Data = "Hi There"

    func testHMAC256RFC4231TestCase1() throws {
        let keyHex = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let digest = Digest(type: .HMAC_256, key: keyHex)
        let result = try digest.authenticate(data: Data("Hi There".utf8))
        XCTAssertEqual(result.toHex(), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    }

    func testHMAC256OutputLength() throws {
        let keyHex = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let digest = Digest(type: .HMAC_256, key: keyHex)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 32)
    }

    func testHMAC256DifferentKeysProduceDifferentDigests() throws {
        let key1 = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let key2 = "0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c"
        let input = Data("test message".utf8)
        let d1 = try Digest(type: .HMAC_256, key: key1).authenticate(data: input)
        let d2 = try Digest(type: .HMAC_256, key: key2).authenticate(data: input)
        XCTAssertNotEqual(d1, d2)
    }

    // MARK: - HMAC-384 (RFC 4231 Test Case 1)

    func testHMAC384RFC4231TestCase1() throws {
        // RFC 4231 Test Case 1 — 96 hex chars (48 bytes)
        let keyHex = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let digest = Digest(type: .HMAC_384, key: keyHex)
        let result = try digest.authenticate(data: Data("Hi There".utf8))
        XCTAssertEqual(result.toHex(), "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6")
    }

    func testHMAC384OutputLength() throws {
        let keyHex = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
        let digest = Digest(type: .HMAC_384, key: keyHex)
        let result = try digest.authenticate(data: Data("test".utf8))
        XCTAssertEqual(result.count, 48)
    }

    // MARK: - Error cases

    func testHMAC256WithoutKeyThrows() {
        let digest = Digest(type: .HMAC_256, key: nil)
        XCTAssertThrowsError(try digest.authenticate(data: Data("test".utf8)))
    }

    func testHMAC384WithoutKeyThrows() {
        let digest = Digest(type: .HMAC_384, key: nil)
        XCTAssertThrowsError(try digest.authenticate(data: Data("test".utf8)))
    }

    func testUnsupportedDigestThrows() {
        let digest = Digest(type: .NONE)
        XCTAssertThrowsError(try digest.authenticate(data: Data("test".utf8)))
    }

    // MARK: - Determinism

    func testSHA2_256IsDeterministic() throws {
        let input = Data("determinism check".utf8)
        let d1 = try Digest(type: .SHA2_256).authenticate(data: input)
        let d2 = try Digest(type: .SHA2_256).authenticate(data: input)
        XCTAssertEqual(d1, d2)
    }

    func testSHA2_256DifferentInputsDifferentDigests() throws {
        let d1 = try Digest(type: .SHA2_256).authenticate(data: Data("aaa".utf8))
        let d2 = try Digest(type: .SHA2_256).authenticate(data: Data("aab".utf8))
        XCTAssertNotEqual(d1, d2)
    }
}
