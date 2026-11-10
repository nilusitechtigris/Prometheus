import Foundation

/// Web apps, built a file at a time. Asked for a whole app in one reply, a small model forgets half the
/// features, invents its styling as it goes, and loses track of which ids it gave the page by the time it
/// writes the script. So code splits the work into jobs it can do: a short plan, then the page's markup
/// in classes it already knows, then a few styles, then the script, written against the page's real
/// elements and a skeleton that keeps its data in one place. Code writes the page's head, so the files
/// are always linked, and checks how they fit together before anything runs.
extension DevAgent {
    struct AppPlan: Equatable {
        var name = ""
        var parts = ""
        var data = ""
        var actions = ""

        var text: String {
            [("PARTS", parts), ("DATA", data), ("ACTIONS", actions)].filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        }

        static func parse(_ reply: String, limit: Int = 400) -> AppPlan {
            var plan = AppPlan()
            for line in reply.replacingOccurrences(of: "**", with: "").components(separatedBy: "\n") {
                guard let parts = line.groups(of: #"^\s*[-#*]*\s*(NAME|PARTS|DATA|ACTIONS)\s*:\s*(.+?)\s*$"#, options: .caseInsensitive) else { continue }
                let value = String(parts[2].prefix(limit))
                switch parts[1].uppercased() {
                case "NAME": plan.name = String(value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`. ")).prefix(40))
                case "PARTS": plan.parts = value
                case "DATA": plan.data = value
                default: plan.actions = value
                }
            }
            return plan
        }
    }

    // MARK: - Building

    func buildApp(page: String, job: DevJob) async -> DevOutcome {
        builtApp = true
        let names = appFileNames(for: page)
        for path in [page, names.styles, names.script, names.kit] where originals[path] == nil { originals[path] = .some(project.read(path)) }
        let data = dataFiles()

        emit(.stage("Planning the app"))
        let plan = isV2 ? await planAppV2(job, data: data) : await planApp(job, data: data)
        if let stop = interrupted() { return stop }
        if !plan.name.isEmpty || !plan.parts.isEmpty {
            emit(.note("Plan: \(plan.name.isEmpty ? "the app" : plan.name). \(plan.parts.prefix(160))"))
        }
        let planned = plan.text.isEmpty ? [] : ["Plan:\n\(plan.text)"]

        if versions[names.kit] == nil, project.read(names.kit)?.hasPrefix(DevKit.marker) != true {
            record(DevKit.css, for: names.kit)
        }

        // The markup.
        emit(.stage("Writing \(page)"))
        let bodyRules = """
        You write the HTML for one page of a web app. Rules:
        - Reply with one ```html block holding only what goes inside <body>, and nothing else.
        - kit.css is already linked. It has Bootstrap 5's classes, offline, such as: \(DevKit.vocabulary). Style everything with these classes.
        - Bootstrap's JavaScript and icons aren't there: use emoji for icons, and no data-bs- attributes.
        - Give an id to every element app.js will use: forms, inputs, buttons, and the places where lists, totals and results show. Write ids in lowercase with dashes, like task-input.
        - Leave lists and results empty. app.js fills them from its data.
        - No <script>, <style> or <link>, and nothing from the internet.
        - Build every part of the plan. Keep it under 90 lines.
        """
        let example = "The look to aim for, from a different app:\n\(fence(DevKit.example, path: page))"
        guard let drafted = await draft(page, system: bodyRules, parts: planned + data + [example, "Task: \(job.request)"], ask: "Write the body of \(page).",
                                        extract: Self.appBody(from:), check: { body in
            if DevWeb.hasPlaceholders(body) { return ("Your last reply left parts out. Write every part.", false) }
            let used = DevWebLinks.tags(in: body).filter { ["form", "input", "button", "select", "textarea", "ul", "ol", "tbody"].contains($0.name) }
            if !used.isEmpty, !used.contains(where: { $0.attributes["id"]?.isEmpty == false }) {
                return ("Give an id to each form, input, button and list that app.js will use.", true)
            }
            return nil
        }) else { return unwritten(page) }
        let split = Self.splittingStyles(from: drafted)
        let body = Self.uniqueIds(split.body)
        record(DevKit.shell(title: plan.name.isEmpty ? "App" : plan.name, body: body, styles: Self.leaf(names.styles), script: Self.leaf(names.script), kit: Self.leaf(names.kit)), for: page)

        // The look. A failure here costs nothing: the kit already makes it presentable.
        emit(.stage("Writing \(names.styles)"))
        let stylesRules = """
        You write the style sheet for one web app. kit.css, with Bootstrap 5's classes, loads first, and yours loads after it. Rules:
        - Reply with one ```css block and nothing else.
        - Only add what the classes don't already do: the app's own colours and character, its header, hover effects, and how the things app.js draws look.
        - To change the main colour, set it once: :root { --bs-primary: #hex; --bs-primary-rgb: r, g, b; }
        - Never make body a flex or grid, never give the page a fixed width or height, and never hide anything.
        - Nothing from the internet: no fonts or images. Keep it under 40 lines.
        """
        let css = await draft(names.styles, system: stylesRules, parts: planned + ["\(page) uses:\n\(DevWebLinks.styleHooks(in: body))", "Task: \(job.request)"],
                              ask: "Write \(names.styles).", extract: { [self] in webCode($0, path: names.styles) },
                              check: { DevWeb.hasPlaceholders($0) ? ("Your last reply left parts out. Write every rule.", false) : nil })
        if let stop = interrupted() { return stop }
        var styles = DevKit.stylesStarter
        if !split.styles.isEmpty { styles += Self.saferStyles(split.styles) + "\n" }
        if let css { styles += Self.saferStyles(css) }
        record(styles, for: names.styles)

        // The behaviour, against the page as it really is.
        emit(.stage("Writing \(names.script)"))
        let scriptRules = """
        You write app.js, the JavaScript behind one page of a web app. Rules:
        - Reply with one ```javascript block holding the whole app.js, and nothing else.
        - Fill in the skeleton you're given and keep its shape: all data lives in state, render() draws the page from state, and every event changes state, then calls save() and render().
        - The page is already written. Use only the element ids listed, through $("#id"). Never write another page.
        - render() fills lists with innerHTML, using the same Bootstrap classes as the page. Put data-id on the buttons inside each item, and listen once on the list for their clicks.
        - Listen for a form's submit, and call event.preventDefault() first.
        - Use escapeHtml() for any text the user typed.
        - Plain JavaScript for a browser: no libraries, imports or modules, and nothing from the internet.
        - Write every line. Never leave a placeholder or TODO.
        """
        let skeleton = DevKit.scriptSkeleton(storageKey: Self.slug(plan.name.isEmpty ? (page as NSString).deletingPathExtension : plan.name))
        var parts = planned + ["\(page) has these elements:\n\(DevWebLinks.describe(DevWebLinks.elements(in: body)))"]
        if Self.tokens(body) * 4 < setup.context { parts.append("Its body:\n\(fence(body, path: page))") }
        parts += data
        parts.append("Start from this and fill it in, keeping its shape:\n\(fence(skeleton, path: names.script))")
        parts.append("Task: \(job.request)")
        guard let script = await draft(names.script, system: scriptRules, parts: parts, ask: "Write \(names.script).",
                                       extract: { [self] in webCode($0, path: names.script) }, check: { code in
            if DevWeb.hasPlaceholders(code) { return ("Your last reply left parts out. Write every line.", false) }
            if let error = DevJS.syntaxError(in: code) { return ("Your last reply had this error on line \(error.line): \(error.message).", true) }
            if code.contains("<body") || code.contains("<!doctype") || code.contains("<html") { return ("Reply with app.js only: the page is already written.", false) }
            return nil
        }) else { return unwritten(names.script) }
        record(script, for: names.script)

        let verdict = await verify(job)
        return await finish(job, verdict: verdict, rounds: 0)
    }

    private func interrupted() -> DevOutcome? {
        if Task.isCancelled { return DevOutcome(text: "Stopped. Nothing changed.", stopped: true) }
        if let backendError { return DevOutcome(text: "The model couldn't answer: \(backendError)") }
        return nil
    }

    private func unwritten(_ path: String) -> DevOutcome {
        interrupted() ?? DevOutcome(text: "The model didn't write usable code for \(path), so nothing changed. Try a smaller step, or a larger context window.", worked: false)
    }

    /// Where an app's files go: next to its page, named after it unless it's the main page.
    func appFileNames(for page: String) -> (styles: String, script: String, kit: String) {
        let folder = (page as NSString).deletingLastPathComponent
        let stem = ((page as NSString).lastPathComponent as NSString).deletingPathExtension
        func here(_ name: String) -> String { folder.isEmpty ? name : (folder as NSString).appendingPathComponent(name) }
        var styles = here(stem == "index" ? "styles.css" : "\(stem).css")
        var script = here(stem == "index" ? "app.js" : "\(stem).js")
        if project.exists(styles) || project.exists(script) {
            styles = here("\(stem)-app.css")
            script = here("\(stem)-app.js")
        }
        var kit = here(DevKit.cssName)
        if project.exists(kit), project.read(kit)?.hasPrefix(DevKit.marker) != true { kit = here("prometheus-kit.css") }
        return (styles, script, kit)
    }

    /// Small data files, whole, since an app can't show data it hasn't seen.
    func dataFiles() -> [String] {
        var found: [String] = []
        for entry in project.entries() where !entry.isFolder && entry.path.matches(#"\.(csv|json|tsv|txt)$"#) {
            guard found.count < 3, let text = project.read(entry.path) else { continue }
            let lines = text.components(separatedBy: "\n")
            let shown = text.count <= 1_500 ? text : lines.prefix(12).joined(separator: "\n") + "\n(\(lines.count) lines in all)"
            found.append("\(entry.path):\n```\n\(Self.quoted(shown))\n```\nThe page can read it with fetch(\"\(entry.path)\"), or you can copy its rows into state.")
        }
        return found
    }

    func planApp(_ job: DevJob, data: [String]) async -> AppPlan {
        let system = """
        You plan small web apps that run as one page in a browser, offline. Reply in exactly this form and nothing else:
        NAME: the app's name, 1 to 4 words
        PARTS: the parts of the page, top to bottom, separated by ;
        DATA: what the app keeps track of, and the fields of each thing
        ACTIONS: everything the user can do, separated by ;
        Keep it small enough for one page: 3 to 6 parts and 3 to 6 actions.
        """
        let reply = await complete(system: system, user: (data + ["App: \(job.request)"]).joined(separator: "\n\n"), temperature: 0.2, limit: 320)
        return AppPlan.parse(reply.text)
    }

    /// Gets one file of the app written, going back to the model until the reply is usable.
    private func draft(_ path: String, system: String, parts: [String], ask: String, extract: (String) -> String?,
                       check: (String) -> (problem: String, keep: Bool)?) async -> String? {
        var problem: String?
        var broken: String?
        for attempt in 0..<3 {
            if Task.isCancelled || backendError != nil { return nil }
            var user = parts
            if let problem { user.append(problem) }
            if let broken { user.append("Your code so far:\n\(fence(broken, path: path))") }
            user.append(broken == nil ? ask : "Correct that and change nothing else. Reply with the whole \(path).")
            let reply = await complete(system: system, user: user.joined(separator: "\n\n"), temperature: [0.2, 0.3, 0.5][attempt])
            if Task.isCancelled { return nil }
            if let error = reply.error {
                backendError = error
                return nil
            }
            if reply.cutOff {
                problem = "Your last reply was too long and got cut off. Write a much shorter version."
                broken = nil
                continue
            }
            guard let text = extract(reply.text) else {
                problem = "Your last reply had no usable code. Reply with one code block."
                broken = nil
                continue
            }
            if let issue = check(text) {
                problem = issue.problem
                broken = issue.keep && Self.tokens(text) * 2 + 500 <= setup.context ? text : nil
                emit(.note("Asked again: \(issue.problem.replacingOccurrences(of: "Your last reply ", with: "the reply "))"))
                continue
            }
            return text
        }
        return nil
    }

    // MARK: - Pages with files of their own

    /// The page that links a script or style sheet.
    func pageLinking(_ path: String) -> String? {
        let pages = Set(order.filter(DevWeb.isPage) + project.entries().filter { !$0.isFolder && DevWeb.isPage($0.path) }.map(\.path))
        let sorted = pages.sorted { a, b in (a == "index.html") != (b == "index.html") ? a == "index.html" : a < b }
        return sorted.first { page in
            guard let html = source(page) else { return false }
            let files = linked(from: page, html: html)
            return files.scripts.contains(path) || files.styles.contains(path)
        }
    }

    /// A page's local files, as project paths.
    func linked(from page: String, html: String) -> (scripts: [String], styles: [String]) {
        let folder = (page as NSString).deletingLastPathComponent
        func resolve(_ link: String) -> String {
            folder.isEmpty ? link : ((folder as NSString).appendingPathComponent(link) as NSString).standardizingPath
        }
        let files = DevWebLinks.linkedFiles(in: html)
        return (files.scripts.map(resolve), files.styles.map(resolve))
    }

    /// The files a change to a page touches. A page with its own styles and script is three files, and
    /// most changes need one or two of them, which is a question for the model. A file the request
    /// names stays the only one.
    func webGroup(_ targets: [String], job: DevJob) async -> [String] {
        guard job.failure == nil, targets.count == 1, let first = targets.first, DevWeb.isWebFile(first), project.exists(first),
              !job.request.contains((first as NSString).lastPathComponent) else { return targets }
        let page = DevWeb.isPage(first) ? first : (pageLinking(first) ?? first)
        guard DevWeb.isPage(page), let html = source(page) else { return targets }
        let files = linked(from: page, html: html)
        let ours = { [project] (path: String) in project.read(path)?.hasPrefix(DevKit.marker) == true }
        let members = [page] + files.styles.filter { project.exists($0) && !ours($0) } + files.scripts.filter { project.exists($0) }
        guard members.count > 1 else { return targets }
        emit(.stage("Choosing the files"))
        let lines = members.map { path -> String in
            if DevWeb.isPage(path) { return "- \(path): the page's markup" }
            if path.hasSuffix(".css") { return "- \(path): how the page looks" }
            let names = (DevJS.outline(source(path) ?? "") ?? []).compactMap(\.name).prefix(14)
            return "- \(path): what the page does" + (names.isEmpty ? "" : " (\(names.joined(separator: ", ")))")
        }
        let reply = await complete(system: "You decide which files a change needs. Reply with the names of the files that have to change, one per line, and nothing else.",
                                   user: "Files:\n\(lines.joined(separator: "\n"))\n\nChange: \(job.request)\n\nWhich files have to change?", temperature: 0.1, limit: 48, quiet: true)
        var chosen = members.filter { reply.text.contains(($0 as NSString).lastPathComponent) }
        if chosen.isEmpty { chosen = members }
        for path in chosen where originals[path] == nil { originals[path] = .some(project.read(path)) }
        if chosen.count > 1 { emit(.note("This takes \(chosen.joined(separator: ", ")).")) }
        return chosen
    }

    /// What a file of a page needs to know about the others, so they still fit together after it changes.
    func webContext(for path: String) -> [String] {
        guard DevWeb.isWebFile(path) else { return [] }
        if !DevWeb.isPage(path) {
            guard let page = pageLinking(path), let html = source(page) else { return [] }
            if path.hasSuffix(".js") {
                let elements = DevWebLinks.elements(in: html)
                return elements.isEmpty ? [] : ["\(page) has these elements:\n\(DevWebLinks.describe(elements))"]
            }
            return ["\(page) uses:\n\(DevWebLinks.styleHooks(in: html))"]
        }
        guard let html = source(path) else { return [] }
        var parts: [String] = []
        for script in linked(from: path, html: html).scripts {
            guard let code = source(script) else { continue }
            let ids = Array(Set(DevWebLinks.idReferences(in: code).map(\.id))).sorted()
            if !ids.isEmpty { parts.append("\(script) uses these ids, so keep them: \(ids.map { "#\($0)" }.joined(separator: " "))") }
        }
        return parts
    }

    /// A page after a rewrite: still linked to its own files, and with nothing from the internet that
    /// code can do without.
    func tidied(_ page: String, was original: String?) -> String {
        var html = page
        if let original { html = DevWebLinks.keepingLinks(from: original, in: html) }
        let offline = DevWebLinks.offline(html)
        html = offline.html
        for note in offline.notes { noteOnce(note) }
        if offline.usesKit, versions[DevKit.cssName] == nil, project.read(DevKit.cssName)?.hasPrefix(DevKit.marker) != true {
            if !project.exists(DevKit.cssName) {
                originals[DevKit.cssName] = .some(nil)
                record(DevKit.css, for: DevKit.cssName)
            }
        }
        return html
    }

    func noteOnce(_ note: String) {
        guard !noted.contains(note) else { return }
        noted.insert(note)
        emit(.note(note))
    }

    /// The code in a reply for a script or a style sheet.
    func webCode(_ reply: String, path: String) -> String? {
        let languages = path.hasSuffix(".js") ? ["javascript", "js", "jsx", "mjs"] : path.hasSuffix(".css") ? ["css"] : []
        guard var code = Self.block(in: reply, languages: languages) else { return nil }
        if path.hasSuffix(".js") {
            code = code.replacingOccurrences(of: #"(?i)^\s*<script[^>]*>\s*|\s*</script>\s*$"#, with: "", options: .regularExpression)
        } else if path.hasSuffix(".css") {
            code = code.replacingOccurrences(of: #"(?i)^\s*<style[^>]*>\s*|\s*</style>\s*$"#, with: "", options: .regularExpression)
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed + "\n"
    }

    /// Checks a page against its scripts, mending what code can, and returns what's left to fix.
    func linkCheck(_ page: String) -> DevFailure? {
        guard let html = source(page) else { return nil }
        let folder = (page as NSString).deletingLastPathComponent
        var files = [page: html]
        var paths: [String: String] = [:]
        for link in DevWebLinks.linkedFiles(in: html).scripts {
            let path = folder.isEmpty ? link : ((folder as NSString).appendingPathComponent(link) as NSString).standardizingPath
            guard let code = source(path) else { continue }
            files[link] = code
            paths[link] = path
        }
        let result = DevWebLinks.check(page: page, files: files)
        for (link, text) in result.files where link != page && text != files[link] {
            guard let path = paths[link] else { continue }
            if originals[path] == nil { originals[path] = .some(project.read(path)) }
            record(text, for: path)
        }
        for note in result.notes { noteOnce(note) }
        guard var failure = result.failure else { return nil }
        if let file = failure.file, let path = paths[file] { failure.file = path }
        return failure
    }

    func pageKind(_ page: String, job: DevJob) -> DevPageKind {
        let html = source(page) ?? ""
        let scripts = linked(from: page, html: html).scripts.compactMap(source)
        if isV2 {
            // An app that animates something is still an app: v1 took any animation for a game and never used it.
            if isGameRequest(job.request) { return .game }
            if builtApp { return .app }
            let tags = DevWebLinks.tags(in: html)
            let hasCanvas = tags.contains { $0.name == "canvas" }
            let hasFields = tags.contains { ["input", "textarea", "select", "form"].contains($0.name) }
            if hasCanvas, !hasFields, ([html] + scripts).contains(where: { $0.contains("requestAnimationFrame") }) { return .game }
            return tags.contains { ["input", "textarea", "select", "button", "form"].contains($0.name) } ? .app : .page
        }
        if Self.isGame(job.request) || ([html] + scripts).contains(where: { $0.contains("requestAnimationFrame") }) { return .game }
        if builtApp { return .app }
        let controls = DevWebLinks.tags(in: html).contains { ["input", "textarea", "select", "button", "form"].contains($0.name) }
        return controls ? .app : .page
    }

    /// Edits a long script through just the functions that matter, with the rest shown as a list.
    func editScriptPieces(of current: String, path: String, task: String, job: DevJob, note: String?, temperature: Double, failure: DevFailure? = nil) async -> String? {
        guard let pieces = DevJS.outline(current) else { return nil }
        let named = pieces.filter(\.isDeclaration)
        let words = Set(task.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init))
        var chosen = named.filter { words.contains(($0.name ?? "").lowercased()) }
        if let line = failure?.line, let holder = pieces.last(where: { $0.start <= line && line <= $0.end }), !chosen.contains(holder) {
            chosen.insert(holder, at: 0)
        }
        if chosen.isEmpty {
            let reply = await complete(system: "You choose which functions a change belongs in. Reply with up to two function names, or NEW if it needs a new function.",
                                       user: "\(path) has:\n\(named.map(\.signature).joined(separator: "\n"))\n\nChange: \(task)\n\nWhich functions?", temperature: 0.1, limit: 24, quiet: true)
            chosen = Array(named.filter { piece in piece.name.map { reply.text.contains($0) } ?? false }.prefix(2))
        }
        // What a change shows on the page nearly always goes through render().
        if failure == nil, chosen.count < 3, let render = named.first(where: { $0.name == "render" }), !chosen.contains(render) { chosen.append(render) }
        var parts = ["\(path) defines:\n" + named.map(\.signature).joined(separator: "\n")]
        parts += webContext(for: path)
        if !chosen.isEmpty { parts.append("The part that matters:\n\(fence(chosen.map(\.text).joined(separator: "\n\n"), path: path))") }
        if let failure { parts.append("Trying it gives:\n```\n\(Self.quoted(failure.title))\n```") }
        parts.append("Task: \(task)")
        if let note, !note.isEmpty { parts.append(note) }
        parts.append("Reply with only the functions you change or add, each one complete, and any new addEventListener lines.")
        let reply = await complete(system: rules(path, partial: true), user: parts.joined(separator: "\n\n"), temperature: temperature)
        if Task.isCancelled { return nil }
        if let error = reply.error {
            backendError = error
            return nil
        }
        guard !reply.cutOff, let code = webCode(reply.text, path: path), !DevWeb.hasPlaceholders(code) else { return nil }
        return DevJS.merge(code, into: current)
    }

    // MARK: - Reading replies

    /// The fenced block in a reply in one of these languages, the largest if there are several, or else
    /// the largest block of any kind. A reply with no fence at all is taken whole.
    static func block(in reply: String, languages: [String]) -> String? {
        var blocks: [(tag: String, text: String)] = []
        var current: [String]?
        var tag = ""
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = current {
                    blocks.append((tag, open.joined(separator: "\n")))
                    current = nil
                } else {
                    tag = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").first ?? "")
                    current = []
                }
            } else {
                current?.append(line)
            }
        }
        if let open = current { blocks.append((tag, open.joined(separator: "\n"))) }
        if blocks.isEmpty {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let wanted = blocks.filter { languages.contains($0.tag) }
        let pick = (wanted.isEmpty ? blocks : wanted).max { $0.text.count < $1.text.count }
        let text = pick?.text.trimmingCharacters(in: .newlines) ?? ""
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
    }

    /// Only what goes inside <body>, from a reply that may hold a whole page anyway.
    static func appBody(from reply: String) -> String? {
        guard var html = block(in: reply, languages: ["html", "htm", "xml"]) else { return nil }
        if let inner = html.groups(of: #"(?is)<body[^>]*>(.*?)(?:</body>|$)"#)?[1] {
            html = inner
        } else {
            html = html.replacingOccurrences(of: #"(?is)<!doctype[^>]*>|<html[^>]*>|</html>|<head[^>]*>.*?</head>"#, with: "", options: .regularExpression)
        }
        html = html.replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>|<script\b[^>]*/?>|<link\b[^>]*>|<meta\b[^>]*>|<title>.*?</title>"#, with: "", options: .regularExpression)
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("<") ? trimmed : nil
    }

    /// Moves any <style> the markup carried out of it, for the style sheet.
    static func splittingStyles(from body: String) -> (body: String, styles: String) {
        var styles: [String] = []
        let regex = try? NSRegularExpression(pattern: #"(?is)<style\b[^>]*>(.*?)</style>"#)
        for match in regex?.matches(in: body, range: NSRange(body.startIndex..., in: body)) ?? [] {
            if let range = Range(match.range(at: 1), in: body) { styles.append(String(body[range]).trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let rest = body.replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
        return (rest.trimmingCharacters(in: .whitespacesAndNewlines), styles.joined(separator: "\n"))
    }

    /// The same id twice makes a script find only the first, so later ones get a number, before any
    /// script is written against them.
    static func uniqueIds(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\bid\s*=\s*(["'])([^"']+)\1"#) else { return html }
        var counts: [String: Int] = [:]
        var renames: [(range: NSRange, id: String)] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 2), in: html) else { continue }
            let id = String(html[range])
            counts[id, default: 0] += 1
            if let count = counts[id], count > 1 { renames.append((match.range(at: 2), "\(id)-\(count)")) }
        }
        let result = NSMutableString(string: html)
        for rename in renames.reversed() { result.replaceCharacters(in: rename.range, with: rename.id) }
        return result as String
    }

    /// A model's style sheet without the few rules that wreck a page: the body made a centred flex box
    /// of fixed height, which squeezes the app and cuts it off, and anything fetched from the internet.
    static func saferStyles(_ css: String) -> String {
        var text = css.replacingOccurrences(of: #"(?im)^\s*@import[^;]*;\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)[\w-]+\s*:[^;{}]*url\(\s*["']?(?:https?:)?//[^;{}]*;?"#, with: "", options: .regularExpression)
        guard let rule = try? NSRegularExpression(pattern: #"(^|\})(\s*)(html|body|html\s*,\s*body|body\s*,\s*html)\s*\{([^{}]*)\}"#, options: .caseInsensitive) else { return text }
        for match in rule.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 4), in: text) else { continue }
            let kept = text[range].split(separator: ";").filter { declaration in
                let property = declaration.split(separator: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let value = declaration.split(separator: ":").dropFirst().joined(separator: ":").lowercased()
                if ["justify-content", "align-items", "place-items", "height", "max-height"].contains(property) { return false }
                if property == "display", value.contains("flex") || value.contains("grid") { return false }
                if property == "overflow", value.contains("hidden") { return false }
                return true
            }
            text.replaceSubrange(range, with: kept.joined(separator: ";"))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func slug(_ name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(5)
        return words.isEmpty ? "app" : words.joined(separator: "-")
    }

    static func leaf(_ path: String) -> String { (path as NSString).lastPathComponent }
}
