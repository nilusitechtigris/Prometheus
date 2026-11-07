import Foundation

/// How a page and its scripts fit together. Written a file at a time, a small model's script looks up
/// `#taskInput` while the page it wrote a minute earlier says `id="task-input"`, or a button calls a
/// function that lives inside another one. Each is a crash the page check would only find one at a
/// time, and code can see them all at once, without running anything, and mend the easy ones itself.
enum DevWebLinks {
    struct Element: Equatable, Sendable {
        var id: String
        var tag: String
        var attributes: [String: String]
        var text: String
        var empty: Bool
        var line: Int
    }

    struct Tag {
        var name: String
        var attributes: [String: String]
        var line: Int
        /// Where the tag ends in the page.
        var end: String.Index
    }

    // MARK: - Reading a page

    /// Every opening tag, outside comments, scripts and styles.
    static func tags(in html: String) -> [Tag] {
        var found: [Tag] = []
        var index = html.startIndex
        var line = 1
        func advance(to target: String.Index) {
            line += html[index..<target].filter { $0 == "\n" || $0 == "\r\n" }.count
            index = target
        }
        while let open = html[index...].firstIndex(of: "<") {
            advance(to: open)
            let rest = html[open...]
            if rest.hasPrefix("<!--") {
                let close = html.range(of: "-->", range: open..<html.endIndex)?.upperBound ?? html.endIndex
                advance(to: close)
                continue
            }
            var cursor = html.index(after: open)
            guard cursor < html.endIndex, html[cursor].isLetter else {
                advance(to: cursor)
                continue
            }
            var name = ""
            while cursor < html.endIndex, html[cursor].isLetter || html[cursor].isNumber || html[cursor] == "-" {
                name.append(html[cursor])
                cursor = html.index(after: cursor)
            }
            var attributes: [String: String] = [:]
            while cursor < html.endIndex, html[cursor] != ">" {
                if html[cursor].isWhitespace || html[cursor] == "/" {
                    cursor = html.index(after: cursor)
                    continue
                }
                var key = ""
                while cursor < html.endIndex, !html[cursor].isWhitespace, !"=>/".contains(html[cursor]) {
                    key.append(html[cursor])
                    cursor = html.index(after: cursor)
                }
                while cursor < html.endIndex, html[cursor].isWhitespace { cursor = html.index(after: cursor) }
                var value = ""
                if cursor < html.endIndex, html[cursor] == "=" {
                    cursor = html.index(after: cursor)
                    while cursor < html.endIndex, html[cursor].isWhitespace { cursor = html.index(after: cursor) }
                    if cursor < html.endIndex, html[cursor] == "\"" || html[cursor] == "'" {
                        let quote = html[cursor]
                        cursor = html.index(after: cursor)
                        while cursor < html.endIndex, html[cursor] != quote {
                            value.append(html[cursor])
                            cursor = html.index(after: cursor)
                        }
                        if cursor < html.endIndex { cursor = html.index(after: cursor) }
                    } else {
                        while cursor < html.endIndex, !html[cursor].isWhitespace, html[cursor] != ">" {
                            value.append(html[cursor])
                            cursor = html.index(after: cursor)
                        }
                    }
                }
                if !key.isEmpty, attributes[key.lowercased()] == nil { attributes[key.lowercased()] = value }
                if key.isEmpty, cursor < html.endIndex, html[cursor] != ">" { cursor = html.index(after: cursor) }
            }
            let end = cursor < html.endIndex ? html.index(after: cursor) : html.endIndex
            let lower = name.lowercased()
            found.append(Tag(name: lower, attributes: attributes, line: line, end: end))
            advance(to: end)
            // What's inside a script or style isn't markup.
            if lower == "script" || lower == "style" {
                let close = html.range(of: "</\(lower)", options: .caseInsensitive, range: end..<html.endIndex)?.lowerBound ?? html.endIndex
                advance(to: close)
            }
        }
        return found
    }

    /// Every element with an id, in order, with what a model needs to use it.
    static func elements(in html: String) -> [Element] {
        tags(in: html).compactMap { tag in
            guard let id = tag.attributes["id"], !id.isEmpty else { return nil }
            var text = ""
            var empty = true
            if !["input", "img", "br", "hr", "meta", "link"].contains(tag.name),
               let close = html.range(of: "</\(tag.name)", options: .caseInsensitive, range: tag.end..<html.endIndex) {
                let inner = String(html[tag.end..<close.lowerBound])
                empty = inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                text = inner.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            return Element(id: id, tag: tag.name, attributes: tag.attributes, text: String(text.prefix(40)), empty: empty, line: tag.line)
        }
    }

    static func ids(in html: String) -> [String] { tags(in: html).compactMap { $0.attributes["id"] }.filter { !$0.isEmpty } }

    /// The page's elements, one line each, the way a script needs to know them.
    static func describe(_ elements: [Element]) -> String {
        elements.prefix(40).map { element in
            var parts = ["#\(element.id): \(element.tag)"]
            if let type = element.attributes["type"], ["input", "button"].contains(element.tag) { parts.append("type=\(type)") }
            if let classes = element.attributes["class"], !classes.isEmpty {
                parts.append("class=\"\(classes.split(separator: " ").prefix(4).joined(separator: " "))\"")
            }
            if let placeholder = element.attributes["placeholder"], !placeholder.isEmpty { parts.append("placeholder=\"\(placeholder.prefix(30))\"") }
            if !element.text.isEmpty, ["button", "a", "label", "h1", "h2", "h3", "h4", "h5", "span", "p", "option", "strong", "small", "div", "li"].contains(element.tag) {
                parts.append("\"\(element.text)\"")
            } else if element.empty, ["ul", "ol", "tbody", "table", "div", "section", "select", "p", "span"].contains(element.tag) {
                parts.append("(empty: app.js fills it)")
            }
            return "- " + parts.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// Local files a page links: its scripts and its style sheets, in order.
    static func linkedFiles(in html: String) -> (scripts: [String], styles: [String]) {
        var scripts: [String] = [], styles: [String] = []
        for tag in tags(in: html) {
            if tag.name == "script", let source = tag.attributes["src"], let path = local(source) {
                scripts.append(path)
            } else if tag.name == "link", tag.attributes["rel"]?.lowercased().contains("stylesheet") == true, let href = tag.attributes["href"], let path = local(href) {
                styles.append(path)
            }
        }
        return (scripts, styles)
    }

    /// A project path from an address in a page, or nil for one that leaves the project.
    static func local(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.matches(#"^([a-zA-Z][\w+.-]*:|//)"#) else { return nil }
        var path = trimmed.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? trimmed
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path.isEmpty ? nil : path
    }

    /// The scripts written into the page itself, each with the line it starts on.
    static func inlineScripts(in html: String) -> [(code: String, line: Int)] {
        var found: [(String, Int)] = []
        for tag in tags(in: html) where tag.name == "script" && tag.attributes["src"] == nil {
            let type = tag.attributes["type"]?.lowercased() ?? ""
            guard type.isEmpty || type.contains("javascript") else { continue }
            let close = html.range(of: "</script", options: .caseInsensitive, range: tag.end..<html.endIndex)?.lowerBound ?? html.endIndex
            found.append((String(html[tag.end..<close]), tag.line))
        }
        return found
    }

    // MARK: - Reading a script

    /// Ids a script looks up, with the line of each.
    static func idReferences(in script: String) -> [(id: String, line: Int)] {
        let code = DevJS.scan(script).blanked
        var found: [(String, Int)] = []
        func lineOf(_ range: NSRange) -> Int {
            guard let lower = Range(range, in: code)?.lowerBound else { return 0 }
            return code[..<lower].filter { $0 == "\n" || $0 == "\r\n" }.count + 1
        }
        if let regex = try? NSRegularExpression(pattern: #"getElementById\(\s*(["'`])([^"'`$\\]+)\1\s*\)"#) {
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                if let range = Range(match.range(at: 2), in: code) { found.append((String(code[range]), lineOf(match.range))) }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(?:querySelector(?:All)?|(?<![\w$])\$\$?)\(\s*(["'`])([^"'`]*)\1"#),
           let token = try? NSRegularExpression(pattern: #"#([A-Za-z_][\w-]*)"#) {
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let range = Range(match.range(at: 2), in: code) else { continue }
                let selector = String(code[range])
                if selector.contains("${") { continue }
                for item in token.matches(in: selector, range: NSRange(selector.startIndex..., in: selector)) {
                    if let id = Range(item.range(at: 1), in: selector) { found.append((String(selector[id]), lineOf(match.range))) }
                }
            }
        }
        return found
    }

    /// Ids a script gives elements itself, in the markup it writes or by setting them.
    static func idsMade(by script: String) -> Set<String> {
        var made: Set<String> = []
        for pattern in [#"\bid\s*=\s*\\?["']([A-Za-z_][\w-]*)"#, #"\.id\s*=\s*["'`]([A-Za-z_][\w-]*)"#, #"setAttribute\(\s*["']id["']\s*,\s*["'`]([A-Za-z_][\w-]*)"#] {
            let regex = try? NSRegularExpression(pattern: pattern)
            for match in regex?.matches(in: script, range: NSRange(script.startIndex..., in: script)) ?? [] {
                if let range = Range(match.range(at: 1), in: script) { made.insert(String(script[range])) }
            }
        }
        return made
    }

    private static let builtins: Set<String> = ["alert", "confirm", "prompt", "console", "document", "window", "event", "this", "return", "if",
                                                "setTimeout", "setInterval", "location", "history", "parseInt", "parseFloat", "Number", "String", "Math", "void"]

    /// The functions a page's own attributes call, as in onclick="addTask()".
    static func handlerCalls(in html: String) -> [(name: String, event: String, line: Int)] {
        tags(in: html).flatMap { tag in
            tag.attributes.compactMap { key, value -> (String, String, Int)? in
                guard key.hasPrefix("on"), let name = value.groups(of: #"^\s*(?:return\s+)?([A-Za-z_$][\w$]*)\s*\("#)?[1], !builtins.contains(name) else { return nil }
                return (name, String(key.dropFirst(2)), tag.line)
            }
        }.sorted { $0.2 < $1.2 }
    }

    // MARK: - Checking a page with its scripts

    struct Result {
        /// The files, with what code could mend put right.
        var files: [String: String]
        var notes: [String] = []
        var failure: DevFailure?
    }

    /// Two ids that only differ in their dashes, case or one letter mean the same element.
    private static func normalized(_ id: String) -> String { id.lowercased().filter { $0.isLetter || $0.isNumber } }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let saved = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = saved
            }
        }
        return row[b.count]
    }

    /// The one id on the page a missing one was surely meant to be, if there is exactly one.
    static func closest(to id: String, among ids: [String]) -> String? {
        let key = normalized(id)
        let same = Set(ids.filter { normalized($0) == key })
        if same.count == 1 { return same.first }
        guard key.count >= 5 else { return nil }
        let near = Set(ids.filter { distance(normalized($0), key) == 1 })
        return near.count == 1 ? near.first : nil
    }

    private static func replacingId(_ old: String, with new: String, in script: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: old)
        var text = script.replacingOccurrences(of: #"(getElementById\(\s*["'`])"# + escaped + #"(?=["'`])"#, with: "$1" + new, options: .regularExpression)
        text = text.replacingOccurrences(of: "#" + escaped + #"(?![\w-])"#, with: "#" + new, options: .regularExpression)
        return text
    }

    /// Checks a page against its scripts and returns the first thing worth fixing, after mending what
    /// code can. `files` holds the page and any of its scripts, by path, as they are now.
    static func check(page: String, files: [String: String]) -> Result {
        var result = Result(files: files)
        guard let html = files[page] else { return result }
        let linked = linkedFiles(in: html).scripts.filter { files[$0] != nil }
        let pageIds = ids(in: html)

        // Syntax first: nothing else in a script counts if it won't run.
        for path in linked {
            if let error = DevJS.syntaxError(in: files[path] ?? "") {
                result.failure = DevFailure(file: path, line: error.line > 0 ? error.line : nil, kind: "SyntaxError", message: error.message, output: "")
                return result
            }
        }
        for script in inlineScripts(in: html) {
            if let error = DevJS.syntaxError(in: script.code) {
                result.failure = DevFailure(file: page, line: error.line > 0 ? script.line + error.line - 1 : script.line, kind: "SyntaxError", message: error.message, output: "")
                return result
            }
        }

        let duplicates = Dictionary(grouping: pageIds, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        if !duplicates.isEmpty { result.notes.append("\(page) uses the id \(duplicates.prefix(3).joined(separator: ", ")) more than once.") }

        var scripts = linked.map { (path: $0, code: result.files[$0] ?? "", offset: 0) }
        scripts += inlineScripts(in: html).map { (path: page, code: $0.code, offset: $0.line - 1) }
        let made = scripts.reduce(into: Set<String>()) { $0.formUnion(idsMade(by: $1.code)) }
        let known = Set(pageIds).union(made)

        var missing: [(path: String, id: String, line: Int)] = []
        for script in scripts {
            var mended = script.code
            for reference in idReferences(in: script.code) where !known.contains(reference.id) {
                if script.offset == 0, let match = closest(to: reference.id, among: pageIds) {
                    mended = replacingId(reference.id, with: match, in: mended)
                    let note = "\(script.path) looked up #\(reference.id), which \(page) calls #\(match), so I matched them."
                    if !result.notes.contains(note) { result.notes.append(note) }
                } else if !missing.contains(where: { $0.id == reference.id }) {
                    missing.append((script.path, reference.id, reference.line + script.offset))
                }
            }
            if script.offset == 0, mended != script.code { result.files[script.path] = mended }
        }
        if let first = missing.first {
            let others = missing.dropFirst().map { "#\($0.id)" }
            let more = others.isEmpty ? "" : " It also looks up \(others.prefix(4).joined(separator: ", ")), which aren't there either."
            result.failure = DevFailure(file: first.path, line: first.line, kind: "Link",
                                        message: "\(first.path) looks up #\(first.id), but \(page) has no element with that id.\(more)",
                                        output: describe(elements(in: html)))
            return result
        }

        // A listener added each time the page is drawn piles up: after a few changes one click runs many times.
        for script in scripts where script.offset == 0 {
            if let pile = listenerInRender(script.code) {
                result.failure = DevFailure(file: script.path, line: pile.line, kind: "Link",
                                            message: "render() adds a \(pile.event) listener to \(pile.target) every time it draws the page, so after a few changes one \(pile.event) runs many times.",
                                            output: "")
                return result
            }
        }

        // A function a button calls has to be where the page can reach it.
        let reachable = scripts.reduce(into: Set<String>()) { $0.formUnion(DevJS.globalNames(in: $1.code)) }
        let anywhere = scripts.reduce(into: Set<String>()) { $0.formUnion(DevJS.allFunctionNames(in: $1.code)) }
        if let call = handlerCalls(in: html).first(where: { !reachable.contains($0.name) }) {
            let home = linked.first ?? page
            let message = anywhere.contains(call.name)
                ? "\(page) calls \(call.name)() on \(call.event), but \(call.name) is defined inside another function, where the page can't reach it."
                : "\(page) calls \(call.name)() on \(call.event), but no script defines \(call.name)."
            result.failure = DevFailure(file: home, line: nil, kind: "Link", message: message, output: describe(elements(in: html)))
        }
        return result
    }

    /// A listener that render() adds to something that stays on the page, such as the list it fills,
    /// the document or the window. One on an element render() just made is fine, since that's new each time.
    static func listenerInRender(_ script: String) -> (target: String, event: String, line: Int)? {
        guard let render = DevJS.outline(script)?.first(where: { $0.name == "render" && $0.kind == "function" }) else { return nil }
        let code = DevJS.scan(render.text).blanked
        // Names render() gives to elements it looks up rather than makes.
        var lasting: [String: String] = [:]
        let lookup = #"(?:\$|document\.getElementById|document\.querySelector|getElementById|querySelector)\(\s*["'`]([^"'`]+)["'`]\s*\)"#
        if let regex = try? NSRegularExpression(pattern: #"(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*"# + lookup) {
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let name = Range(match.range(at: 1), in: code), let found = Range(match.range(at: 2), in: code) else { continue }
                lasting[String(code[name])] = String(code[found])
            }
        }
        let call = #"(document|window|"# + lookup + #"|[A-Za-z_$][\w$]*)\s*\.\s*addEventListener\(\s*["'`](\w+)"#
        guard let regex = try? NSRegularExpression(pattern: call) else { return nil }
        for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
            guard let whole = Range(match.range(at: 1), in: code), let event = Range(match.range(at: 3), in: code) else { continue }
            let receiver = String(code[whole])
            var target: String?
            if receiver == "document" || receiver == "window" {
                target = receiver
            } else if let looked = Range(match.range(at: 2), in: code) {
                target = String(code[looked])
            } else if let name = lasting[receiver] {
                target = name
            }
            guard let target else { continue }
            let line = render.start + code[..<whole.lowerBound].filter { $0 == "\n" || $0 == "\r\n" }.count
            return (target, String(code[event]), line)
        }
        return nil
    }

    // MARK: - Keeping pages offline and wired

    /// Takes out what a page wants from the internet that it can do without. Bootstrap's style sheet
    /// becomes the kit, which answers to the same class names. Fonts and icon sheets go, and so does
    /// Bootstrap's script, which nothing here can load. Anything else, such as a chart library, stays,
    /// so the page check reports it and the model writes the page without it.
    static func offline(_ html: String, kit: String = DevKit.cssName) -> (html: String, usesKit: Bool, notes: [String]) {
        var page = html
        var usesKit = false
        var notes: [String] = []
        let links = (try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive))?
            .matches(in: page, range: NSRange(page.startIndex..., in: page)).reversed() ?? []
        for match in links {
            guard let range = Range(match.range, in: page) else { continue }
            let tag = String(page[range])
            guard let href = tag.groups(of: #"href\s*=\s*["']?([^"'\s>]+)"#, options: .caseInsensitive)?[1], local(href) == nil, !href.lowercased().hasPrefix("data:") else { continue }
            if href.lowercased().contains("bootstrap"), !href.lowercased().contains("icons") {
                page.replaceSubrange(range, with: usesKit ? "" : "<link rel=\"stylesheet\" href=\"\(kit)\">")
                usesKit = true
            } else {
                page.replaceSubrange(range, with: "")
            }
        }
        if usesKit { notes.append("Swapped Bootstrap from the internet for \(kit), which works offline.") }
        let before = page
        page = page.replacingOccurrences(of: #"<script\b[^>]*\bsrc\s*=\s*["']?(?:https?:)?//[^"'\s>]*bootstrap[^"'\s>]*["']?[^>]*>\s*</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
        if page != before { notes.append("Took out Bootstrap's script, which can't load here.") }
        if links.count > 0, !usesKit, page != html, notes.isEmpty { notes.append("Took out fonts and icons from the internet, which can't load here.") }
        return (page, usesKit, notes)
    }

    /// Puts back a link to a local file that a rewrite of the page dropped, which would leave the page
    /// without its styles or its code. A link the request asked to remove stays out.
    static func keepingLinks(from original: String, in updated: String) -> String {
        let before = linkedFiles(in: original), after = linkedFiles(in: updated)
        var page = updated
        for style in before.styles where !after.styles.contains(style) {
            page = insert("<link rel=\"stylesheet\" href=\"\(style)\">\n", before: "</head>", in: page)
        }
        for script in before.scripts where !after.scripts.contains(script) {
            page = insert("<script src=\"\(script)\"></script>\n", before: "</body>", in: page)
        }
        return page
    }

    private static func insert(_ text: String, before tag: String, in page: String) -> String {
        guard let range = page.range(of: tag, options: [.caseInsensitive, .backwards]) else { return page + text }
        return page.replacingCharacters(in: range.lowerBound..<range.lowerBound, with: text)
    }

    /// Classes and ids a page uses, for writing its styles.
    static func styleHooks(in html: String) -> String {
        let all = tags(in: html)
        let ids = all.compactMap { $0.attributes["id"] }.filter { !$0.isEmpty }
        var classes: [String] = []
        for tag in all {
            for name in (tag.attributes["class"] ?? "").split(separator: " ").map(String.init) where !classes.contains(name) { classes.append(name) }
        }
        return "Ids: " + ids.prefix(30).map { "#\($0)" }.joined(separator: " ") + "\nClasses: " + classes.prefix(40).joined(separator: " ")
    }
}
