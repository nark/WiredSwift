#if os(Linux)
import Foundation
import Glibc
import CZlib
import CLZ4

public enum LinuxCompressionSupport {
    public static var isLZFSEAvailable: Bool {
        LinuxLZFSE.shared.isAvailable
    }
}

public extension Data {
    enum CompressionAlgorithm {
        case zlib
        case lzfse
        case lz4
        case lzma
    }

    func compress(withAlgorithm algo: CompressionAlgorithm) -> Data? {
        switch algo {
        case .zlib:
            return self.deflate()
        case .lzfse:
            return LinuxCompressionCodec.lzfseCompress(self)
        case .lz4:
            return LinuxCompressionCodec.lz4Compress(self)
        case .lzma:
            return nil
        }
    }

    func decompress(withAlgorithm algo: CompressionAlgorithm) -> Data? {
        switch algo {
        case .zlib:
            return self.inflate()
        case .lzfse:
            return LinuxCompressionCodec.lzfseDecompress(self)
        case .lz4:
            return LinuxCompressionCodec.lz4Decompress(self)
        case .lzma:
            return nil
        }
    }

    // RFC-1951 raw deflate stream.
    func deflate() -> Data? {
        LinuxCompressionCodec.zlibDeflate(self)
    }

    // RFC-1951 raw inflate stream.
    func inflate() -> Data? {
        LinuxCompressionCodec.zlibInflate(self)
    }
}

private enum LinuxCompressionCodec {
    private static let chunkSize = 64 * 1024
    private static let appleLZ4HeaderStore: [UInt8] = [0x62, 0x76, 0x34, 0x2d] // "bv4-"
    private static let appleLZ4Footer: [UInt8] = [0x62, 0x76, 0x34, 0x24] // "bv4$"

    static func zlibDeflate(_ input: Data) -> Data? {
        processZlib(input: input, compress: true)
    }

    static func zlibInflate(_ input: Data) -> Data? {
        processZlib(input: input, compress: false)
    }

    private static func processZlib(input: Data, compress: Bool) -> Data? {
        var stream = z_stream()

        let initStatus: Int32 = compress
            ? deflateInit2_(&stream,
                            Z_DEFAULT_COMPRESSION,
                            Z_DEFLATED,
                            -MAX_WBITS,
                            MAX_MEM_LEVEL,
                            Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size))
            : inflateInit2_(&stream,
                            -MAX_WBITS,
                            ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size))

        guard initStatus == Z_OK else {
            return nil
        }

        defer {
            if compress {
                deflateEnd(&stream)
            } else {
                inflateEnd(&stream)
            }
        }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        return input.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return compress ? Data([0x03, 0x00]) : Data()
            }

            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(input.count)

            while true {
                let status: Int32 = buffer.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)

                    if compress {
                        return deflate(&stream, Z_FINISH)
                    } else {
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }

                if status == Z_STREAM_END {
                    return output
                }

                if compress {
                    guard status == Z_OK else { return nil }
                } else {
                    guard status == Z_OK else { return nil }
                    if stream.avail_in == 0 && produced == 0 {
                        return nil
                    }
                }
            }
        }
    }

    static func lz4Compress(_ input: Data) -> Data? {
        if input.isEmpty {
            return Data()
        }

        // Apple's lz4 stream format accepts stored (uncompressed) payload in bv4 framing.
        // Use this mode for strict cross-platform interoperability with Compression.framework.
        var framed = Data()
        framed.append(contentsOf: appleLZ4HeaderStore)
        var originalSizeLE = UInt32(input.count).littleEndian
        framed.append(Data(bytes: &originalSizeLE, count: MemoryLayout<UInt32>.size))
        framed.append(input)
        framed.append(contentsOf: appleLZ4Footer)
        return framed
    }

    static func lz4Decompress(_ input: Data) -> Data? {
        if input.isEmpty {
            return Data()
        }

        if let payload = unwrapAppleLZ4Frame(input) {
            let (compressed, expectedSize, variant) = payload
            if expectedSize == 0 { return Data() }
            if compressed.count == expectedSize {
                return compressed
            }
            var destination = [UInt8](repeating: 0, count: expectedSize)
            let decodedCount: Int32? = compressed.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: CChar.self)
                guard let sourcePtr = source.baseAddress else { return nil }
                return destination.withUnsafeMutableBufferPointer { outBuffer in
                    LZ4_decompress_safe(sourcePtr,
                                        outBuffer.baseAddress,
                                        Int32(compressed.count),
                                        Int32(expectedSize))
                }
            }
            if let decodedCount, decodedCount == Int32(expectedSize) { return Data(destination) }
            Logger.error("Linux LZ4 decode frame failed: variant=\(variant) compressed=\(compressed.count) expected=\(expectedSize) decoded=\(decodedCount ?? -1)")
            return nil
        }

        var destinationCapacity = max(chunkSize, input.count * 4)
        let maxCapacity = max(32 * 1024 * 1024, input.count * 256)

        while destinationCapacity <= maxCapacity {
            var destination = [UInt8](repeating: 0, count: destinationCapacity)
            let decodedCount: Int32? = input.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: CChar.self)
                guard let sourcePtr = source.baseAddress else { return nil }
                return destination.withUnsafeMutableBufferPointer { outBuffer in
                    LZ4_decompress_safe(sourcePtr,
                                        outBuffer.baseAddress,
                                        Int32(input.count),
                                        Int32(destinationCapacity))
                }
            }

            if let decodedCount, decodedCount >= 0 { return Data(destination.prefix(Int(decodedCount))) }

            destinationCapacity *= 2
        }

        return nil
    }

    private static func unwrapAppleLZ4Frame(_ input: Data) -> (compressed: Data, expectedSize: Int, variant: UInt8)? {
        let overhead = 4 + MemoryLayout<UInt32>.size + appleLZ4Footer.count
        guard input.count >= overhead else { return nil }

        let prefix = input.prefix(4)
        let suffix = input.suffix(appleLZ4Footer.count)
        let prefixBytes = Array(prefix)
        guard prefixBytes.count == 4,
              prefixBytes[0] == 0x62, // b
              prefixBytes[1] == 0x76, // v
              prefixBytes[2] == 0x34, // 4
              Array(suffix) == appleLZ4Footer
        else { return nil }
        let variant = prefixBytes[3]

        let sizeOffset = 4
        let sizeEnd = sizeOffset + MemoryLayout<UInt32>.size
        let sizeData = input.subdata(in: sizeOffset..<sizeEnd)
        let expectedSize = sizeData.withUnsafeBytes { rawBuffer -> Int in
            let value = rawBuffer.load(as: UInt32.self)
            return Int(UInt32(littleEndian: value))
        }

        let payloadStart = sizeEnd
        let payloadEnd = input.count - appleLZ4Footer.count
        let payload = input.subdata(in: payloadStart..<payloadEnd)
        return (payload, expectedSize, variant)
    }

    static func lzfseCompress(_ input: Data) -> Data? {
        guard let encode = LinuxLZFSE.shared.encode else {
            return nil
        }

        if input.isEmpty {
            return Data()
        }

        var destinationCapacity = max(chunkSize, input.count + input.count / 4 + 1024)
        let maxCapacity = max(64 * 1024 * 1024, input.count * 16 + 4096)

        while destinationCapacity <= maxCapacity {
            var destination = [UInt8](repeating: 0, count: destinationCapacity)
            let encodedCount: Int? = input.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: UInt8.self)
                guard let sourcePtr = source.baseAddress else { return nil }
                return destination.withUnsafeMutableBufferPointer { outBuffer in
                    encode(outBuffer.baseAddress,
                           destinationCapacity,
                           sourcePtr,
                           input.count,
                           nil)
                }
            }

            if let encodedCount, encodedCount > 0 {
                return Data(destination.prefix(encodedCount))
            }

            destinationCapacity *= 2
        }

        return nil
    }

    static func lzfseDecompress(_ input: Data) -> Data? {
        guard let decode = LinuxLZFSE.shared.decode else {
            return nil
        }

        if input.isEmpty {
            return Data()
        }

        var destinationCapacity = max(chunkSize, input.count * 4)
        let maxCapacity = max(128 * 1024 * 1024, input.count * 512)

        while destinationCapacity <= maxCapacity {
            var destination = [UInt8](repeating: 0, count: destinationCapacity)
            let decodedCount: Int? = input.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: UInt8.self)
                guard let sourcePtr = source.baseAddress else { return nil }
                return destination.withUnsafeMutableBufferPointer { outBuffer in
                    decode(outBuffer.baseAddress,
                           destinationCapacity,
                           sourcePtr,
                           input.count,
                           nil)
                }
            }

            if let decodedCount, decodedCount > 0 {
                return Data(destination.prefix(decodedCount))
            }

            destinationCapacity *= 2
        }

        return nil
    }
}

private struct LinuxLZFSE {
    typealias EncodeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Int
    typealias DecodeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Int

    static let shared = LinuxLZFSE()

    let handle: UnsafeMutableRawPointer?
    let encode: EncodeFn?
    let decode: DecodeFn?

    var isAvailable: Bool {
        encode != nil && decode != nil
    }

    init() {
        let candidates = ["liblzfse.so", "liblzfse.so.1", "liblzfse.so.0"]
        var loadedHandle: UnsafeMutableRawPointer? = nil

        for library in candidates {
            if let handle = dlopen(library, RTLD_LAZY | RTLD_LOCAL) {
                loadedHandle = handle
                break
            }
        }

        guard let loadedHandle else {
            self.handle = nil
            self.encode = nil
            self.decode = nil
            return
        }

        guard let encodeSymbol = dlsym(loadedHandle, "lzfse_encode_buffer"),
              let decodeSymbol = dlsym(loadedHandle, "lzfse_decode_buffer")
        else {
            dlclose(loadedHandle)
            self.handle = nil
            self.encode = nil
            self.decode = nil
            return
        }

        self.handle = loadedHandle
        self.encode = unsafeBitCast(encodeSymbol, to: EncodeFn.self)
        self.decode = unsafeBitCast(decodeSymbol, to: DecodeFn.self)
    }
}
#endif
