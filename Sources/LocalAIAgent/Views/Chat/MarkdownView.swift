import AppKit
import SwiftUI

/// Lightweight Markdown renderer for chat: headings, lists, quotes, tables, rules and fenced code.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(indent: Int, marker: String, text: String)
    case quote(String)
    case code(language: String, code: String)
    case table([[String]])
    case rule
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var table: [[String]] = []
        var code: [String]?
        var codeLang = ""
        var closingFence = "```"

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)); table = [] }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if code != nil {
                if line.hasPrefix(closingFence) {
                    appendCode(code!, language: codeLang, to: &blocks)
                    code = nil
                } else {
                    code!.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") {
                flushParagraph(); flushTable()
                codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                closingFence = "```"
                code = []
                continue
            }
            // Display math: `$$` on its own line, or `$$ … $$` on one line.
            if line.hasPrefix("$$") {
                flushParagraph(); flushTable()
                let inner = line.dropFirst(2)
                if inner.hasSuffix("$$"), inner.count >= 2 {
                    appendCode([String(inner.dropLast(2)).trimmingCharacters(in: .whitespaces)], language: "math", to: &blocks)
                } else {
                    codeLang = "math"
                    closingFence = "$$"
                    code = inner.isEmpty ? [] : [String(inner)]
                }
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } }
                if !isSeparator { table.append(cells) }
                continue
            }
            flushTable()

            if line.isEmpty { flushParagraph(); continue }

            if let heading = headingLevel(line) {
                flushParagraph()
                blocks.append(.heading(level: heading, text: String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushParagraph(); blocks.append(.rule); continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            let indent = (rawLine.prefix { $0 == " " || $0 == "\t" }.count) / 2
            if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
                flushParagraph()
                blocks.append(.listItem(indent: indent, marker: "•", text: String(line.dropFirst(2))))
                continue
            }
            if let marker = numberedMarker(line) {
                flushParagraph()
                blocks.append(.listItem(indent: indent, marker: marker, text: String(line.dropFirst(marker.count + 1))))
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        flushTable()
        // An unterminated fence while streaming still renders as code.
        if let code { appendCode(code, language: codeLang, to: &blocks) }
        return blocks
    }

    /// Skips empty fences (models sometimes emit a stray closing ```).
    private static func appendCode(_ lines: [String], language: String, to blocks: inout [MarkdownBlock]) {
        let code = lines.joined(separator: "\n")
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        blocks.append(.code(language: language, code: code))
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func numberedMarker(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let p = rest.first, p == "." || p == ")", rest.dropFirst().first == " " else { return nil }
        return digits + "."
    }

    static func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 14, alignment: .trailing)
                Text(MarkdownParser.inline(text))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Palette.accent.opacity(0.6)).frame(width: 3)
                Text(MarkdownParser.inline(text)).foregroundStyle(.secondary).italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .table(let rows):
            TableBlockView(rows: rows)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.uiCaption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.uiCaption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}

private struct TableBlockView: View {
    let rows: [[String]]

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(MarkdownParser.inline(c < row.count ? row[c] : ""))
                            .font(r == 0 ? .callout.weight(.semibold) : .callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(r == 0 ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(r.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear))
                if r < rows.count - 1 { Divider().gridCellUnsizedAxes(.horizontal) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
