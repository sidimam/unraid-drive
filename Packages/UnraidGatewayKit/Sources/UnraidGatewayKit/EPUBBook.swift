import Foundation

/// Minimal EPUB reader: container.xml → OPF → spine → XHTML stripped to plain text, one chapter per
/// spine item. Good enough to read a novel on a TV; formatting and images are dropped.
public enum EPUBBook {
    public struct Chapter: Sendable { public let title: String; public let text: String }

    /// container.xml → OPF → manifest/spine → XHTML stripped to text.
    public static func parse(_ zip: ZipArchive) -> (title: String, chapters: [Chapter]) {
        guard let container = zip.read(named: "META-INF/container.xml").flatMap({ String(data: $0, encoding: .utf8) }),
              let opfPath = match(container, #"full-path="([^"]+)""#) else { return ("", []) }
        guard let opf = zip.read(named: opfPath).flatMap({ String(data: $0, encoding: .utf8) }) else { return ("", []) }
        let dir = (opfPath as NSString).deletingLastPathComponent
        let title = match(opf, #"<dc:title[^>]*>([^<]*)</dc:title>"#).map(decode) ?? ""
        var hrefs: [String: String] = [:]
        for item in matches(opf, #"<item\b[^>]*>"#) {
            if let id = match(item, #"\bid="([^"]+)""#), let href = match(item, #"\bhref="([^"]+)""#) { hrefs[id] = href }
        }
        var parts: [Chapter] = []
        for ref in matches(opf, #"<itemref\b[^>]*>"#) {
            guard let id = match(ref, #"idref="([^"]+)""#), let href = hrefs[id] else { continue }
            let path = dir.isEmpty ? href : (dir as NSString).appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let html = zip.read(named: path).flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
            let text = stripHTML(html)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                let t = match(html, #"<title[^>]*>([^<]*)</title>"#).map(decode) ?? href
                parts.append(Chapter(title: t, text: text))
            }
        }
        return (title, parts)
    }

    public static func stripHTML(_ html: String) -> String {
        var s = html
        for pattern in [#"<head\b[\s\S]*?</head>"#, #"<script\b[\s\S]*?</script>"#, #"<style\b[\s\S]*?</style>"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"</(p|div|h[1-6]|li|tr|blockquote|section|article)>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decode(s)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func decode(_ s: String) -> String {
        var t = s
        for (k, v) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–", "&laquo;": "«", "&raquo;": "»"] { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression) // rare numeric entities: drop
        return t
    }
    static func match(_ s: String, _ pattern: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let range = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[range])
    }
    static func matches(_ s: String, _ pattern: String) -> [String] {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return r.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

}
