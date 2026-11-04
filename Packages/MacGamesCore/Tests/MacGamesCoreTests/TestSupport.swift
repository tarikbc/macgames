import Foundation

/// A fresh temporary folder, removed by the caller.
func makeTempDir(_ name: String = "mg") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

/// Builds the headers of a PE file: DOS stub, COFF header, optional header and section table.
enum PEFixture {
    struct Section { let name: String; let virtualAddress: UInt32; let virtualSize: UInt32 }

    static func data(machine: UInt16 = 0x8664, magic: UInt16 = 0x20b, imageBase: UInt64 = 0x140000000,
                     sections: [Section]) -> Data {
        var d = Data(count: 0x80)
        d[0] = 0x4d; d[1] = 0x5a
        put(UInt32(0x80), at: 0x3c, in: &d)
        d.append(contentsOf: Array("PE".utf8) + [0, 0])
        let optionalSize = 0xf0
        var coff = Data(count: 20)
        put(machine, at: 0, in: &coff)
        put(UInt16(sections.count), at: 2, in: &coff)
        put(UInt16(optionalSize), at: 16, in: &coff)
        d.append(coff)
        var optional = Data(count: optionalSize)
        put(magic, at: 0, in: &optional)
        put(imageBase, at: 24, in: &optional)
        d.append(optional)
        for section in sections {
            var entry = Data(count: 40)
            for (i, byte) in section.name.utf8.prefix(8).enumerated() { entry[i] = byte }
            put(section.virtualSize, at: 8, in: &entry)
            put(section.virtualAddress, at: 12, in: &entry)
            d.append(entry)
        }
        return d
    }

    static func aoe4(textSize: UInt32, textAddress: UInt32 = 0x1000) -> Data {
        data(sections: [.init(name: ".text", virtualAddress: textAddress, virtualSize: textSize),
                        .init(name: ".rdata", virtualAddress: 0x5810000, virtualSize: 0x1ecacf6)])
    }

    static func put<T: FixedWidthInteger>(_ value: T, at offset: Int, in data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset..<offset + MemoryLayout<T>.size, with: $0) }
    }
}
