import Foundation
import Testing
import BridgeKit
@testable import MacGamesCore

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
