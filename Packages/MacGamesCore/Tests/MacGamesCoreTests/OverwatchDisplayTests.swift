import Foundation
import Testing
@testable import MacGamesCore

@Suite struct OverwatchDisplayTests {
    typealias D = OverwatchDisplay
    typealias Size = OverwatchDisplay.Size
    let macBook = Size(width: 1512, height: 982)
    let wide = Size(width: 2560, height: 1440)

    static let played = """
    [GPU.6]\r
    GPUName = "Apple M3 Max"\r
    GPUVenderID = "4203"\r
    [Render.13]\r
    FullScreenHeight = "1440"\r
    FullScreenWidth = "2560"\r
    MouseSensitivity = "7.5"\r
    [Sound.3]\r
    MasterVolume = "80"\r

    """

    @Test func readsAQuotedSettingFromItsSection() {
        #expect(D.setting(Self.played, section: "[Render.", key: "FullScreenWidth") == "2560")
        #expect(D.setting(Self.played, section: "[Render.", key: "MasterVolume") == nil)
        #expect(D.gpu(Self.played) == "Apple M3 Max|4203")
        #expect(D.gpu("[Render.13]\n") == "")
    }

    @Test func aNewDisplayStartsAt1080pInItsShape() {
        #expect(D.screenDefault(display: macBook) == Size(width: 1920, height: 1200))
        #expect(D.screenDefault(display: wide) == Size(width: 1920, height: 1080))
    }

    @Test func theFirstLaunchTakesTheGamesOwnChoiceOrTheDefault() {
        #expect(D.next(settings: nil, record: nil, display: macBook) == Size(width: 1920, height: 1200))
        #expect(D.next(settings: Self.played, record: nil, display: macBook) == Size(width: 2560, height: 1440))
    }

    @Test func aResolutionChosenInTheGameIsKept() {
        let record = D.Record(chosen: Size(width: 1920, height: 1200), wrote: Size(width: 1920, height: 1200), gpu: "Apple M3 Max|4203")
        #expect(D.next(settings: Self.played, record: record, display: macBook) == Size(width: 2560, height: 1440))
    }

    @Test func theGamesOwnResetForANewCardIsSetAside() {
        let record = D.Record(chosen: Size(width: 1920, height: 1200), wrote: Size(width: 1920, height: 1200), gpu: "")
        #expect(D.next(settings: Self.played, record: record, display: macBook) == Size(width: 1920, height: 1200))
    }

    @Test func aLargerChoiceSurvivesALaunchOnASmallerDisplay() {
        // 4K was lowered to fit a MacBook; the game still shows what MacGames wrote, so the choice stays.
        let record = D.Record(chosen: Size(width: 3840, height: 2400), wrote: Size(width: 2560, height: 1600), gpu: "Apple M3 Max|4203")
        let settings = Self.played.replacingOccurrences(of: "\"1440\"", with: "\"1600\"")
        #expect(D.next(settings: settings, record: record, display: macBook) == Size(width: 3840, height: 2400))
    }

    @Test func aResolutionThatDoesNotFitIsLoweredToTheLargestOfItsShape() {
        #expect(D.fitted(Size(width: 3840, height: 2400), display: macBook) == Size(width: 2560, height: 1600))
        #expect(D.fitted(Size(width: 3840, height: 2160), display: Size(width: 1920, height: 1080)) == Size(width: 3840, height: 2160))
        #expect(D.fitted(Size(width: 5120, height: 2160), display: Size(width: 1440, height: 900)) == Size(width: 2560, height: 1600))
        #expect(D.fitted(Size(width: 1920, height: 1200), display: macBook) == Size(width: 1920, height: 1200))
    }

    @Test func launchValuesGoIntoTheRenderSectionInTheFilesOwnStyle() throws {
        let out = try D.apply(to: Self.played, size: Size(width: 1920, height: 1200), seedBaseline: false)
        #expect(out.contains("FullScreenWidth = \"1920\"\r\n"))
        #expect(out.contains("FullScreenHeight = \"1200\"\r\n"))
        #expect(out.contains("WindowedWidth = \"1920\"\r\n"))
        #expect(out.contains("DynamicRenderScale = \"0\"\r\n"))
        #expect(out.contains("MouseSensitivity = \"7.5\"\r\n"), "other settings stay")
        #expect(!out.contains("FrameRateCap"), "no baseline after the first launch")
        let render = try #require(out.range(of: "[Render.13]")), sound = try #require(out.range(of: "[Sound.3]"))
        let width = try #require(out.range(of: "WindowedWidth"))
        #expect(render.upperBound < width.lowerBound && width.upperBound < sound.lowerBound)
        #expect(D.setting(out, section: "[Render.", key: "FullScreenWidth") == "1920")
    }

    @Test func theFirstLaunchSeedsOnlyTheMissingBaseline() throws {
        let mine = Self.played.replacingOccurrences(of: "MouseSensitivity = \"7.5\"", with: "FrameRateCap = \"144\"")
        let out = try D.apply(to: mine, size: Size(width: 1920, height: 1200), seedBaseline: true)
        #expect(D.setting(out, section: "[Render.", key: "FrameRateCap") == "144")
        #expect(D.setting(out, section: "[Render.", key: "GFXPresetLevel") == "1")
        #expect(D.setting(out, section: "[Render.", key: "VerticalSyncEnabled") == "0")
    }

    @Test func aMissingFileOrSectionGetsOne() throws {
        let fresh = try D.apply(to: nil, size: Size(width: 1920, height: 1080), seedBaseline: true)
        #expect(fresh.hasPrefix("[Render.13]\n"))
        #expect(D.setting(fresh, section: "[Render.", key: "FullScreenHeight") == "1080")
        let other = try D.apply(to: "[Sound.3]\nMasterVolume = \"80\"\n", size: Size(width: 1920, height: 1080), seedBaseline: false)
        #expect(other.hasPrefix("[Sound.3]\nMasterVolume = \"80\"\n"))
        #expect(D.setting(other, section: "[Render.", key: "FullScreenWidth") == "1920")
    }

    @Test func aByteOrderMarkStays() throws {
        let out = try D.apply(to: "\u{FEFF}[Render.13]\nFullScreenWidth = \"2560\"\n", size: Size(width: 1920, height: 1080), seedBaseline: false)
        #expect(out.hasPrefix("\u{FEFF}[Render.13]\n"))
        #expect(out.components(separatedBy: "[Render.13]").count == 2)
    }

    @Test func aFileWithTwoRenderSectionsIsLeftAlone() {
        #expect(throws: SetupError.self) {
            try D.apply(to: "[Render.13]\nA = \"1\"\n[Render.13]\nB = \"2\"\n", size: Size(width: 1920, height: 1080), seedBaseline: false)
        }
    }

    @Test func theCanvasTakesTheGamesSizeUnderItsExactKeys() throws {
        let profile = "[Overwatch.exe]\nd3d11.releaseShaderIR = True\ndxgi.fullscreenCanvasWidth = 1920\ndxgi.fullscreenCanvasHeight = 1200\n"
        let out = try D.canvas(profile, size: Size(width: 2560, height: 1440))
        #expect(out == "[Overwatch.exe]\nd3d11.releaseShaderIR = True\ndxgi.fullscreenCanvasWidth = 2560\ndxgi.fullscreenCanvasHeight = 1440\n")
        #expect(throws: SetupError.self) { try D.canvas("dxgi.fullScreenCanvasWidth = 1\n", size: Size(width: 1, height: 1)) }
    }
}
