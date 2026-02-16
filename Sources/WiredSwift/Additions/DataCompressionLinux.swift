#if os(Linux)
import Foundation
import CZlib
import CLZ4
import CLZFSE

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

        let sourceCount = input.count
        let maxCompressedSize = Int(LZ4_compressBound(Int32(sourceCount)))
        guard maxCompressedSize > 0 else { return nil }

        var destination = [UInt8](repeating: 0, count: maxCompressedSize)

        return input.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: CChar.self)
            guard let sourcePtr = source.baseAddress else { return nil }
            let written = destination.withUnsafeMutableBufferPointer { outBuffer in
                LZ4_compress_default(sourcePtr,
                                     outBuffer.baseAddress,
                                     Int32(sourceCount),
                                     Int32(maxCompressedSize))
            }
            guard written > 0 else { return nil }
            return Data(destination.prefix(Int(written)))
        }
    }

    static func lz4Decompress(_ input: Data) -> Data? {
        if input.isEmpty {
            return Data()
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

            if let decodedCount, decodedCount >= 0 {
                return Data(destination.prefix(Int(decodedCount)))
            }

            destinationCapacity *= 2
        }

        return nil
    }

    static func lzfseCompress(_ input: Data) -> Data? {
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
                    Int(lzfse_encode_buffer(outBuffer.baseAddress,
                                            destinationCapacity,
                                            sourcePtr,
                                            input.count,
                                            nil))
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
                    Int(lzfse_decode_buffer(outBuffer.baseAddress,
                                            destinationCapacity,
                                            sourcePtr,
                                            input.count,
                                            nil))
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
#endif
