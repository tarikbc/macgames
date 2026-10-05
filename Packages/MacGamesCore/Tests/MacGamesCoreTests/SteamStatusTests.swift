import Foundation
import Testing
@testable import MacGamesCore

@Suite struct SteamAccountTests {
    let vdf = """
    "users"
    {
    \t"76561197960287930"
    \t{
    \t\t"AccountName"\t\t"oldlogin"
    \t\t"PersonaName"\t\t"Old Name"
    \t\t"MostRecent"\t\t"0"
    \t}
    \t"76561198000000001"
    \t{
    \t\t"AccountName"\t\t"mylogin"
    \t\t"PersonaName"\t\t"tarikbc"
    \t\t"MostRecent"\t\t"1"
    \t}
    }
    """

    @Test func mostRecentUserWins() {
        #expect(SteamAccount.parse(vdf)?.personaName == "tarikbc")
    }

    @Test func singleUserWithoutMostRecentIsUsed() {
        let one = vdf.replacingOccurrences(of: "\"MostRecent\"\t\t\"1\"", with: "\"MostRecent\"\t\t\"0\"")
        #expect(SteamAccount.parse(one)?.personaName != nil)
    }

    @Test func emptyFileHasNoAccount() {
        #expect(SteamAccount.parse("\"users\"\n{\n}\n") == nil)
    }
}

@Suite struct DownloadProgressTests {
    func manifest(flags: String, done: String, total: String) -> AppManifest {
        AppManifest(text: "\"AppState\"\n{\n\t\"appid\"\t\t\"730\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"installdir\"\t\t\"Counter-Strike Global Offensive\"\n\t\"BytesDownloaded\"\t\t\"\(done)\"\n\t\"BytesToDownload\"\t\t\"\(total)\"\n}\n")
    }

    @Test func runningDownloadReportsItsFraction() {
        let p = manifest(flags: "1026", done: "15418601840", total: "61674407360").downloadProgress
        #expect(p != nil)
        #expect(abs((p ?? 0) - 0.25) < 0.0001)
    }

    @Test func finishedInstallHasNoDownload() {
        #expect(manifest(flags: "4", done: "61674407360", total: "61674407360").downloadProgress == nil)
    }

    @Test func queuedInstallWithoutBytesIsZero() {
        #expect(manifest(flags: "2", done: "0", total: "0").downloadProgress == 0)
    }
}

@Suite struct StagedProgressTests {
    func manifest(flags: String = "1026", done: String = "100658080", toDownload: String = "61674407360", toStage: String = "74087233962") -> AppManifest {
        AppManifest(text: "\"AppState\"\n{\n\t\"appid\"\t\t\"730\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"BytesDownloaded\"\t\t\"\(done)\"\n\t\"BytesToDownload\"\t\t\"\(toDownload)\"\n\t\"BytesToStage\"\t\t\"\(toStage)\"\n}\n")
    }

    @Test func bytesWrittenToTheStagingFolderShowLiveProgress() {
        // Steam rewrites the manifest's byte counters rarely; the staging folder grows live.
        let p = manifest().downloadProgress(stagedBytes: 74087233962 / 4)
        #expect(abs((p ?? 0) - 0.25) < 0.001)
    }

    @Test func aFresherManifestWins() {
        let p = manifest(done: "46255805520").downloadProgress(stagedBytes: 1_000_000)
        #expect(abs((p ?? 0) - 0.75) < 0.001)
    }

    @Test func progressNeverPassesOne() {
        #expect(manifest().downloadProgress(stagedBytes: 90_000_000_000) == 1)
    }

    @Test func stagedBytesCountWhatIsOnDisk() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 300_000).write(to: dir.appendingPathComponent("a.vpk"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 200_000).write(to: dir.appendingPathComponent("sub/b.vpk"))
        // A reserved but unwritten file takes no space on APFS.
        let sparse = try FileHandle(forWritingTo: { let u = dir.appendingPathComponent("sparse.vpk"); FileManager.default.createFile(atPath: u.path, contents: nil); return u }())
        try sparse.truncate(atOffset: 50_000_000); try sparse.close()
        let bytes = AppManifest.stagedBytes(in: dir)
        #expect(bytes >= 500_000 && bytes < 2_000_000)
        #expect(AppManifest.stagedBytes(in: dir.appendingPathComponent("missing")) == 0)
    }
}
