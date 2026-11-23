import SwiftUI

struct RichField: View {
    let title: String
    @Binding var text: String
    var height: CGFloat = 86
    @State private var target = EditorTarget()
    init(_ title: String, text: Binding<String>, height: CGFloat = 86) {
        self.title = title
        _text = text
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title)).font(.callout)
                Spacer()
                ForEach([1,2,4], id: \.self) { bit in
                    let name = bit == 1 ? "Bold" : bit == 2 ? "Italic" : "Underline"
                    Button { target.editor?.toggle(bit) } label: { Image(systemName: name.lowercased()) }
                        .buttonStyle(.borderless).accessibilityLabel(Text(LocalizedStringKey(name))).help(Text(LocalizedStringKey(name)))
                }
            }
            RichEditor(text: $text, target: target, label: title)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.32))
                        .allowsHitTesting(false)
                }
        }
    }
}

private final class EditorTarget { weak var editor: FormattingView? }

private final class FormattingView: NSTextView {
    func toggle(_ bit: Int) {
        window?.makeFirstResponder(self)
        let range = selectedRange()
        guard let store = textStorage else { return }
        let start = range.length > 0 ? store.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        let enabled = InlineText.mask(start) & bit == 0
        func changed(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var result = attrs
            if bit == 4 { result[.underlineStyle] = enabled ? 1 : 0 }
            else {
                let font = attrs[.font] as? NSFont ?? .systemFont(ofSize: 13)
                let trait: NSFontTraitMask = bit == 1 ? .boldFontMask : .italicFontMask
                result[.font] = enabled ? NSFontManager.shared.convert(font, toHaveTrait: trait) : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
            }
            return result
        }
        if range.length == 0 { typingAttributes = changed(typingAttributes); return }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let snapshot = NSAttributedString(attributedString: store)
        snapshot.enumerateAttributes(in: range) { attrs, part, _ in store.setAttributes(changed(attrs), range: part) }
        didChangeText()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased(), let bit = ["b":1,"i":2,"u":4][key] {
            toggle(bit); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct RichEditor: NSViewRepresentable {
    @Binding var text: String
    let target: EditorTarget
    let label: String
    final class Coordinator: NSObject, NSTextViewDelegate {
        var value: Binding<String>
        var last: String?
        init(_ value: Binding<String>) { self.value = value }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            let updated = InlineText.stored(editor.attributedString())
            last = updated
            value.wrappedValue = updated
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator($text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = FormattingView()
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 7, height: 6)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(label)
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        target.editor = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.value = $text
        guard context.coordinator.last != text, let editor = scroll.documentView as? FormattingView else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor]
        editor.textStorage?.setAttributedString(InlineText.attributed(text, attributes: attrs))
        editor.typingAttributes = attrs
        context.coordinator.last = text
    }
}
