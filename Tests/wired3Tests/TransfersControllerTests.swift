import XCTest
import Foundation
import WiredSwift
@testable import wired3Lib

final class TransfersControllerTests: XCTestCase {
    func testRunDownloadWithoutLimitsStartsImmediatelyAndCleansQueueState() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("payload.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data(repeating: 0x22, count: 32))

        let transfers = makeTransfersController(root: root)
        let client = makeAuthenticatedClient(userID: 20, username: "alice", includeWiredSpec: true)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.download(path: "/payload.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        let result = transfers.run(transfer: transfer, client: client, message: message)

        XCTAssertFalse(result)
        XCTAssertEqual(transfer.state, .running)
        XCTAssertTrue(transfers.transfers.isEmpty)
        XCTAssertNil(transfers.usersDownloadTransfers["alice"])
    }

    func testRunDownloadWithActiveLimitAndDisconnectedClientDoesNotStartTransfer() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("queued.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data(repeating: 0x44, count: 16))

        let transfers = makeTransfersController(root: root)
        transfers.totalDownloadLimit = 1

        let client = makeAuthenticatedClient(userID: 21, username: "bob", includeWiredSpec: true)
        client.state = .DISCONNECTED
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.download(path: "/queued.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        let result = transfers.run(transfer: transfer, client: client, message: message)

        XCTAssertFalse(result)
        XCTAssertEqual(transfer.state, .queued)
        XCTAssertTrue(transfers.transfers.isEmpty)
        XCTAssertNil(transfers.usersDownloadTransfers["bob"])
    }

    func testRunUploadWithoutLimitsStartsImmediatelyAndCleansQueueState() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let transfers = makeTransfersController(root: root)
        let client = makeAuthenticatedClient(userID: 22, username: "charlie", includeWiredSpec: true)
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.upload(path: "/upload-run.dat", dataSize: 24, rsrcSize: 0, executable: false, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        let result = transfers.run(transfer: transfer, client: client, message: message)

        XCTAssertFalse(result)
        XCTAssertEqual(transfer.state, .running)
        XCTAssertTrue(transfers.transfers.isEmpty)
        XCTAssertNil(transfers.usersUploadTransfers["charlie"])
    }

    func testRunUploadWithActiveLimitAndDisconnectedClientDoesNotStartTransfer() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let transfers = makeTransfersController(root: root)
        transfers.totalUploadLimit = 1

        let client = makeAuthenticatedClient(userID: 24, username: "eve", includeWiredSpec: true)
        client.state = .DISCONNECTED
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.upload(path: "/upload-queued.dat", dataSize: 10, rsrcSize: 0, executable: false, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        let result = transfers.run(transfer: transfer, client: client, message: message)

        XCTAssertFalse(result)
        XCTAssertEqual(transfer.state, .queued)
        XCTAssertTrue(transfers.transfers.isEmpty)
        XCTAssertNil(transfers.usersUploadTransfers["eve"])
    }

    func testRunTreatsZeroLimitsAsUnlimited() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("nolimit.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data(repeating: 0x11, count: 8))

        let transfers = makeTransfersController(root: root)
        transfers.totalDownloadLimit = 0
        transfers.perUserDownloadLimit = 0
        transfers.totalUploadLimit = 0
        transfers.perUserUploadLimit = 0

        let client = makeAuthenticatedClient(userID: 23, username: "dana", includeWiredSpec: true)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.download(path: "/nolimit.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        _ = transfers.run(transfer: transfer, client: client, message: message)
        XCTAssertEqual(transfer.state, .running)
    }

    func testDownloadInitializesTransferWithOffsetsAndRemainingSizes() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("sample.bin").path
        let content = Data(repeating: 0xAB, count: 64)
        FileManager.default.createFile(atPath: filePath, contents: content)

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 1)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.download(path: "/sample.bin", dataOffset: 10, rsrcOffset: 0, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        XCTAssertEqual(transfer.type, .download)
        XCTAssertEqual(transfer.realDataPath, filePath)
        XCTAssertEqual(transfer.dataSize, 64)
        XCTAssertEqual(transfer.dataOffset, 10)
        XCTAssertEqual(transfer.remainingDataSize, 54)
        XCTAssertEqual(transfer.transferred, 10)
        XCTAssertEqual(transfer.remainingRsrcSize, 0)
    }

    func testDownloadReturnsNilForMissingFile() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 2)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = transfers.download(path: "/does-not-exist.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        XCTAssertNil(transfer)
    }

    func testDownloadResolvesSymlinkTargetOutsideRoot() throws {
        let root = try makeTemporaryDirectory()
        let external = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        addTeardownBlock { try? FileManager.default.removeItem(at: external) }

        let target = external.appendingPathComponent("payload.bin")
        FileManager.default.createFile(atPath: target.path, contents: Data(repeating: 0x5A, count: 12))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.bin"), withDestinationURL: target)

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 9)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.download(path: "/linked.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        XCTAssertEqual(transfer.realDataPath, target.path)
        XCTAssertEqual(transfer.dataSize, 12)
    }

    func testUploadCreatesPartialFileAndSetsInitialState() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 3)
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.upload(path: "/upload.dat", dataSize: 100, rsrcSize: 0, executable: false, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        XCTAssertEqual(transfer.type, .upload)
        XCTAssertTrue(transfer.realDataPath.hasSuffix(".\(WiredTransferPartialExtension)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transfer.realDataPath))
        XCTAssertEqual(transfer.dataOffset, 0)
        XCTAssertEqual(transfer.remainingDataSize, 100)
        XCTAssertEqual(transfer.transferred, 0)
    }

    func testUploadResumesExistingPartialFileUsingCurrentOffset() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let partialPath = root.appendingPathComponent("resume.dat.\(WiredTransferPartialExtension)").path
        let existing = Data(repeating: 0x11, count: 16)
        FileManager.default.createFile(atPath: partialPath, contents: existing)

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 4)
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.upload(path: "/resume.dat", dataSize: 32, rsrcSize: 0, executable: false, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        XCTAssertEqual(transfer.realDataPath, partialPath)
        XCTAssertEqual(transfer.dataOffset, 16)
        XCTAssertEqual(transfer.transferred, 16)
        XCTAssertEqual(transfer.remainingDataSize, 16)
    }

    func testUploadResolvesSymlinkParentOutsideRoot() throws {
        let root = try makeTemporaryDirectory()
        let external = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        addTeardownBlock { try? FileManager.default.removeItem(at: external) }

        let targetDirectory = external.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("drop"), withDestinationURL: targetDirectory)

        let transfers = makeTransfersController(root: root)
        let client = makeClientWithWiredSpec(userID: 10)
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let transfer = try XCTUnwrap(
            transfers.upload(path: "/drop/upload.dat", dataSize: 20, rsrcSize: 0, executable: false, client: client, message: message)
        )
        defer { try? transfer.dataFd.close() }

        XCTAssertTrue(transfer.realDataPath.hasPrefix(targetDirectory.path))
        XCTAssertTrue(transfer.realDataPath.hasSuffix("upload.dat.\(WiredTransferPartialExtension)"))
    }

    private func makeTransfersController(root: URL) -> TransfersController {
        let filesController = FilesController(rootPath: root.path)
        return TransfersController(filesController: filesController)
    }

    private func makeClientWithWiredSpec(userID: UInt32) -> Client {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: P7Spec(withPath: wiredSpecPath()))
        return Client(userID: userID, socket: socket)
    }

    private func makeAuthenticatedClient(userID: UInt32, username: String, includeWiredSpec: Bool = false) -> Client {
        let socket: P7Socket
        if includeWiredSpec {
            socket = P7Socket(hostname: "localhost", port: 0, spec: P7Spec(withPath: wiredSpecPath()))
        } else {
            socket = P7Socket(hostname: "localhost", port: 0, spec: P7Spec(withPath: nil))
        }

        let client = Client(userID: userID, socket: socket)
        client.state = .LOGGED_IN
        client.user = User(username: username, password: "password")
        return client
    }

    private func wiredSpecPath() -> String {
        WiredProtocolSpec.bundledSpecURL()!.path
    }
}
