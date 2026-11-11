import Foundation

/// The model with the harness off, the way someone would use it in a chat: the project's files and the
/// request in, one reply out, and every file in that reply saved as it came. Nothing is planned, run,
/// checked or fixed. It does hear the same facts about where its code runs, so a comparison measures
/// what the harness does rather than what the model wasn't told.
enum DevOneReply {
    static let system = """
    You are a helpful coding assistant. What you write runs on this computer, offline: web pages open in a browser with no internet, \
    and Python has only its standard library and no display.
    """

    struct File: Equatable {
        var path: String
        var text: String
    }

    static func prompt(for request: String, project: DevProject, budget: Int, failure: DevFailure? = nil) -> String {
        var parts: [String] = []
        var left = budget * 35 / 10
        for entry in project.entries() where !entry.isFolder {
            guard let text = project.read(entry.path), text.count < left else { continue }
            parts.append("\(entry.path):\n```\n\(DevAgent.quoted(text))\n```")
            left -= text.count
        }
        parts.append(request)
        if let failure { parts.append("Running it gives:\n```\n\(DevAgent.quoted(String(failure.output.suffix(1_200))))\n```") }
        parts.append("Reply with each file in full, in its own code block, with the file's name on the line just before the block.")
        return parts.joined(separator: "\n\n")
    }

    private static let named = #"([\w][\w./-]*\.(?:html?|css|js|mjs|py|json|md|txt|csv|svg))\b"#

    /// The files in a reply, named the way models name them: on the line before the block, in the
    /// block's opening line, or in a comment at its top. A block with no name gets the one the page
    /// links it by, or the usual one for its language.
    static func files(in reply: String) -> [File] {
        struct Block { var tag: String; var name: String?; var lines: [String] }
        var blocks: [Block] = []
        var current: Block?
        var recent: [String] = []
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = current {
                    blocks.append(open)
                    current = nil
                    recent = []
                } else {
                    let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    let tag = String(info.lowercased().split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "{" }).first ?? "")
                    var name = info.groups(of: named)?[1]
                    if name == nil, let before = recent.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { name = before.groups(of: named)?[1] }
                    current = Block(tag: tag, name: name, lines: [])
                }
            } else if current != nil {
                current?.lines.append(line)
            } else {
                recent.append(line)
                if recent.count > 3 { recent.removeFirst() }
            }
        }
        if let open = current { blocks.append(open) }

        var found: [File] = []
        func add(_ path: String, _ text: String) {
            found.removeAll { $0.path == path }
            found.append(File(path: path, text: text))
        }
        var unnamed: [Block] = []
        for var block in blocks {
            let text = block.lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if block.name == nil, let first = block.lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               first.matches(#"^\s*(//|/\*|<!--|#)"#) {
                block.name = first.groups(of: named)?[1]
            }
            if let name = block.name.map(clean), !name.isEmpty {
                add(name, text + "\n")
            } else {
                block.lines = text.components(separatedBy: "\n")
                unnamed.append(block)
            }
        }
        // The rest by language, using the names a page links them by where there's a page.
        let page = found.first { DevWeb.isPage($0.path) }?.text ?? unnamed.first { ["html", "htm"].contains($0.tag) }?.lines.joined(separator: "\n") ?? ""
        let links = DevWebLinks.linkedFiles(in: page)
        var styles = links.styles.filter { name in !found.contains { $0.path == name } }
        var scripts = links.scripts.filter { name in !found.contains { $0.path == name } }
        var pages = 0
        for block in unnamed {
            let text = block.lines.joined(separator: "\n") + "\n"
            switch block.tag {
            case "html", "htm":
                pages += 1
                add(pages == 1 && !found.contains { $0.path == "index.html" } ? "index.html" : "page\(pages).html", text)
            case "css":
                add(styles.isEmpty ? "styles.css" : styles.removeFirst(), text)
            case "javascript", "js":
                add(scripts.isEmpty ? "script.js" : scripts.removeFirst(), text)
            case "python", "py", "python3":
                add(found.contains { $0.path == "main.py" } ? "program.py" : "main.py", text)
            default:
                continue
            }
        }
        return found
    }

    private static func clean(_ name: String) -> String {
        var path = name.trimmingCharacters(in: CharacterSet(charactersIn: "`*\"' "))
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    static func run(request: String, project: DevProject, setup: DevSetup, failure: DevFailure? = nil,
                    emit: @escaping @Sendable (DevEvent) -> Void) async -> DevOutcome {
        emit(.stage("Asking the model once"))
        let user = prompt(for: request, project: project, budget: setup.context / 2, failure: failure)
        let used = DevAgent.tokens(system) + DevAgent.tokens(user) + 64
        // 8,192 with v1 or v2 chosen. With v3 the plain model gets the room v3 gives itself, so that a
        // comparison measures the harness and not the cap.
        let cap = DevBudget.of(setup.version, context: setup.context).oneReply
        let chat = ChatRequest(model: setup.model, messages: [ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: user)],
                               temperature: 0.2, contextLength: setup.context, maxTokens: min(cap, max(setup.context - used, 512)), think: setup.think)
        var text = ""
        var parser = ThinkTagParser()
        var chunks = 0
        do {
            for try await event in setup.backend.chat(chat) {
                if Task.isCancelled { break }
                if case .content(let chunk) = event {
                    text += parser.feed(chunk).answer
                    chunks += 1
                    if chunks % 6 == 0 {
                        emit(.writing(text))
                        if DevAgent.isLooping(text) { break }
                    }
                }
            }
            text += parser.flush().answer
        } catch {
            return DevOutcome(text: "The model couldn't answer: \(error.localizedDescription)", calls: 1)
        }
        if Task.isCancelled { return DevOutcome(text: "Stopped. Nothing changed.", stopped: true, calls: 1) }

        let files = files(in: text).filter { (try? project.url(for: $0.path)) != nil }
        guard !files.isEmpty else {
            let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return DevOutcome(text: answer.isEmpty ? "The model gave no reply." : answer, calls: 1)
        }
        var changes: [DevChange] = []
        for file in files {
            let before = project.read(file.path)
            guard before != file.text else { continue }
            do {
                try project.write(file.text, to: file.path)
                changes.append(DevChange(path: file.path, before: before, after: file.text))
            } catch {
                emit(.note("Couldn't save \(file.path): \(error.localizedDescription)"))
            }
        }
        let lines = changes.map { change -> String in
            let size = change.after.split(separator: "\n", omittingEmptySubsequences: false).count
            return change.isNew ? "Created \(change.path) (\(size) lines)." : "Updated \(change.path) (+\(change.counts.added) −\(change.counts.removed))."
        }
        let page = changes.first { $0.path == "index.html" }?.path ?? changes.first { DevWeb.isPage($0.path) }?.path
        let summary = (["One reply from the model, saved as it came."] + lines + ["Nothing was run or checked."]).joined(separator: " ")
        return DevOutcome(text: summary, changes: changes, page: page, calls: 1)
    }
}
