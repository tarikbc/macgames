import Foundation
import Testing
@testable import MacGamesCore

@Suite struct PresentationTests {
    @Test func artworkComesFromTheSteamAppID() {
        let art = GameProfile.cs2.artwork!
        #expect(art.hero.absoluteString == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/730/library_hero.jpg")
        #expect(art.logo.absoluteString.hasSuffix("/apps/730/logo.png"))
        #expect(art.portrait.absoluteString.hasSuffix("/apps/730/library_600x900.jpg"))
    }

    @Test func eachGameKeepsItsArtFocusAndAccent() {
        #expect(GameProfile.cs2.presentation.heroFocus.x > 0.7, "the CS2 figures stand on the right")
        #expect(GameProfile.aoe4.presentation.accentHex != GameProfile.cs2.presentation.accentHex)
    }

    @Test func gamesSteamDoesNotSellHaveNoArtwork() {
        #expect(GameProfile.diablo2Resurrected.artwork == nil)
    }

    @Test func defaultPresentationIsCentered() {
        let p = GameProfile.Presentation()
        #expect(p.heroFocus.x == 0.5 && p.heroFocus.y == 0.5)
    }

    @Test func setupStepsAreInOrder() {
        #expect(SetupStep.allCases.map(\.title) == ["Check this Mac", "Get libraries", "Install the Wine engine",
                                                      "Create Windows", "Configure graphics and controllers", "Install Steam"])
    }
}
