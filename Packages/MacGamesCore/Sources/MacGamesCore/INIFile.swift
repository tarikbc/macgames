import Foundation

/// Small, format-preserving edits to Windows INI files. Line endings, other
/// sections and comments stay as they are.
public enum INIFile {
    /// Sets `key` in `section` (`nil` for keys before any section). With
    /// `onlyIfMissing`, an existing value is kept.
    public static func set(in text: String, section: String?, key: String, value: String,
                           onlyIfMissing: Bool = false, separator: String = "=") -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.isEmpty ? [] : text.components(separatedBy: newline)
        if lines.last == "" { lines.removeLast() }
        let entry = key + separator + value

        var start = section == nil ? 0 : nil
        var end = lines.count
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("["), t.hasSuffix("]") else { continue }
            if start != nil { end = i; break }
            if let section, t.dropFirst().dropLast().caseInsensitiveCompare(section) == .orderedSame { start = i + 1 }
            else if section == nil { end = i; break }
        }
        guard let first = start else {
            var out = lines
            if !out.isEmpty, out.last?.isEmpty == false { out.append("") }
            out += ["[\(section!)]", entry]
            return out.joined(separator: newline) + newline
        }
        for i in first..<end {
            let name = lines[i].split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
            if name?.caseInsensitiveCompare(key) == .orderedSame {
                if !onlyIfMissing { lines[i] = entry }
                return lines.joined(separator: newline) + newline
            }
        }
        // Insert after the section's last non-blank line.
        var at = end
        while at > first, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        lines.insert(entry, at: at)
        return lines.joined(separator: newline) + newline
    }
}
