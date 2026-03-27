import XCTest
@testable import WiredSwift

final class ServerIdentityTests: XCTestCase {
    func testIdentityIsPersistedAcrossReloadAndFingerprintStaysStable() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        guard let first = ServerIdentity(workingDirectory: tempDir.path) else {
            return XCTFail("Could not create first identity")
        }
        guard let second = ServerIdentity(workingDirectory: tempDir.path) else {
            return XCTFail("Could not reload identity")
        }

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.identityPublicKey, second.identityPublicKey)
    }

    func testSignAndVerifyRoundTripAndTamperDetection() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        guard let identity = ServerIdentity(workingDirectory: tempDir.path) else {
            return XCTFail("Could not create identity")
        }

        let payload = Data("wired-server-identity".utf8)
        guard let signature = identity.signWithIdentity(data: payload) else {
            return XCTFail("Could not sign payload")
        }

        XCTAssertTrue(identity.verify(data: payload, signature: signature))
        XCTAssertFalse(identity.verify(data: Data("tampered".utf8), signature: signature))
        XCTAssertFalse(identity.verify(data: payload, signature: Data(repeating: 0xAA, count: signature.count)))
        XCTAssertFalse(identity.verify(data: payload, signature: Data([0x01])))
    }

    func testFormattedFingerprintAndExportedPublicKeyAreConsistent() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        guard let identity = ServerIdentity(workingDirectory: tempDir.path) else {
            return XCTFail("Could not create identity")
        }

        let formatted = identity.formattedFingerprint()
        XCTAssertTrue(formatted.hasPrefix("SHA256:"))
        XCTAssertEqual(formatted.replacingOccurrences(of: "SHA256:", with: ""), identity.fingerprint.chunked(by: 2).joined(separator: ":"))

        let publicKeyBase64 = identity.exportPublicKeyBase64()
        XCTAssertEqual(Data(base64Encoded: publicKeyBase64), identity.identityPublicKey)
    }

    func testKeyFileHelpersMatchLiveIdentity() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        guard let identity = ServerIdentity(workingDirectory: tempDir.path) else {
            return XCTFail("Could not create identity")
        }

        let fpFromFile = ServerIdentity.fingerprintFromKeyFile(at: identity.keyFilePath)
        XCTAssertEqual(fpFromFile, identity.formattedFingerprint())

        let pubFromFileBase64Data = ServerIdentity.publicKeyBase64FromKeyFile(at: identity.keyFilePath)
        XCTAssertEqual(pubFromFileBase64Data, identity.identityPublicKey.base64EncodedData())
    }

    func testInitFailsWhenExistingKeyFileIsInvalid() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let keyPath = tempDir.appendingPathComponent("wired-identity.key")
        try Data("not-a-private-key".utf8).write(to: keyPath)

        XCTAssertNil(ServerIdentity(workingDirectory: tempDir.path))
        XCTAssertNil(ServerIdentity.fingerprintFromKeyFile(at: keyPath.path))
        XCTAssertNil(ServerIdentity.publicKeyBase64FromKeyFile(at: keyPath.path))
    }

    func testStrictIdentityDefaultAndOverride() throws {
        let tempDirA = try makeTempDirectory()
        let tempDirB = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        guard let strictDefault = ServerIdentity(workingDirectory: tempDirA.path),
              let strictDisabled = ServerIdentity(workingDirectory: tempDirB.path, strictIdentity: false) else {
            return XCTFail("Could not create identities")
        }

        XCTAssertTrue(strictDefault.strictIdentity)
        XCTAssertFalse(strictDisabled.strictIdentity)
    }

    func testInitFailsWhenIdentityFileCannotBeWritten() {
        XCTAssertNil(ServerIdentity(workingDirectory: "/dev/null"))
    }

    func testFormatAndComputeFingerprintHelpers() {
        let data = Data("pub-key".utf8)
        let fingerprint = ServerIdentity.computeFingerprint(data)
        let formatted = ServerIdentity.format(fingerprint: fingerprint)

        XCTAssertTrue(formatted.hasPrefix("SHA256:"))
        XCTAssertEqual(formatted.dropFirst("SHA256:".count).filter { $0 == ":" }.count, 31)
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wiredswift-crypto-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension String {
    func chunked(by size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var output: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            output.append(String(self[index..<next]))
            index = next
        }
        return output
    }
}
