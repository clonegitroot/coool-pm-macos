import Foundation

struct HelpArticle: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let markdown: String
    var summary: String {
        markdown.components(separatedBy: "\n\n").dropFirst().first.map {
            $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        } ?? ""
    }
    func matches(_ query: String, locale: Locale) -> Bool {
        let text = (title + "\n" + markdown).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            text.contains(String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale))
        }
    }
}

struct HelpLibrary: Sendable {
    private struct Entry: Decodable { let id: String; let symbol: String }
    let articles: [HelpArticle]
    static func load(root: URL, language: String) throws -> Self {
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: root.appendingPathComponent("index.json")))
        guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count else { throw HelpError.invalidContent }
        let code = language == "de" ? "de" : "en"
        let articles = try entries.map { entry in
            guard entry.id.range(of: "^[a-z0-9-]{1,64}$", options: .regularExpression) != nil else { throw HelpError.invalidContent }
            let preferred = root.appendingPathComponent(code + "/" + entry.id + ".md")
            let fallback = root.appendingPathComponent("en/" + entry.id + ".md")
            let url = FileManager.default.fileExists(atPath: preferred.path) ? preferred : fallback
            let markdown = try String(contentsOf: url, encoding: .utf8)
            guard let first = markdown.components(separatedBy: .newlines).first, first.hasPrefix("# "),
                  !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HelpError.invalidContent }
            return HelpArticle(id: entry.id, symbol: entry.symbol, title: String(first.dropFirst(2)), markdown: markdown)
        }
        return Self(articles: articles)
    }
    func article(for url: URL) -> HelpArticle? {
        guard url.scheme == "help", url.path.isEmpty || url.path == "/", let id = url.host else { return nil }
        return articles.first { $0.id == id }
    }
    enum HelpError: Error { case invalidContent }
}

enum HelpBlock: Equatable, Sendable {
    case heading(Int, String)
    case paragraph(String)
    case item(String, String)
    case code(String)
    case table([[String]])

    static func parse(_ markdown: String) -> [Self] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks = [Self](), paragraph = [String]()
        var index = 0
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flush(); index += 1
                var code = [String]()
                while index < lines.count, !lines[index].hasPrefix("```") { code.append(lines[index]); index += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
            } else if line.hasPrefix("|") {
                flush()
                var rows = [[String]]()
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = lines[index].split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { rows.append(cells) }
                    index += 1
                }
                blocks.append(.table(rows)); continue
            } else if line.isEmpty { flush() }
            else if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
                flush(); blocks.append(.heading(line.distance(from: line.startIndex, to: space), String(line[line.index(after: space)...])))
            } else if line.hasPrefix("- ") {
                flush(); blocks.append(.item("•", String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), dot != line.startIndex,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); blocks.append(.item(String(line[...dot]), String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))
            } else { paragraph.append(line) }
            index += 1
        }
        flush()
        return blocks
    }
}
