import Foundation

extension GameRuntime {
    /// The displays when MacGames last started Battle.net.
    var sessionDisplays: URL { paths.gameData.appendingPathComponent("session-displays") }

    /// `true` when the displays differ from the ones the running session started with. A client
    /// open from before MacGames recorded them counts as unchanged.
    func displaysChanged(clientRunning: Bool) -> Bool {
        guard let now = displaySignature() else { return false }
        guard let then = try? String(contentsOf: sessionDisplays, encoding: .utf8) else { return !clientRunning }
        return now != then
    }

    /// Runs before each new Battle.net session, as Recall does: the game's resolution goes into
    /// its settings and DXMT's canvas, and the graphics pipelines it learned are built ahead.
    /// Setup runs it without the pipelines, so the first session already has its display.
    func prepareOverwatch(pipelines: Bool = true) throws {
        let data = paths.gameData
        for folder in ["cache/shaders", "cache/pipelines"] {
            try fm.createDirectory(at: data.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let display = mainDisplay() ?? OverwatchDisplay.Size(width: 1920, height: 1200)
        let recordFile = OverwatchDisplay.record(paths)
        let record = try? JSONDecoder().decode(OverwatchDisplay.Record.self, from: Data(contentsOf: recordFile))
        let file = OverwatchDisplay.settingsFile(paths)
        let text = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let chosen = OverwatchDisplay.next(settings: text, record: record, display: display)
        let size = OverwatchDisplay.fitted(chosen, display: display)

        var canvas = size
        if let file, text != nil || !fm.fileExists(atPath: file.path) {
            do {
                let updated = try OverwatchDisplay.apply(to: text, size: size, seedBaseline: record == nil)
                if updated != text {
                    let backup = URL(fileURLWithPath: file.path + ".macgames-backup")
                    if text != nil, !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
                    try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try updated.write(to: file, atomically: true, encoding: .utf8)
                }
                let written = OverwatchDisplay.Record(chosen: chosen, wrote: size, gpu: OverwatchDisplay.gpu(updated))
                try JSONEncoder().encode(written).write(to: recordFile, options: .atomic)
            } catch {
                progress("\(error)")
                canvas = text.flatMap(OverwatchDisplay.gameResolution) ?? size
            }
        } else {
            progress("Overwatch's settings file could not be read, so its resolution was left as it is.")
            canvas = text.flatMap(OverwatchDisplay.gameResolution) ?? size
        }
        if size != chosen {
            progress("Overwatch opens at \(size.width)x\(size.height), the largest that fits this display.")
        }

        guard let profile = try? String(contentsOf: paths.engine.appendingPathComponent("config/dxmt.conf"), encoding: .utf8) else {
            throw SetupError("The Overwatch engine has no DXMT profile. Remove the setup of Overwatch, then set it up again.")
        }
        // The canvas must match the size the game opens at, or the game changes the display's mode.
        try OverwatchDisplay.canvas(profile, size: canvas).write(to: OverwatchDisplay.config(paths), atomically: true, encoding: .utf8)
        if pipelines { prepareRecallPipelines() }
    }

    /// Recall's tool builds the pipelines the game used before, costliest first, and warms the
    /// Metal cache of the engine's Game Mode app. A failure only costs stutter, so it never stops the launch.
    func prepareRecallPipelines() {
        guard let pack = paths.environment.enginePack else { return }
        let tool = paths.pack(pack).appendingPathComponent("Helpers/ow2-pipeline")
        guard fm.isExecutableFile(atPath: tool.path) else { return }
        let app = paths.engine.appendingPathComponent("lib/wine/game-mode/Overwatch.app")
        let arguments = [paths.gameData.path] + (fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) ? [app.path] : [])
        progress("Preparing Overwatch's graphics…")
        do {
            try runner.run(tool, arguments, timeout: 600)
        } catch {
            progress("Graphics preparation was skipped this time: \(error)")
        }
    }
}
