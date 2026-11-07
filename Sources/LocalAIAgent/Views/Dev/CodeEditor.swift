import AppKit
import SwiftUI

/// A plain-text editor with line numbers and Python colours. AppKit's text view handles find, undo
/// and long files, which SwiftUI's own editor doesn't do well.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var isPython: Bool
    var jump: DevJump?
    var errorLine: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.clipsToBounds = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.drawsBackground = false
        view.font = CodeStyle.font
        view.textColor = CodeStyle.text
        view.insertionPointColor = NSColor(Palette.accent)
        view.selectedTextAttributes = [.backgroundColor: NSColor(Palette.accent).withAlphaComponent(0.3)]
        view.textContainerInset = NSSize(width: 6, height: 8)
        // Long lines scroll sideways, as code should, rather than wrapping.
        view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.typingAttributes = [.font: CodeStyle.font, .foregroundColor: CodeStyle.text]
        view.string = text

        let ruler = LineRuler(textView: view, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler
        context.coordinator.view = view
        NotificationCenter.default.addObserver(ruler, selector: #selector(LineRuler.redraw), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.colour()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = isEditable
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            let length = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            coordinator.colour()
            coordinator.ruler?.redraw()
        }
        coordinator.markError()
        if let jump, jump != coordinator.lastJump {
            coordinator.lastJump = jump
            coordinator.show(line: jump.line)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var view: NSTextView?
        var ruler: LineRuler?
        var lastJump: DevJump?
        private var markedLine: Int?

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
            colour()
            ruler?.redraw()
        }

        func colour() {
            guard let storage = view?.textStorage else { return }
            CodeStyle.apply(to: storage, python: parent.isPython)
            view?.typingAttributes = [.font: CodeStyle.font, .foregroundColor: CodeStyle.text]
        }

        func show(line: Int) {
            guard let view, let range = range(ofLine: line) else { return }
            view.setSelectedRange(NSRange(location: range.location, length: 0))
            view.scrollRangeToVisible(range)
            view.window?.makeFirstResponder(view)
        }

        func markError() {
            guard parent.errorLine != markedLine, let view, let manager = view.layoutManager else { return }
            let length = (view.string as NSString).length
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            markedLine = parent.errorLine
            if let line = parent.errorLine, let range = range(ofLine: line) {
                manager.addTemporaryAttribute(.backgroundColor, value: NSColor(Palette.critical).withAlphaComponent(0.2), forCharacterRange: range)
            }
        }

        private func range(ofLine line: Int) -> NSRange? {
            guard let view else { return nil }
            let string = view.string as NSString
            var index = 0, current = 1
            while current < line, index < string.length {
                index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
                current += 1
            }
            return current == line && index <= string.length ? string.lineRange(for: NSRange(location: index, length: 0)) : nil
        }

        /// Tab makes spaces, Return keeps the indent, and a line ending in a colon indents the next.
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            let string = view.string as NSString
            let location = view.selectedRange().location
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                view.insertText("    ", replacementRange: view.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let line = string.substring(with: string.lineRange(for: NSRange(location: location, length: 0)))
                let beforeCursor = string.substring(with: NSRange(location: string.lineRange(for: NSRange(location: location, length: 0)).location,
                                                                  length: location - string.lineRange(for: NSRange(location: location, length: 0)).location))
                var indent = String(line.prefix { $0 == " " })
                if beforeCursor.trimmingCharacters(in: .whitespaces).hasSuffix(":") { indent += "    " }
                view.insertText("\n" + indent, replacementRange: view.selectedRange())
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                let selection = view.selectedRange()
                guard selection.length == 0, selection.location >= 4 else { return false }
                let start = string.lineRange(for: NSRange(location: location, length: 0)).location
                let leading = string.substring(with: NSRange(location: start, length: location - start))
                guard !leading.isEmpty, leading.count % 4 == 0, leading.allSatisfy({ $0 == " " }) else { return false }
                view.insertText("", replacementRange: NSRange(location: location - 4, length: 4))
                return true
            default:
                return false
            }
        }
    }
}

/// The numbers down the left of the editor.
final class LineRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 42
        clientView = textView
        // Otherwise its edge line runs on past the editor, down the whole window.
        clipsToBounds = true
    }

    required init(coder: NSCoder) { fatalError("Not used") }

    @objc func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let view = textView, let manager = view.layoutManager, let container = view.textContainer else { return }
        let string = view.string as NSString
        let visible = view.visibleRect
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        var index = 0
        while index < characters.location {
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                                                         .foregroundColor: NSColor.white.withAlphaComponent(0.28)]
        func draw(_ number: Int, at y: CGFloat) {
            let label = NSAttributedString(string: "\(number)", attributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - label.size().width - 8, y: y + 2))
        }
        let inset = view.textContainerOrigin.y - visible.minY + convert(NSPoint.zero, from: scrollView?.contentView).y
        if string.length == 0 {
            draw(1, at: inset)
            return
        }
        while index < string.length, index <= NSMaxRange(characters) {
            let glyph = manager.glyphIndexForCharacter(at: index)
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line, at: fragment.minY + inset)
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
    }
}

/// Python's colours, found with a few patterns. It reads a file as it's typed, so it stays simple:
/// a wrong colour now and then costs far less than a parser would.
enum CodeStyle {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let text = NSColor.white.withAlphaComponent(0.88)
    private static let keyword = NSColor(red: 0.78, green: 0.62, blue: 1, alpha: 1)
    private static let string = NSColor(red: 0.91, green: 0.78, blue: 0.5, alpha: 1)
    private static let comment = NSColor.white.withAlphaComponent(0.34)
    private static let number = NSColor(red: 0.96, green: 0.6, blue: 0.45, alpha: 1)
    private static let definition = NSColor(red: 0.5, green: 0.83, blue: 0.97, alpha: 1)
    private static let builtin = NSColor(red: 0.5, green: 0.9, blue: 0.76, alpha: 1)

    private static func regex(_ pattern: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: pattern) }

    private static let words = regex(#"\b(False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b"#)
    private static let builtins = regex(#"\b(abs|all|any|bool|dict|enumerate|filter|float|input|int|isinstance|len|list|map|max|min|open|print|range|reversed|round|self|set|sorted|str|sum|super|tuple|type|zip)\b"#)
    private static let numbers = regex(#"\b\d[\d_]*(\.\d+)?\b"#)
    private static let definitions = regex(#"\b(?:def|class)\s+(\w+)|^\s*(@\w+)"#)
    /// In one pattern, so a # inside a string isn't a comment and a quote inside a comment isn't a string.
    private static let textual = regex(#"#[^\n]*|[rbfRBF]{0,2}"""[\s\S]*?(?:"""|\z)|[rbfRBF]{0,2}'''[\s\S]*?(?:'''|\z)|[rbfRBF]{0,2}"(?:\\.|[^"\\\n])*"?|[rbfRBF]{0,2}'(?:\\.|[^'\\\n])*'?"#)

    /// Above this, colouring would slow down typing.
    private static let limit = 300_000

    static func apply(to storage: NSTextStorage, python: Bool) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: font, .foregroundColor: text], range: whole)
        guard python, storage.length < limit else { return }
        let string = storage.string
        func paint(_ regex: NSRegularExpression?, _ color: NSColor) {
            regex?.enumerateMatches(in: string, range: whole) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        paint(numbers, number)
        paint(builtins, builtin)
        paint(words, keyword)
        definitions?.enumerateMatches(in: string, options: [], range: whole) { match, _, _ in
            guard let match else { return }
            for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: definition, range: match.range(at: group))
            }
        }
        textual?.enumerateMatches(in: string, range: whole) { match, _, _ in
            guard let match else { return }
            let isComment = (string as NSString).substring(with: NSRange(location: match.range.location, length: 1)) == "#"
            storage.addAttribute(.foregroundColor, value: isComment ? comment : Self.string, range: match.range)
        }
    }
}
