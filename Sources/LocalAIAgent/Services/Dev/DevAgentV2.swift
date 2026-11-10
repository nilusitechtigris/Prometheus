import Foundation

/// Which coding harness works on a request. Every version stays in the app, so Compare and the measuring runs
/// can show what each adds on the same model.
enum DevHarnessVersion: String, CaseIterable, Identifiable, Sendable {
    case v1, v2

    var id: String { rawValue }
    var short: String { rawValue }

    var name: String {
        switch self {
        case .v1: return "Agent"
        case .v2: return "Checked build"
        }
    }

    var title: String { "\(short) \(name)" }

    var summary: String {
        switch self {
        case .v1: return "plans, writes each file, tries it and fixes it"
        case .v2: return "builds and fixes like v1, then checks what a first use would show"
        }
    }

    /// What Dev mode uses unless someone picks another. v2 has no measured run yet, so v1 stays.
    static let recommended = DevHarnessVersion.v1
}

/// Dev harness v2. It is v1 with the gaps closed that showed in v1's own code and runs:
///
/// - v1 called an app done if anything on the page changed once. Whether what you typed showed up, whether a
///   button did anything and whether the page fitted the window were left for Compare to find afterwards.
///   v2 looks for those itself once the app works, and gets one try at each.
/// - v1 kept only the newest version of each file, so a fix that made things worse replaced a better attempt.
///   v2 remembers how far each attempt got and goes back to the best one.
/// - "A quiz with a button to play again" was built as a canvas game, because of the word "play", and an app
///   that animated anything was tried as a game and never used.
/// - The plan was capped at six parts and six actions, so a longer request lost features before any code.
///
/// The extra looks can only improve on what v1 would have saved. They run after the page already works by
/// v1's own standard, each gets one fix, and a fix that doesn't cure it, or breaks anything, is thrown away.
/// What's left is said in the report instead of being called a failure. They also only run on an app this job
/// built, never on someone's existing page.
///
/// Nothing here changes v1: every difference sits behind `setup.version`.
extension DevAgent {
    var isV2: Bool { setup.version == .v2 }

    /// v1's rule, without the uses of "play" that belong to apps: play again, a play button, play the song.
    static func isGameStrict(_ request: String) -> Bool {
        let harmless = #"\bplay(s|ed|ing)?\s+(again|next|it again|the (song|video|track|sound|audio|music|clip))\b|\bplay\s*/\s*pause\b|\bplay\s+button\b|\bpress\s+play\b|\bplayback\b"#
        return isGame(request.lowercased().replacingOccurrences(of: harmless, with: " ", options: .regularExpression))
    }

    func isGameRequest(_ request: String) -> Bool { isV2 ? Self.isGameStrict(request) : Self.isGame(request) }

    // MARK: - What an app that works still lacks

    struct Issue {
        /// The same thing found again has the same key.
        let key: String
        /// A few words for the report, when it couldn't be fixed.
        let short: String
        let failure: DevFailure
    }

    /// Whether the page takes text and has a list to put it in, so typing something should make it show up. The
    /// page check types words only into text fields, so a number field or a login form doesn't count.
    static func keepsAList(_ html: String) -> Bool {
        let tags = DevWebLinks.tags(in: html)
        let typed = tags.contains { tag in
            tag.name == "textarea" || (tag.name == "input" && ["", "text"].contains(tag.attributes["type"]?.lowercased() ?? ""))
        }
        let listed = tags.contains { tag in
            ["ul", "ol", "tbody"].contains(tag.name)
                || (tag.attributes["id"]?.lowercased().matches(#"(^|-)(list|items|entries|history|cart|tasks|notes|orders)(-|$)"#) ?? false)
        }
        return typed && listed
    }

    /// Forms and buttons on the page that no script mentions. A script that listens on a container, or on every
    /// button at once, reaches controls it never names, so with one of those nothing is said.
    static func idleControls(html: String, code: String) -> [(id: String, tag: String)] {
        guard !code.isEmpty else { return [] }
        if code.matches(#"\.target\b|closest\(|querySelectorAll\(|getElementsBy(TagName|ClassName)|document\.forms|querySelector\(\s*["'`](form|button)"#) { return [] }
        let tags = DevWebLinks.tags(in: html)
        let hasForm = tags.contains { $0.name == "form" }
        return tags.compactMap { tag in
            guard tag.name == "form" || tag.name == "button", let id = tag.attributes["id"], !id.isEmpty else { return nil }
            // Something written on the tag itself already says what it does.
            if tag.attributes.keys.contains(where: { $0.hasPrefix("on") || $0.hasPrefix("data-") }) { return nil }
            // A button in a form sends the form, which the form's own listener answers.
            if tag.name == "button", hasForm, tag.attributes["type"]?.lowercased() != "button" { return nil }
            if ["#\(id)", "\"\(id)\"", "'\(id)'", "`\(id)`"].contains(where: code.contains) { return nil }
            if (tag.attributes["class"] ?? "").split(separator: " ").contains(where: { code.contains(".\($0)") }) { return nil }
            return (id, tag.name)
        }
    }

    /// Everything a first use would show that's still wrong with a page that opens and answers, by v1's
    /// standard. Empty unless the last try of the page got that far.
    func openIssues(page: String, kind: DevPageKind) -> [Issue] {
        guard let report = lastReport, report.failure == nil, report.loaded else { return [] }
        let html = source(page) ?? ""
        let files = linked(from: page, html: html)
        let scripts = files.scripts.filter { source($0) != nil }
        let script = scripts.first ?? page
        let styles = files.styles.first { path in source(path).map { !$0.hasPrefix(DevKit.marker) } ?? false } ?? page
        let inline = html.groups(of: #"(?s)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>"#)?[1] ?? ""
        let code = (scripts.compactMap(source) + [inline]).joined(separator: "\n")
        let elements = DevWebLinks.describe(DevWebLinks.elements(in: html))
        let hasCanvas = DevWebLinks.tags(in: html).contains { $0.name == "canvas" }
        var issues: [Issue] = []
        // A drawing pad changes its canvas, which the page check's signature of the page can't see.
        if kind == .app, report.controls > 0, !hasCanvas {
            if report.used == false {
                issues.append(Issue(key: "unused", short: "pressing its buttons changed nothing I could see",
                                    failure: DevFailure(file: script, kind: "Advice",
                                                        message: "The page opens, but filling in its fields and pressing its buttons changed nothing on it. Every form and button has to change the data and draw the page again.",
                                                        output: elements)))
            } else if report.used == true, report.showedTyped == false, Self.keepsAList(html) {
                issues.append(Issue(key: "typed", short: "what I typed into it never showed up on the page",
                                    failure: DevFailure(file: script, kind: "Advice",
                                                        message: "I typed into the page's text fields and pressed its buttons, and at no point did what I typed show up on the page. Adding something has to put it in the data, and the page has to draw it in the list.",
                                                        output: elements)))
            }
            let name = (script as NSString).lastPathComponent
            for idle in Self.idleControls(html: html, code: code) {
                issues.append(Issue(key: "idle:\(idle.id)", short: "nothing in \(name) uses the \(idle.tag) #\(idle.id), so it may do nothing",
                                    failure: DevFailure(file: script, kind: "Advice",
                                                        message: "\(page) has a \(idle.tag) with the id \(idle.id), but \(name) never mentions it, so pressing it probably does nothing. Make it work in \(name).",
                                                        output: elements)))
            }
        }
        // A game's canvas is as wide as it was asked to be.
        if kind != .game, !report.fits {
            issues.append(Issue(key: "fits", short: "something on it is wider than the window",
                                failure: DevFailure(file: styles, kind: "Advice",
                                                    message: "Something on the page is wider than the window, so at 800 pixels wide it scrolls sideways. Give nothing a fixed width wider than the page, and let wide rows wrap.",
                                                    output: "")))
        }
        return issues
    }

    /// Once a new app works, tries to cure up to two of the things a first use would show. Each gets one fix.
    /// The fix only stays if the page still works and that thing is gone. Otherwise the working version comes
    /// back and the report says what was left.
    func improve(_ job: DevJob, _ worked: Verdict, round: inout Int) async -> Verdict {
        guard isV2, builtApp, job.failure == nil, let page = triedPage else { return worked }
        var verdict = worked
        for _ in 0..<2 {
            if Task.isCancelled || backendError != nil { break }
            guard let issue = openIssues(page: page, kind: pageKind(page, job: job)).first(where: { !raisedKeys.contains($0.key) }) else { break }
            raisedKeys.insert(issue.key)
            let kept = (versions: versions, order: order, report: lastReport)
            emit(.note("It works. One more look: \(issue.short)."))
            var cured = false
            if let path = issue.failure.file, let before = source(path) {
                round += 1
                if let fixed = await fix(path, failure: issue.failure, job: job, round: round, repeats: 1), fixed != before {
                    record(fixed, for: path)
                    let again = await verify(job)
                    if case .worked = again, !openIssues(page: page, kind: pageKind(page, job: job)).contains(where: { $0.key == issue.key }) {
                        verdict = again
                        cured = true
                    }
                }
            }
            if !cured {
                versions = kept.versions
                order = kept.order
                lastReport = kept.report
                unresolved.append(issue.short)
                emit(.note("The fix for that didn't hold, so I kept the version that works."))
            }
        }
        return verdict
    }

    // MARK: - Keeping the best attempt

    /// How far an attempt got. A page that opened is ranked by the lines Compare scores. One that was never
    /// opened, because its files didn't fit together, still got further than one that opened and crashed.
    static func progress(_ verdict: Verdict, report: DevPageReport?) -> Int {
        switch verdict {
        case .worked: return 100
        case .needsInput: return 90
        case .notRun: return 0
        case .failed(let failure):
            guard let report else { return failure.kind == "SyntaxError" ? 0 : 5 }
            guard report.loaded else { return 2 + (report.hasContent ? 1 : 0) }
            let lines = [report.hasContent && !report.rawTemplate, report.styled, report.offline,
                         report.used == true || report.controls == 0, report.fits]
            return 10 + lines.filter { $0 }.count
        }
    }

    /// Remembers this attempt if it got at least as far as any before it, so a tie goes to the newer one.
    func noteAttempt(_ verdict: Verdict) {
        guard isV2 else { return }
        let score = Self.progress(verdict, report: lastReport)
        if score >= (best?.score ?? -1) { best = (score, versions, order, verdict) }
    }

    /// When the fixing ends on something that got less far than an earlier attempt, goes back to that one.
    func bestOf(_ verdict: Verdict) -> Verdict {
        guard isV2, case .failed = verdict, let best, best.score > Self.progress(verdict, report: lastReport) else { return verdict }
        versions = best.versions
        order = best.order
        emit(.note("The last fix got less far than an earlier attempt, so I kept the earlier one."))
        return best.verdict
    }

    // MARK: - A plan with room for the request

    /// What the user can do comes first, since that's what gets cut when a reply runs long.
    func planAppV2(_ job: DevJob, data: [String]) async -> AppPlan {
        let system = """
        You plan small web apps that run as one page in a browser, offline. Reply in exactly this form and nothing else:
        NAME: the app's name, 1 to 4 words
        ACTIONS: everything the user can do, separated by ;
        PARTS: the parts of the page, top to bottom, separated by ;
        DATA: what the app keeps track of, and the fields of each thing
        Cover everything the request asks for and add nothing it doesn't: 3 to 10 actions and 3 to 8 parts, a few words each.
        """
        let reply = await complete(system: system, user: (data + ["App: \(job.request)"]).joined(separator: "\n\n"), temperature: 0.2, limit: 600)
        return AppPlan.parse(reply.text, limit: 600)
    }
}
