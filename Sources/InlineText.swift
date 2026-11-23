import AppKit

// Compact inline style changes inside existing string fields. Plain strings remain plain.
// Each marker sets the full style mask, so nested emphasis has no ordering ambiguity.
struct InlineText {
    struct Run {
        let text: String
        let mask: Int
    }
    static let marker = "\u{E000}"
    static func runs(_ source: String) -> [Run] {
        guard source.contains(marker) else { return [Run(text: source, mask: 0)] }
        var result = [Run](), buffer = "", mask = 0
        var iterator = source.makeIterator()
        while let ch = iterator.next() {
            if String(ch) == marker, let next = iterator.next() {
                if let n = next.wholeNumberValue, n < 8 {
                    if !buffer.isEmpty { result.append(Run(text: buffer, mask: mask)); buffer = "" }
                    mask = n
                } else {
                    buffer += marker
                    if String(next) != marker { buffer.append(next) }
                }
            } else { buffer.append(ch) }
        }
        if !buffer.isEmpty { result.append(Run(text: buffer, mask: mask)) }
        return result
    }
    static func encode(_ runs: [Run]) -> String {
        var output = "", mask = 0
        for run in runs where !run.text.isEmpty {
            if run.mask != mask { mask = run.mask; output += marker + String(mask) }
            output += run.text.replacingOccurrences(of: marker, with: marker + marker)
        }
        if mask != 0 { output += marker + "0" }
        return output
    }
    static func lines(_ source: String) -> [String] {
        let styled = attributed(source, attributes: [:])
        var offset = 0
        return styled.string.components(separatedBy: .newlines).map { line in
            let length = (line as NSString).length
            defer { offset += length + 1 }
            return stored(styled.attributedSubstring(from: NSRange(location: offset, length: length)))
        }
    }
    static func attributed(_ source: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs(source) {
            var attrs = attributes
            var font = attrs[.font] as? NSFont ?? .systemFont(ofSize: 13)
            let manager = NSFontManager.shared
            if run.mask & 1 != 0 { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if run.mask & 2 != 0 { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            attrs[.font] = font
            if run.mask & 4 != 0 { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }
    static func mask(_ attrs: [NSAttributedString.Key: Any]) -> Int {
        let traits = NSFontManager.shared.traits(of: attrs[.font] as? NSFont ?? .systemFont(ofSize: 13))
        return (traits.contains(.boldFontMask) ? 1 : 0) | (traits.contains(.italicFontMask) ? 2 : 0) | ((attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0 ? 4 : 0)
    }
    static func stored(_ text: NSAttributedString) -> String {
        var runs = [Run]()
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            runs.append(Run(text: (text.string as NSString).substring(with: range), mask: mask(attrs)))
        }
        return encode(runs)
    }
    static func substituting(_ fields: [String: String], in source: String) -> String {
        let styled = NSMutableAttributedString(attributedString: attributed(source, attributes: [:]))
        let original = styled.string as NSString
        var matches: [(NSRange, String)] = []
        for (field, replacement) in fields {
            var start = 0
            while start < original.length {
                let range = original.range(of: field, options: [], range: NSRange(location: start, length: original.length - start))
                if range.location == NSNotFound { break }
                matches.append((range, replacement))
                start = NSMaxRange(range)
            }
        }
        for (range, replacement) in matches.sorted(by: { $0.0.location > $1.0.location }) {
            let attrs = styled.attributes(at: range.location, effectiveRange: nil)
            styled.replaceCharacters(in: range, with: attributed(replacement, attributes: attrs))
        }
        return stored(styled)
    }
    static func properties(_ mask: Int) -> String {
        (mask & 1 == 0 ? "" : "<w:b/>") + (mask & 2 == 0 ? "" : "<w:i/>") + (mask & 4 == 0 ? "" : "<w:u w:val=\"single\"/>")
    }
}
