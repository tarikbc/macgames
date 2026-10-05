import Foundation
import Testing
@testable import MacGamesCore

@Suite struct CabinetScannerTests {
    func cab(size: Int, fill: UInt8) -> Data {
        var d = Data([0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0])
        d.append(contentsOf: withUnsafeBytes(of: UInt32(size).littleEndian, Array.init))
        d.append(Data(repeating: fill, count: size - d.count))
        return d
    }

    @Test func findsEachEmbeddedCabinetWithItsDeclaredSize() {
        var exe = Data(repeating: 0x90, count: 100)
        exe.append(cab(size: 64, fill: 1))
        exe.append(Data(repeating: 0x90, count: 30))
        exe.append(cab(size: 80, fill: 2))
        let found = CabinetScanner.cabinets(in: exe)
        #expect(found.map(\.count) == [64, 80])
        #expect(found[1].last == 2)
    }

    @Test func ignoresAMagicWithAnImpossibleSize() {
        var exe = Data([0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x7F])
        exe.append(Data(repeating: 0, count: 40))
        #expect(CabinetScanner.cabinets(in: exe).isEmpty)
    }
}

@Suite struct DirectLaunchTests {
    @Test func heroesStartsFromItsOwnFolder() {
        #expect(GameRuntime.heroesScript(installDir: #"C:\Games\Heroes"#) == "@echo off\r\ncd /d \"C:\\Games\\Heroes\"\r\nHeroes3.exe\r\n")
    }

    @Test func eachEnvironmentListsOnlyItsGames() {
        #expect(GameEnvironment.steam.games.count == 13)
        #expect(GameEnvironment.all.flatMap(\.games).count == GameProfile.all.count)
        #expect(GameEnvironment.all.allSatisfy { !$0.games.isEmpty })
    }
}
