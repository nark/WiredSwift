import XCTest
import Foundation
import WiredSwift
@testable import wired3Lib

final class TransfersControllerTests: XCTestCase {
    func testDownloadInitializesTransferWithOffsetsAndRemainingSizes() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("sample.bin").path
        let content = Data(repeating: 0xAB, count: 64)
        FileManager.default.createFile(atPath: filePath, contents: content)

        let transfers = makeTransfersController(root: root)
        let client = makeClient(userID: 1)
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
        let client = makeClient(userID: 2)
        let message = P7Message(withName: "wired.transfer.download_file", spec: client.socket.spec)

        let transfer = transfers.download(path: "/does-not-exist.bin", dataOffset: 0, rsrcOffset: 0, client: client, message: message)
        XCTAssertNil(transfer)
    }

    func testUploadCreatesPartialFileAndSetsInitialState() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let transfers = makeTransfersController(root: root)
        let client = makeClient(userID: 3)
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
        let client = makeClient(userID: 4)
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

    private func makeTransfersController(root: URL) -> TransfersController {
        let filesController = FilesController(rootPath: root.path)
        return TransfersController(filesController: filesController)
    }
}
