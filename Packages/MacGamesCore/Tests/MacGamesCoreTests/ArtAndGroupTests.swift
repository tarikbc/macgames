import Foundation
import Testing
@testable import MacGamesCore

@Suite struct StoreArtTests {
    static let sample = Data("""
    {"response":{"store_items":[
      {"appid":4921760,"assets":{"asset_url_format":"steam/apps/4921760/${FILENAME}?t=1790180698",
        "library_capsule":"b2e1/library_capsule.jpg","library_hero":"d3c5/library_hero.jpg"}},
      {"appid":730,"assets":{"asset_url_format":"steam/apps/730/${FILENAME}?t=1789251637",
        "library_capsule":"library_600x900.jpg","library_hero":"library_hero.jpg"}},
      {"appid":99,"success":2}
    ]}}
    """.utf8)

    @Test func newerAppsKeepTheirArtInHashedFolders() throws {
        let art = try #require(SteamStoreArt.parse(Self.sample)["4921760"])
        #expect(art.portrait.absoluteString == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/4921760/b2e1/library_capsule.jpg")
        #expect(art.hero.absoluteString == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/4921760/d3c5/library_hero.jpg")
        #expect(art.logo.absoluteString.hasSuffix("/apps/4921760/logo.png"), "the store does not list logos")
    }

    @Test func olderAppsResolveToTheFixedPaths() throws {
        let art = try #require(SteamStoreArt.parse(Self.sample)["730"])
        #expect(art == GameProfile.cs2.artwork, "the same URLs keep the image cache")
    }

    @Test func itemsWithoutAssetsAreLeftOut() {
        #expect(SteamStoreArt.parse(Self.sample)["99"] == nil)
        #expect(SteamStoreArt.parse(Data("not json".utf8)).isEmpty)
    }

    @Test func oneRequestAsksForEveryApp() throws {
        let url = SteamStoreArt.request(appIDs: ["730", "4921760"])
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "input_json" }?.value)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(query.utf8)) as? [String: Any])
        #expect((json["ids"] as? [[String: Int]])?.compactMap { $0["appid"] } == [730, 4921760])
        #expect((json["data_request"] as? [String: Bool])?["include_assets"] == true)
        #expect(url.host == "api.steampowered.com" && url.path() == "/IStoreBrowseService/GetItems/v1/")
    }

    @Test func resolvedArtWinsOverTheFixedPaths() throws {
        let resolved = SteamStoreArt.parse(Self.sample)
        #expect(GameProfile.heroes3.artwork(resolved: resolved)?.portrait.absoluteString.contains("/b2e1/") == true)
        #expect(GameProfile.aoe4.artwork(resolved: resolved) == GameProfile.aoe4.artwork)
    }

    @Test func diablo2UsesItsSteamArtButStaysOnBattleNet() {
        #expect(GameProfile.diablo2Resurrected.artwork != nil)
        #expect(GameProfile.diablo2Resurrected.launch == .battleNet)
    }

    @Test func gamesWithoutASteamPageHaveNoArtwork() {
        let profile = GameProfile(id: "x", title: "X", steamAppID: "", installFolder: "X", executableRelativePath: "x.exe")
        #expect(profile.artwork == nil)
        #expect(profile.artwork(resolved: ["": GameProfile.cs2.artwork!]) == nil)
    }
}

@Suite struct SidebarGroupTests {
    @Test func gtaVSitsWithTheOtherRockstarGames() throws {
        let rockstar = try #require(GameEnvironment.groups.first { $0.title == "Rockstar" })
        #expect(rockstar.games.map(\.id) == ["rdr2", "san-andreas-de", "gta5-enhanced"])
        #expect(!GameEnvironment.groups.contains { $0.title == "GTA V" })
    }

    @Test func groupsKeepEnvironmentOrderAndEveryGame() {
        #expect(GameEnvironment.groups.map(\.title) == ["Steam library", "Skyrim", "Overwatch", "Battle.net", "Rockstar"])
        #expect(GameEnvironment.groups.flatMap(\.games).count == GameProfile.all.count)
    }
}
