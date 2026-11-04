import Foundation

/// The code section of a 64-bit Windows executable, read from its PE headers.
///
/// The x87sidecar software-fault hook covers a fixed address range. That range is the
/// only part of the optimization that changes between game builds, and it follows from
/// the `.text` section, so each build's range can be read from the exe itself.
public struct GameImage: Equatable, Sendable {
    public let imageBase: UInt64
    /// Absolute start and end (start + VirtualSize) of the `.text` section.
    public let textStart: UInt64
    public let textEnd: UInt64

    /// Runtime 4's rule; reproduces both builds tested in game.
    public static let softfaultTailMargin: UInt64 = 0x500
    /// x87sidecar installs no decode hook for a longer range.
    public static let maximumSoftfaultRange: UInt64 = 0x6000000

    public init(imageBase: UInt64, textStart: UInt64, textEnd: UInt64) {
        self.imageBase = imageBase; self.textStart = textStart; self.textEnd = textEnd
    }

    /// The range end for a hook that starts at `start`; nil when the image does not fit.
    public func softfaultEnd(start: UInt64) -> UInt64? {
        guard textStart == start, textEnd > Self.softfaultTailMargin else { return nil }
        let end = textEnd - Self.softfaultTailMargin
        guard end > start, end - start <= Self.maximumSoftfaultRange else { return nil }
        return end
    }

    /// Reads the first 64 KiB of the file and parses it.
    public static func read(atPath path: String) throws -> GameImage? {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return parse(try handle.read(upToCount: 1 << 16) ?? Data())
    }

    public static func parse(_ header: Data) -> GameImage? {
        let bytes = [UInt8](header)
        func read<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
            let size = MemoryLayout<T>.size
            guard offset >= 0, offset <= bytes.count - size else { return nil }
            return bytes[offset..<offset + size].reversed().reduce(T(0)) { $0 << 8 | T($1) }
        }
        guard bytes.starts(with: [0x4d, 0x5a]), let peOffset = read(UInt32.self, at: 0x3c).map(Int.init),
              read(UInt32.self, at: peOffset) == 0x0000_4550 else { return nil }
        let coff = peOffset + 4
        guard read(UInt16.self, at: coff) == 0x8664,
              let sectionCount = read(UInt16.self, at: coff + 2),
              let optionalSize = read(UInt16.self, at: coff + 16) else { return nil }
        let optional = coff + 20
        guard read(UInt16.self, at: optional) == 0x20b, let imageBase = read(UInt64.self, at: optional + 24) else { return nil }
        let table = optional + Int(optionalSize)
        for index in 0..<Int(sectionCount) {
            let entry = table + index * 40
            guard entry + 40 <= bytes.count else { return nil }
            let name = bytes[entry..<entry + 8].prefix { $0 != 0 }
            guard Array(name) == Array(".text".utf8) else { continue }
            guard let size = read(UInt32.self, at: entry + 8), let address = read(UInt32.self, at: entry + 12) else { return nil }
            let (start, overflow) = imageBase.addingReportingOverflow(UInt64(address))
            guard !overflow, start <= UInt64.max - UInt64(size) else { return nil }
            return GameImage(imageBase: imageBase, textStart: start, textEnd: start + UInt64(size))
        }
        return nil
    }
}
