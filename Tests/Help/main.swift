import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let en = try HelpLibrary.load(root: root, language: "en")
let de = try HelpLibrary.load(root: root, language: "de")
precondition(en.articles.count >= 16)
precondition(en.articles.map(\.id) == de.articles.map(\.id))
precondition(en.articles.first?.title != de.articles.first?.title)
precondition(en.articles.contains { $0.id == "ai-prompting" })
precondition(de.articles.contains { $0.matches("Fremdkosten", locale: Locale(identifier: "de")) })
precondition(en.articles.contains { $0.matches("reference rates", locale: Locale(identifier: "en")) })
precondition(!en.articles.contains { $0.matches("nonexistent-help-phrase", locale: Locale(identifier: "en")) })
let fallback = try HelpLibrary.load(root: root, language: "fr")
precondition(fallback.articles == en.articles)
precondition(en.article(for: URL(string: "help://local-ai")!)?.id == "local-ai")
precondition(en.article(for: URL(string: "https://example.com/local-ai")!) == nil)
precondition(en.article(for: URL(string: "help://local-ai/../../privacy")!) == nil)
for article in en.articles + de.articles {
    precondition(!HelpBlock.parse(article.markdown).isEmpty)
    let regex = try NSRegularExpression(pattern: #"help://([a-z0-9-]+)"#)
    let source = article.markdown as NSString
    for match in regex.matches(in: article.markdown, range: NSRange(location: 0, length: source.length)) {
        precondition(en.articles.contains { $0.id == source.substring(with: match.range(at: 1)) })
    }
}
let blocks = HelpBlock.parse("# Title\n\nHello **world**.\nSoft line.\n\n- Item\n2. Step\n\n```sh\necho safe\n```\n\n| A | B |\n| --- | --- |\n| C | D |")
precondition(blocks.contains(.paragraph("Hello **world**. Soft line.")))
precondition(blocks.contains(.item("•", "Item")))
precondition(blocks.contains(.item("2.", "Step")))
precondition(blocks.contains(.code("echo safe")))
precondition(blocks.contains(.table([["A", "B"], ["C", "D"]])))
print("Bilingual help, search, links, fallback and native Markdown blocks passed.")
