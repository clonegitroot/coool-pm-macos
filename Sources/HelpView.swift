import SwiftUI

enum HelpWindow { static let id = "coool-pm-help" }

struct HelpCommands: Commands {
    let locale: Locale
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button {
                NSApp.activate()
                openWindow(id: HelpWindow.id)
            } label: {
                Text(verbatim: AppLanguage.text("Coool PM Help", fallback: "Coool PM Help", locale: locale))
            }.keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct HelpView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    @State private var library: HelpLibrary?
    @State private var selection: String? = "getting-started"
    @State private var query = ""
    @State private var failed = false
    private var code: String { locale.language.languageCode?.identifier == "de" ? "de" : "en" }
    private var visible: [HelpArticle] { library?.articles.filter { $0.matches(query, locale: locale) } ?? [] }
    private var selected: HelpArticle? { library?.articles.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visible) { article in
                    Label { Text(verbatim: article.title).lineLimit(2) } icon: { Image(systemName: article.symbol).foregroundStyle(.tint) }
                        .padding(.vertical, 3).tag(article.id)
                }
            }
            .navigationTitle("Help topics")
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
            .searchable(text: $query, prompt: Text("Search help"))
        } detail: {
            if let article = selected {
                HelpArticleView(article: article).id(article.id + code)
            } else if failed {
                ContentUnavailableView("Help content unavailable", systemImage: "book.closed", description: Text("Rebuild the app with its bundled Help resources."))
            } else if library == nil { ProgressView() }
            else if !query.isEmpty && visible.isEmpty { ContentUnavailableView("No matching help topics", systemImage: "magnifyingglass", description: Text("Try a shorter term, such as rates, backup or AI.")) }
            else { ContentUnavailableView("Choose a help topic", systemImage: "book", description: Text("Search or select a topic in the sidebar.")) }
        }
        .background(HelpWindowFocus().frame(width: 0, height: 0))
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 520)
        .toolbar {
            ToolbarItemGroup {
                if let article = selected {
                    Button("Copy article", systemImage: "doc.on.doc") { copyHelpText(article.markdown) }
                }
                Button("Settings", systemImage: "gearshape") { openWindow(id: BusinessSettingsWindow.id) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let article = library?.article(for: url) { query = ""; selection = article.id; return .handled }
            if ["https", "http"].contains(url.scheme) { return .systemAction }
            return .discarded
        })
        .task(id: code) {
            query = ""
            do {
                guard let root = Bundle.main.resourceURL?.appendingPathComponent("Help", isDirectory: true) else { throw HelpLibrary.HelpError.invalidContent }
                let loaded = try HelpLibrary.load(root: root, language: code)
                library = loaded; failed = false
                if !loaded.articles.contains(where: { $0.id == selection }) { selection = loaded.articles.first?.id }
            } catch { library = nil; failed = true }
        }
        .onChange(of: query) { _, _ in
            if !visible.contains(where: { $0.id == selection }) { selection = visible.first?.id }
        }
    }
}

private struct HelpArticleView: View {
    let article: HelpArticle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: article.symbol).font(.system(size: 30)).foregroundStyle(.tint).frame(width: 38)
                    Text(verbatim: article.title).font(.largeTitle.bold())
                }.padding(.bottom, 4)
                ForEach(Array(HelpBlock.parse(article.markdown).enumerated()), id: \.offset) { _, block in
                    HelpBlockView(block: block)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .textSelection(.enabled)
        .navigationTitle(article.title)
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock
    @ViewBuilder var body: some View {
        switch block {
        case .heading(let level, let title):
            if level > 1 { Text(verbatim: title).font(level == 2 ? .title2.bold() : .headline).padding(.top, 8).accessibilityAddTraits(.isHeader) }
        case .paragraph(let text):
            rich(text).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        case .item(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: marker).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .trailing)
                rich(text).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let code):
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Code example").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Copy") { copyHelpText(code) }.font(.caption) }
                ScrollView(.horizontal) { Text(verbatim: code).font(.system(.body, design: .monospaced)).fixedSize() }
            }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        case .table(let rows):
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow(alignment: .top) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            rich(rows[row][column]).fontWeight(row == 0 ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func rich(_ text: String) -> Text {
        let value = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return value.map(Text.init) ?? Text(verbatim: text)
    }
}

private func copyHelpText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// A newly created secondary SwiftUI window can initially remain behind the main
/// window. Focus this reader once its native window has actually been attached.
private struct HelpWindowFocus: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}
