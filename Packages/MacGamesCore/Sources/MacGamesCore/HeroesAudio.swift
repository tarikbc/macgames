import CryptoKit
import Foundation

/// Heroes III's Miles sound library asks for a wave format that macOS audio
/// rejects, so music and sound stay silent. These instructions set up a plain
/// PCM format (2 channels, 44100 Hz, 16-bit) in its WAVEFORMATEX instead.
public enum HeroesAudio {
    public static let originalSHA = "09e2dec3d1e996571fb2c95e5de393410d486f1728c86473b550282edd83588c"
    public static let fixedSHA = "57191b1e7a07df187ee4aff128c0f522d1ac11a7657ebe7e4f40d3b5f99b23c8"
    static let range = 0xe39e..<0xe3d6

    /// x86: store wFormatTag=1, nChannels=2, nSamplesPerSec=44100,
    /// nAvgBytesPerSec=176400, nBlockAlign=4, wBitsPerSample=16 at [EBX], then NOP padding.
    public static let formatCode: [UInt8] = [
        0x66, 0xb8, 0x01, 0x00, 0x66, 0x89, 0x03,
        0x66, 0xb8, 0x02, 0x00, 0x66, 0x89, 0x43, 0x02,
        0xb8, 0x44, 0xac, 0x00, 0x00, 0x89, 0x43, 0x04,
        0xc1, 0xe0, 0x02, 0x89, 0x43, 0x08,
        0x66, 0xb8, 0x04, 0x00, 0x66, 0x89, 0x43, 0x0c,
        0x66, 0xb8, 0x10, 0x00, 0x66, 0x89, 0x43, 0x0e,
    ] + Array(repeating: 0x90, count: 11)

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Returns the repaired library. Only the known original build is changed.
    public static func repair(_ original: Data, originalSHA: String? = HeroesAudio.originalSHA,
                              fixedSHA: String? = HeroesAudio.fixedSHA) throws -> Data {
        if let fixedSHA, sha(original) == fixedSHA { return original }
        if let originalSHA, sha(original) != originalSHA {
            throw SetupError("This Heroes III sound library is a build MacGames does not know, so it was left unchanged.")
        }
        guard original.count >= range.upperBound else { throw SetupError("The Heroes III sound library is too small.") }
        var fixed = original
        fixed.replaceSubrange(range, with: formatCode)
        if let fixedSHA, sha(fixed) != fixedSHA { throw SetupError("The Heroes III sound repair did not verify, so nothing was changed.") }
        return fixed
    }
}
