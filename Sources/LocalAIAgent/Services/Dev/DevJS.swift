import Foundation
import JavaScriptCore

/// JavaScript the way Python's parser serves Python files here: a syntax check before anything runs,
/// and a file split into its top-level pieces, so a long script can be edited a function at a time.
/// It reads strings, template literals, comments and regular expressions well enough for the code
/// models write, and anything it can't follow comes back nil rather than guessed.
enum DevJS {
    struct Piece: Equatable, Sendable {
        /// Nil for a statement that isn't a declaration, such as `render();`.
        var name: String?
        var kind: String
        /// Line numbers, from 1, both ends included.
        var start: Int
        var end: Int
        var text: String

        var isDeclaration: Bool { name != nil }
        var signature: String {
            let first = text.components(separatedBy: "\n").first { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("/*") && !trimmed.hasPrefix("*")
            } ?? ""
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            let cut = trimmed.firstIndex(of: "{").map { String(trimmed[..<$0]) } ?? trimmed
            return String(cut.trimmingCharacters(in: .whitespaces).prefix(100))
        }
    }

    /// What the scanner knows about each line, and the source with comments blanked out.
    struct Scan {
        /// Bracket depth where each line starts.
        var depth: [Int]
        /// Whether each line starts in plain code, rather than inside a string or comment.
        var plain: [Bool]
        /// The source with every comment turned to spaces, newlines kept, so positions still match.
        var blanked: String
        /// Whether the brackets came out even.
        var balanced: Bool
    }

    // MARK: - Syntax

    /// The first syntax error, with its line, or nil if the script would parse. Nothing runs.
    static func syntaxError(in code: String) -> (line: Int, message: String)? {
        guard let context = JSContext() else { return nil }
        let script = JSStringCreateWithCFString(code as CFString)
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        if JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception) { return nil }
        guard let exception, let value = JSValue(jsValueRef: exception, in: context) else { return (0, "SyntaxError") }
        let line = value.objectForKeyedSubscript("line")?.toInt32() ?? 0
        var message = value.toString() ?? "SyntaxError"
        if message.hasPrefix("SyntaxError: ") { message = String(message.dropFirst(13)) }
        return (Int(line), message)
    }

    // MARK: - Scanning

    static func scan(_ source: String) -> Scan {
        enum State { case code, line, block, single, double, template, regex, regexClass }
        let characters = Array(source)
        var blanked = characters
        var state = State.code
        var depth = 0
        var templates: [Int] = []
        var lineDepth = [0]
        var linePlain = [true]
        var balanced = true
        var lastSignificant: Character?
        var lastWord = ""
        var index = 0

        func startsRegex() -> Bool {
            guard let last = lastSignificant else { return true }
            if "(,=:[!&|?{};+-*%<>~^".contains(last) { return true }
            return ["return", "typeof", "case", "do", "else", "in", "of", "new", "delete", "void", "throw", "instanceof", "yield", "await"].contains(lastWord)
        }

        func isNewline(_ character: Character) -> Bool { character == "\n" || character == "\r\n" }
        /// Steps over an escaped character, which can be the end of a line.
        func skipEscaped() {
            index += 1
            if index < characters.count, isNewline(characters[index]) {
                lineDepth.append(depth)
                linePlain.append(false)
            }
        }

        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if isNewline(character) {
                if state == .line { state = .code }
                // A regular expression can't run past the end of its line, so a guess that was wrong stops here.
                if state == .regex || state == .regexClass || state == .single || state == .double { state = .code }
                lineDepth.append(depth)
                linePlain.append(state == .code)
                index += 1
                continue
            }
            switch state {
            case .code:
                if character == "/" && next == "/" {
                    state = .line
                    blanked[index] = " "
                } else if character == "/" && next == "*" {
                    state = .block
                    blanked[index] = " "
                    blanked[index + 1] = " "
                    index += 1
                } else if character == "/" && startsRegex() {
                    state = .regex
                    lastSignificant = "/"
                    lastWord = ""
                } else if character == "'" {
                    state = .single
                } else if character == "\"" {
                    state = .double
                } else if character == "`" {
                    state = .template
                } else if "{([".contains(character) {
                    depth += 1
                } else if "})]".contains(character) {
                    depth -= 1
                    if depth < 0 {
                        balanced = false
                        depth = 0
                    }
                    if character == "}", let open = templates.last, open == depth {
                        templates.removeLast()
                        state = .template
                    }
                }
                if state == .code, !character.isWhitespace {
                    if character.isLetter || character.isNumber || character == "_" || character == "$" {
                        if let last = lastSignificant, last.isLetter || last.isNumber || last == "_" || last == "$" {
                            lastWord.append(character)
                        } else {
                            lastWord = String(character)
                        }
                    } else {
                        lastWord = ""
                    }
                    lastSignificant = character
                } else if state != .code, state != .line, state != .block {
                    lastSignificant = "a"
                    lastWord = ""
                }
            case .line:
                blanked[index] = " "
            case .block:
                if character == "*" && next == "/" {
                    blanked[index] = " "
                    blanked[index + 1] = " "
                    index += 1
                    state = .code
                } else {
                    blanked[index] = " "
                }
            case .single, .double:
                if character == "\\" {
                    skipEscaped()
                } else if (state == .single && character == "'") || (state == .double && character == "\"") {
                    state = .code
                }
            case .template:
                if character == "\\" {
                    skipEscaped()
                } else if character == "`" {
                    state = .code
                } else if character == "$" && next == "{" {
                    templates.append(depth)
                    depth += 1
                    index += 1
                    state = .code
                    lastSignificant = "{"
                    lastWord = ""
                }
            case .regex:
                if character == "\\" {
                    skipEscaped()
                } else if character == "[" {
                    state = .regexClass
                } else if character == "/" {
                    state = .code
                }
            case .regexClass:
                if character == "\\" {
                    skipEscaped()
                } else if character == "]" {
                    state = .regex
                }
            }
            index += 1
        }
        if depth != 0 || !templates.isEmpty || state == .block || state == .template { balanced = false }
        return Scan(depth: lineDepth, plain: linePlain, blanked: String(blanked), balanced: balanced)
    }

    // MARK: - Outline

    private static let declarations: [(kind: String, pattern: String)] = [
        ("function", #"^(?:export\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\("#),
        ("class", #"^(?:export\s+)?class\s+([A-Za-z_$][\w$]*)"#),
        ("variable", #"^(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*="#),
    ]

    /// The file's top-level pieces in order, or nil if its brackets don't come out even.
    static func outline(_ source: String) -> [Piece]? {
        let scan = scan(source)
        guard scan.balanced else { return nil }
        let lines = source.components(separatedBy: "\n")
        let plain = scan.blanked.components(separatedBy: "\n")
        guard lines.count == plain.count, scan.depth.count == lines.count else { return nil }
        // Where each top-level statement begins.
        var starts: [Int] = []
        for index in lines.indices where scan.depth[index] == 0 && scan.plain[index] {
            let text = plain[index].trimmingCharacters(in: .whitespaces)
            guard let first = text.first else { continue }
            // A line that carries on the one before it, as in a chain of calls.
            if ".)]}?:,+-*/&|=".contains(first) { continue }
            // So does one after a line left open, as in `const total =`.
            if let previous = (0..<index).last(where: { !plain[$0].trimmingCharacters(in: .whitespaces).isEmpty }),
               let end = plain[previous].trimmingCharacters(in: .whitespaces).last, "=,+-*/&|?:(".contains(end), scan.depth[previous] == 0 { continue }
            starts.append(index)
        }
        var pieces: [Piece] = []
        for (position, start) in starts.enumerated() {
            var end = (position + 1 < starts.count ? starts[position + 1] : lines.count) - 1
            // Blank lines and comments before the next statement belong with it.
            while end > start, plain[end].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            var first = start
            while first > 0, scan.depth[first - 1] == 0, plain[first - 1].trimmingCharacters(in: .whitespaces).isEmpty,
                  !lines[first - 1].trimmingCharacters(in: .whitespaces).isEmpty, pieces.last.map({ $0.end < first }) ?? true {
                first -= 1
            }
            let head = lines[start].trimmingCharacters(in: .whitespaces)
            var name: String?
            var kind = "statement"
            for declaration in declarations {
                if let groups = head.groups(of: declaration.pattern) {
                    name = groups[1]
                    kind = declaration.kind
                    if kind == "variable", head.matches(#"=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)"#) { kind = "function" }
                    break
                }
            }
            pieces.append(Piece(name: name, kind: kind, start: first + 1, end: end + 1, text: lines[first...end].joined(separator: "\n")))
        }
        return pieces
    }

    /// Names a page's inline handlers can call: functions and variables at the top of the script, and
    /// anything set on window.
    static func globalNames(in source: String) -> Set<String> {
        var names = Set((outline(source) ?? []).compactMap(\.name))
        let regex = try? NSRegularExpression(pattern: #"\bwindow\.([A-Za-z_$][\w$]*)\s*="#)
        for match in regex?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? [] {
            if let range = Range(match.range(at: 1), in: source) { names.insert(String(source[range])) }
        }
        return names
    }

    /// Every function name defined anywhere, at any depth.
    static func allFunctionNames(in source: String) -> Set<String> {
        var names: Set<String> = []
        for pattern in [#"\bfunction\s*\*?\s*([A-Za-z_$][\w$]*)\s*\("#, #"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)"#] {
            let regex = try? NSRegularExpression(pattern: pattern)
            for match in regex?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? [] {
                if let range = Range(match.range(at: 1), in: source) { names.insert(String(source[range])) }
            }
        }
        return names
    }

    // MARK: - Merging

    /// Fits a reply that holds only some functions into the file they came from: a function of the same
    /// name replaces the old one, a new one goes in before the code that starts the page, and a new
    /// statement, such as another event listener, goes in before the last call. Nil if the result
    /// wouldn't parse, or the reply can't be read.
    static func merge(_ reply: String, into source: String) -> String? {
        guard let old = outline(source), let new = outline(reply), !new.isEmpty else { return nil }
        let oldNames = Set(old.compactMap(\.name))
        let newNames = Set(new.compactMap(\.name))
        // A reply with nearly everything in it is the whole file.
        if !oldNames.isEmpty, Double(oldNames.intersection(newNames).count) >= Double(oldNames.count) * 0.8, reply.count * 10 >= source.count * 7 {
            return syntaxError(in: reply) == nil ? reply : nil
        }
        var lines = source.components(separatedBy: "\n")
        var edits: [(start: Int, end: Int, text: String)] = []
        var newDeclarations: [String] = []
        var newStatements: [String] = []
        let existing = Set(old.filter { !$0.isDeclaration }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
        for piece in new {
            if let name = piece.name, let match = old.last(where: { $0.name == name }) {
                if !edits.contains(where: { $0.start == match.start }) { edits.append((match.start, match.end, piece.text)) }
            } else if piece.isDeclaration {
                newDeclarations.append(piece.text)
            } else if !existing.contains(piece.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                newStatements.append(piece.text)
            }
        }
        // The statements at the end that start the page, such as `render();`.
        let lastDeclaration = old.lastIndex(where: \.isDeclaration)
        let tail = old.indices.filter { index in lastDeclaration.map { index > $0 } ?? true }
        let declarationLine = tail.first.map { old[$0].start } ?? (lines.count + 1)
        let finalCall = old.last.flatMap { $0.isDeclaration ? nil : ($0.text.trimmingCharacters(in: .whitespacesAndNewlines).matches(#"^[A-Za-z_$][\w$.]*\([^()]*\);?$"#) ? $0.start : nil) }
        let statementLine = finalCall ?? (lines.count + 1)
        var inserts: [(line: Int, text: String)] = []
        if !newDeclarations.isEmpty { inserts.append((declarationLine, newDeclarations.joined(separator: "\n\n") + "\n")) }
        if !newStatements.isEmpty { inserts.append((statementLine, newStatements.joined(separator: "\n\n") + "\n")) }
        // From the bottom up, so the line numbers above stay right.
        // At the same line an edit goes first, then statements, then declarations, which so end up above them.
        var operations: [(line: Int, order: Int, apply: (inout [String]) -> Void)] = []
        for edit in edits {
            operations.append((edit.start, 0, { lines in
                lines.replaceSubrange((edit.start - 1)..<min(edit.end, lines.count), with: edit.text.components(separatedBy: "\n"))
            }))
        }
        for (position, insert) in inserts.enumerated() {
            operations.append((insert.line, position == 0 && !newDeclarations.isEmpty ? 2 : 1, { lines in
                let at = min(max(insert.line - 1, 0), lines.count)
                lines.insert(contentsOf: insert.text.components(separatedBy: "\n"), at: at)
            }))
        }
        for operation in operations.sorted(by: { $0.line != $1.line ? $0.line > $1.line : $0.order < $1.order }) { operation.apply(&lines) }
        let merged = lines.joined(separator: "\n")
        return syntaxError(in: merged) == nil ? merged : nil
    }
}
