import Foundation
import Testing
@testable import MacGamesCore

@Suite struct DownloaderTests {
    let payload = "payload v1"
    var payloadSHA: String { sha256Hex(Data(payload.utf8)) }

    func source(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("source.bin")
        try write(payload, to: url)
        return url
    }

    @Test func reusesAVerifiedCachedFileWithoutFetching() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("cache")
        try write(payload, to: cache.appendingPathComponent("file.bin"))
        let item = Download(url: URL(string: "https://invalid.example/never")!, sha256: payloadSHA, fileName: "file.bin")
        let url = try Downloader(cache: cache).fetch(item)
        #expect(read(url) == payload)
    }

    @Test func replacesACachedFileWithTheWrongHash() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("cache")
        try write("stale", to: cache.appendingPathComponent("file.bin"))
        let item = Download(url: try source(in: dir), sha256: payloadSHA, fileName: "file.bin")
        #expect(read(try Downloader(cache: cache).fetch(item)) == payload)
    }

    @Test func rejectsADownloadWithTheWrongHash() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("cache")
        let item = Download(url: try source(in: dir), sha256: String(repeating: "a", count: 64), fileName: "file.bin")
        #expect(throws: SetupError.self) { try Downloader(cache: cache).fetch(item) }
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("file.bin").path))
    }

    @Test func unpinnedDownloadsAreAcceptedAndCached() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("cache")
        let item = Download(url: try source(in: dir), sha256: nil, fileName: "file.bin")
        #expect(read(try Downloader(cache: cache).fetch(item)) == payload)
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("file.bin").path))
    }

    @Test func knownDownloadsPointAtTheOfficialSources() {
        #expect(Download.template.url.absoluteString == "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz")
        #expect(Download.template.sha256 == "34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3")
        #expect(Download.steamSetup.url.absoluteString == "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")
        #expect(Download.steamSetup.sha256 == nil)
    }
}
