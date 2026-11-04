import Foundation
import Testing
import BridgeKit
@testable import MacGamesCore

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

@Suite struct GameImageTests {
    @Test func parsesTheTextSectionOfAnX64Image() {
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x580d95c))
                == GameImage(imageBase: 0x140000000, textStart: 0x140001000, textEnd: 0x14580e95c))
    }

    @Test func softfaultEndKeepsRuntime4sRule() {
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x56dcfdc))?.softfaultEnd(start: 0x140001000) == 0x1456ddadc)
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x580d95c))?.softfaultEnd(start: 0x140001000) == 0x14580e45c)
    }

    @Test func softfaultEndRejectsAnotherStart() {
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x580d95c))?.softfaultEnd(start: 0x140002000) == nil)
    }

    @Test func softfaultEndRejectsAnOversizedText() {
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x6000501))?.softfaultEnd(start: 0x140001000) == nil)
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x6000500))?.softfaultEnd(start: 0x140001000) == 0x146001000)
    }

    @Test func notAPEFileHasNoImage() {
        #expect(GameImage.parse(Data()) == nil)
        #expect(GameImage.parse(Data("MZ".utf8)) == nil)
        #expect(GameImage.parse(PEFixture.aoe4(textSize: 0x580d95c).prefix(100)) == nil)
    }

    @Test func thirtyTwoBitImageHasNoImage() {
        let text = PEFixture.Section(name: ".text", virtualAddress: 0x1000, virtualSize: 0x1000)
        #expect(GameImage.parse(PEFixture.data(magic: 0x10b, sections: [text])) == nil)
        #expect(GameImage.parse(PEFixture.data(machine: 0x14c, sections: [text])) == nil)
    }

    @Test func imageWithoutTextHasNoImage() {
        #expect(GameImage.parse(PEFixture.data(sections: [.init(name: ".rdata", virtualAddress: 0x1000, virtualSize: 0x1000)])) == nil)
    }

    /// The two builds played in game; run with AOE4_EXES="<exe>:<exe>".
    static let testedEnds: [String: UInt64] = [
        "5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c": 0x1456ddadc,
        "4c99b868cbec98b2219e135908a31d03c64c7b71f2bbcf1469dab1d7c6df2c9f": 0x14580e45c,
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AOE4_EXES"] != nil))
    func realBuildsMatchTheirTestedRangeEnd() throws {
        for path in (ProcessInfo.processInfo.environment["AOE4_EXES"] ?? "").split(separator: ":").map(String.init) {
            let sha = try sha256Hex(ofFileAt: URL(fileURLWithPath: path))
            guard let expected = Self.testedEnds[sha] else { Issue.record("\(path) is not a tested build (\(sha))"); continue }
            #expect(try GameImage.read(atPath: path)?.softfaultEnd(start: 0x140001000) == expected, "\(path)")
        }
    }
}
