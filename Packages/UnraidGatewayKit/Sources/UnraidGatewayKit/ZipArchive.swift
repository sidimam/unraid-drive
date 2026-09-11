import Foundation
import Compression

// MARK: - Minimal ZIP reader (stored + deflate), enough for EPUB, CBZ and plain archives

public struct ZipArchive: Sendable {
    public struct Entry: Sendable { public let name: String; public let method: UInt16; public let compressedSize: Int; public let size: Int; public let offset: Int }
    public let data: Data
    public let entries: [Entry]

    public init?(data: Data) {
        self.data = data
        guard data.count > 22 else { return nil }
        // End of central directory: scan the last 66 KB for its signature.
        let tail = max(0, data.count - 66_000)
        var eocd = -1
        var i = data.count - 22
        while i >= tail { if data.u32(i) == 0x06054b50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { return nil }
        let count = Int(data.u16(eocd + 10)), cdOffset = Int(data.u32(eocd + 16))
        var list: [Entry] = []; var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x02014b50 else { break }
            let method = data.u16(p + 10), csize = Int(data.u32(p + 20)), usize = Int(data.u32(p + 24))
            let n = Int(data.u16(p + 28)), x = Int(data.u16(p + 30)), c = Int(data.u16(p + 32)), off = Int(data.u32(p + 42))
            let name = String(data: data.subdata(in: (p + 46)..<(p + 46 + n)), encoding: .utf8) ?? ""
            list.append(Entry(name: name, method: method, compressedSize: csize, size: usize, offset: off))
            p += 46 + n + x + c
        }
        entries = list
    }

    public func read(_ e: Entry) -> Data? {
        guard e.offset + 30 <= data.count, data.u32(e.offset) == 0x04034b50 else { return nil }
        let n = Int(data.u16(e.offset + 26)), x = Int(data.u16(e.offset + 28))
        let start = e.offset + 30 + n + x
        guard start + e.compressedSize <= data.count else { return nil }
        let comp = data.subdata(in: start..<(start + e.compressedSize))
        if e.method == 0 { return comp }
        guard e.method == 8, e.size > 0 else { return nil }
        var out = Data(count: e.size)
        let written = out.withUnsafeMutableBytes { dst in
            comp.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size, src.bindMemory(to: UInt8.self).baseAddress!, comp.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == e.size ? out : nil
    }
    public func read(named name: String) -> Data? { entries.first { $0.name == name }.flatMap(read) }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}

