import Foundation

/// Small, format-preserving edits to Windows INI files. Line endings, other
/// sections and comments stay as they are.
public enum INIFile {
    /// Sets `key` in `section` (`nil` for keys before any section). With
    /// `onlyIfMissing`, an existing value is kept.
    public static func set(in text: String, section: String?, key: String, value: String,
                           onlyIfMissing: Bool = false, separator: String = "=") -> String {
        // New lines use the file's main line ending; existing lines keep their own.
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = split(text)
        let entry = key + separator + value

        var start = section == nil ? 0 : nil
        var end = lines.count
        for (i, line) in lines.enumerated() {
            guard let name = header(line.body) else { continue }
            if start != nil { end = i; break }
            if let section, name.caseInsensitiveCompare(section) == .orderedSame { start = i + 1 }
            else if section == nil { end = i; break }
        }
        guard let first = start else {
            if let last = lines.indices.last, lines[last].end.isEmpty { lines[last].end = newline }
            if let last = lines.last, !clean(last.body).isEmpty { lines.append(Line(body: "", end: newline)) }
            lines += [Line(body: "[\(section!)]", end: newline), Line(body: entry, end: newline)]
            return join(lines)
        }
        for i in first..<end where name(of: lines[i].body)?.caseInsensitiveCompare(key) == .orderedSame {
            if !onlyIfMissing { lines[i].body = (lines[i].body.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : "") + entry }
            return join(lines)
        }
        // Insert after the section's last non-blank line.
        var at = end
        while at > first, clean(lines[at - 1].body).isEmpty { at -= 1 }
        if at > 0, lines[at - 1].end.isEmpty { lines[at - 1].end = newline }
        lines.insert(Line(body: entry, end: newline), at: at)
        return join(lines)
    }

    struct Line { var body: String; var end: String }

    /// Lines with their own endings: CRLF, LF or CR. The last line may have none.
    static func split(_ text: String) -> [Line] {
        var lines: [Line] = [], body = ""
        for c in text {
            switch c {
            case "\r\n", "\n", "\r": lines.append(Line(body: body, end: String(c))); body = ""
            default: body.append(c)
            }
        }
        if !body.isEmpty { lines.append(Line(body: body, end: "")) }
        return lines
    }

    static func join(_ lines: [Line]) -> String { lines.map { $0.body + $0.end }.joined() }

    /// The line without a byte order mark and surrounding spaces.
    static func clean(_ line: String) -> String {
        (line.hasPrefix("\u{FEFF}") ? String(line.dropFirst()) : line).trimmingCharacters(in: .whitespaces)
    }

    /// The section name of a header line such as `[Video]` or `[Video] ; comment`.
    static func header(_ line: String) -> String? {
        let t = clean(line)
        guard t.hasPrefix("["), let close = t.firstIndex(of: "]") else { return nil }
        let rest = t[t.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.hasPrefix(";") || rest.hasPrefix("#") else { return nil }
        return t[t.index(after: t.startIndex)..<close].trimmingCharacters(in: .whitespaces)
    }

    /// The key of a `key=value` line.
    static func name(of line: String) -> String? {
        clean(line).split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
