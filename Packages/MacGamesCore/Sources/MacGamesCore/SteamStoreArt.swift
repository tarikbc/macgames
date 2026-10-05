import Foundation

/// Finds where Steam keeps each app's library art.
///
/// Older apps keep it at fixed paths (`library_600x900.jpg`), but newer ones put it in
/// hashed folders that only the store API lists. The API does not list logos, so the
/// logo stays at its fixed path and may not exist.
public enum SteamStoreArt {
    static let cdn = "https://shared.akamai.steamstatic.com/store_item_assets/"

    /// One store request for the art of all the given apps.
    public static func request(appIDs: [String]) -> URL {
        let input: [String: Any] = [
            "ids": appIDs.compactMap(Int.init).map { ["appid": $0] },
            "context": ["language": "english", "country_code": "US"],
            "data_request": ["include_assets": true],
        ]
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: input, options: .sortedKeys), as: UTF8.self)
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/")!
        components.queryItems = [URLQueryItem(name: "input_json", value: json)]
        return components.url!
    }

    /// Art per Steam app ID from a store reply; apps without library art are left out.
    public static func parse(_ data: Data) -> [String: GameProfile.Artwork] {
        struct Reply: Decodable {
            struct Response: Decodable { let store_items: [Item]? }
            struct Item: Decodable { let appid: Int; let assets: Assets? }
            struct Assets: Decodable { let asset_url_format: String?; let library_capsule: String?; let library_hero: String? }
            let response: Response
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return [:] }
        var art: [String: GameProfile.Artwork] = [:]
        for item in reply.response.store_items ?? [] {
            guard let assets = item.assets, let format = assets.asset_url_format,
                  let capsule = assets.library_capsule, let hero = assets.library_hero else { continue }
            // The `?t=` stamp only busts caches; the hashed folder already names the image.
            let path = { (file: String) in URL(string: cdn + format.replacingOccurrences(of: "${FILENAME}", with: file)
                .components(separatedBy: "?")[0]) }
            guard let portrait = path(capsule), let heroURL = path(hero), let logo = path("logo.png") else { continue }
            art[String(item.appid)] = GameProfile.Artwork(hero: heroURL, logo: logo, portrait: portrait)
        }
        return art
    }
}
