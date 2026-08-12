import SwiftUI
import AppKit

// MARK: - MarkdownAction

enum MarkdownAction: CaseIterable, Hashable {
    case bold, italic, strikethrough, inlineCode, codeBlock, bullet, numbered, quote

    var icon: String {
        switch self {
        case .bold:          return "bold"
        case .italic:        return "italic"
        case .strikethrough: return "strikethrough"
        case .inlineCode:    return "chevron.left.forwardslash.chevron.right"
        case .codeBlock:     return "curlybraces"
        case .bullet:        return "list.bullet"
        case .numbered:      return "list.number"
        case .quote:         return "text.quote"
        }
    }

    var label: String {
        switch self {
        case .bold:          return "Bold (**text**)"
        case .italic:        return "Italic (_text_)"
        case .strikethrough: return "Strikethrough (~~text~~)"
        case .inlineCode:    return "Inline code (`code`)"
        case .codeBlock:     return "Code block"
        case .bullet:        return "Bullet list (- item)"
        case .numbered:      return "Numbered list (1. item)"
        case .quote:         return "Quote (> text)"
        }
    }

    var prefix: String {
        switch self {
        case .bold:          return "**"
        case .italic:        return "_"
        case .strikethrough: return "~~"
        case .inlineCode:    return "`"
        case .codeBlock:     return "```\n"
        case .bullet:        return "- "
        case .numbered:      return "1. "
        case .quote:         return "> "
        }
    }

    var suffix: String {
        switch self {
        case .bold:          return "**"
        case .italic:        return "_"
        case .strikethrough: return "~~"
        case .inlineCode:    return "`"
        case .codeBlock:     return "\n```"
        case .bullet, .numbered, .quote: return ""
        }
    }

    var isWrapping: Bool { !suffix.isEmpty }
    var wrapPlaceholder: String { "text" }
}

// MARK: - NoteEditorRef

/// Bridge so SwiftUI toolbar buttons can drive the underlying AppKit text view.
final class NoteEditorRef {
    weak var coordinator: NoteEditorCoordinator?

    func applyMarkdown(_ action: MarkdownAction) {
        coordinator?.applyMarkdown(action)
    }

    func focus() {
        guard let textView = coordinator?.textView else { return }
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }
}

// MARK: - NoteTextView

private final class NoteTextView: NSTextView {
    var placeholder: String = "Add a note…"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0
        let inset = textContainerInset
        let rect = NSRect(
            x: inset.width + padding,
            y: inset.height,
            width: max(0, bounds.width - inset.width * 2 - padding),
            height: bounds.height
        )
        placeholder.draw(in: rect, withAttributes: attrs)
    }
}

// MARK: - NoteEditorCoordinator

final class NoteEditorCoordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var onSubmit: () -> Void
    weak var textView: NSTextView?

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
        self.text = text
        self.onSubmit = onSubmit
    }

    func applyMarkdown(_ action: MarkdownAction) {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let range = textView.selectedRange()
        let selected = nsString.substring(with: range)

        let content: String
        let replacement: String
        let selectStart: Int
        let selectLen: Int

        if action.isWrapping {
            content = selected.isEmpty ? action.wrapPlaceholder : selected
            replacement = action.prefix + content + action.suffix
            selectStart = range.location + (action.prefix as NSString).length
            selectLen = (content as NSString).length
        } else {
            content = selected
            replacement = action.prefix + content
            selectStart = range.location + (action.prefix as NSString).length
            selectLen = (content as NSString).length
        }

        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selectStart, length: selectLen))
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        text.wrappedValue = textView.string
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if !flags.contains(.shift) {
                onSubmit()
                return true
            }
        }
        return false
    }
}

// MARK: - NoteEditorView

struct NoteEditorView: NSViewRepresentable {
    @Binding var text: String
    let ref: NoteEditorRef
    let onSubmit: () -> Void

    func makeCoordinator() -> NoteEditorCoordinator {
        NoteEditorCoordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NoteTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.string = text
        textView.autoresizingMask = [.width]

        context.coordinator.textView = textView
        ref.coordinator = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }
}
