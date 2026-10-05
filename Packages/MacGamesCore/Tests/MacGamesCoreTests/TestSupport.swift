import Foundation

/// A fresh temporary folder, removed by the caller.
func makeTempDir(_ name: String = "mg") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
