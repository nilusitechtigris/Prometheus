import Foundation
import Observation

/// Whether the harness may use the web. Search terms and page addresses are what the harness sends off this
/// Mac, so nothing goes out until the person has said yes: to the search on screen, for good, or to a test
/// they started. Every web request the harness makes asks here first (see `WebTools`).
///
/// A yes covers the search it was shown and the pages that search finds, and nothing else. A different
/// search in the same reply asks again, and so does a page no allowed search returned.
@MainActor
@Observable
final class WebConsent {
    static let shared = WebConsent()

    enum Policy: String, CaseIterable, Identifiable {
        case ask, allowed, off

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ask: return "Ask first"
            case .allowed: return "Always"
            case .off: return "Never"
            }
        }
    }

    enum Answer { case once, always, notNow }

    /// What's about to leave this Mac, for the question on screen.
    struct Request: Identifiable, Equatable {
        let id = UUID()
        /// The search terms, or the address of the page, exactly as they'd be sent.
        let detail: String
        let isSearch: Bool
    }

    private struct Waiter {
        let request: Request
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// True inside a test the person started, who was told it looks things up. It belongs to the test's own
    /// task, so a chat reply running at the same moment doesn't share it.
    @TaskLocal static var inTest = false

    private static let key = "harnessWeb"

    var policy: Policy {
        didSet {
            UserDefaults.standard.set(policy.rawValue, forKey: Self.key)
            // Changing the setting answers whatever is waiting.
            if policy != .ask { finish(allowed: policy == .allowed) }
        }
    }
    /// The question waiting for an answer, if there is one.
    private(set) var pending: Request?
    @ObservationIgnored private var waiters: [Waiter] = []
    /// Searches allowed for the reply under way, by their exact text.
    @ObservationIgnored private var allowedSearches: Set<String> = []
    /// Pages those searches found, which the same yes covers.
    @ObservationIgnored private var allowedPages: Set<String> = []
    /// True once the person said Not now: nothing more is asked or sent for this reply.
    @ObservationIgnored private var declined = false
    /// Set only by automated checks, which have nobody to ask. It's never saved.
    @ObservationIgnored private var override: Policy?

    private init() {
        policy = Policy(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .ask
        #if DEBUG
        // LOCALAI_WEB=allowed|off|ask sets it for this run only.
        if let forced = Policy(rawValue: ProcessInfo.processInfo.environment["LOCALAI_WEB"] ?? "") { override = forced }
        #endif
    }

    private var effective: Policy { override ?? policy }

    /// An address as it's compared: without the parts `WebTools.open` drops before it sends anything.
    nonisolated static func normalized(_ address: String) -> String {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return address }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url?.absoluteString ?? address
    }

    private func covered(_ request: Request) -> Bool {
        request.isSearch ? allowedSearches.contains(request.detail) : allowedPages.contains(Self.normalized(request.detail))
    }

    /// Asked before every request. Waits for the person when the setting is Ask first.
    func mayUseWeb(detail: String, isSearch: Bool) async -> Bool {
        if Task.isCancelled { return false }
        if Self.inTest { return true }
        switch effective {
        case .allowed: return true
        case .off: return false
        case .ask:
            let request = Request(detail: detail, isSearch: isSearch)
            if declined { return false }
            if covered(request) { return true }
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    waiters.append(Waiter(request: request, continuation: continuation))
                    if pending == nil { pending = request }
                }
            } onCancel: {
                // Stop was pressed, so nobody is waiting for the lookup any more.
                Task { @MainActor in self.finish(allowed: false) }
            }
        }
    }

    /// The pages a search found. A yes to that search covers reading them.
    func noteResults(_ addresses: [String], of search: String) {
        guard allowedSearches.contains(search) else { return }
        allowedPages.formUnion(addresses.map(Self.normalized))
    }

    func answer(_ answer: Answer) {
        switch answer {
        case .always:
            policy = .allowed
        case .notNow:
            declined = true
            finish(allowed: false)
        case .once:
            guard let asked = pending else { return }
            if asked.isSearch { allowedSearches.insert(asked.detail) } else { allowedPages.insert(Self.normalized(asked.detail)) }
            // Whoever was waiting on exactly this gets its yes. Anything else still has to be asked about.
            let (answered, rest) = (waiters.filter { covered($0.request) }, waiters.filter { !covered($0.request) })
            waiters = rest
            pending = rest.first?.request
            for waiter in answered { waiter.continuation.resume(returning: true) }
        }
    }

    /// Answers everything that's waiting the same way, and takes the question down.
    private func finish(allowed: Bool) {
        pending = nil
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.continuation.resume(returning: allowed) }
    }

    /// A new reply starts with nothing allowed, so it asks if it needs the web.
    func beginReply() {
        allowedSearches = []
        allowedPages = []
        declined = false
    }

    /// The reply is over: a question still on screen has nothing left to ask about.
    func endReply() {
        finish(allowed: false)
        beginReply()
    }

    /// A test looks things up without stopping to ask, so whoever starts one is told first.
    var testNeedsAsking: Bool { effective != .allowed }

    /// Where searches go, said the same way everywhere.
    static let destinations = "Wikipedia, Stack Overflow, arXiv and MDN"

    #if DEBUG
    /// For automated checks that make real requests with nobody at the keyboard.
    func allowForChecks() { override = .allowed }

    /// The gate with nobody at the keyboard: each answer, and what it does to the next request.
    static func selfCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let consent = WebConsent()
        let saved = UserDefaults.standard.string(forKey: key)
        consent.override = nil
        defer {
            // The check must leave the real setting as it found it.
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        func shown() async { for _ in 0..<200 where consent.pending == nil { try? await Task.sleep(for: .milliseconds(5)) } }
        func gone() async { for _ in 0..<200 where consent.pending != nil { try? await Task.sleep(for: .milliseconds(5)) } }

        /// Asks, and answers as soon as the question is on screen.
        func ask(_ detail: String, search: Bool = true, _ reply: Answer) async -> Bool {
            async let allowed = consent.mayUseWeb(detail: detail, isSearch: search)
            await shown()
            consent.answer(reply)
            return await allowed
        }
        /// Asks something that should be settled without a question.
        func quiet(_ detail: String, search: Bool = true) async -> Bool? {
            let allowed = await consent.mayUseWeb(detail: detail, isSearch: search)
            return consent.pending == nil ? allowed : nil
        }
        let page = "https://en.wikipedia.org/wiki/Tungsten"

        consent.policy = .off
        expect("Never: refused without asking", await quiet("x") == false)
        consent.policy = .allowed
        expect("Always: allowed without asking", await quiet("x") == true)

        consent.policy = .ask
        consent.beginReply()
        expect("Ask first, Not now: refused", await ask("tungsten atomic number", .notNow) == false)
        let laterSearch = await quiet("another search"), laterPage = await quiet(page, search: false)
        expect("after Not now, the rest of that reply is refused without asking", laterSearch == false && laterPage == false)
        consent.endReply()

        consent.beginReply()
        expect("Ask first, Allow once: allowed", await ask("tungsten atomic number", .once))
        expect("the same search again doesn't ask", await quiet("tungsten atomic number") == true)
        consent.noteResults([page + "?utm=1#top"], of: "tungsten atomic number")
        expect("a page that search found is covered by the same yes", await quiet(page, search: false) == true)
        expect("a different search in the same reply asks again", await ask("element 74 name", .notNow) == false)
        consent.endReply()

        consent.beginReply()
        let searchAllowed = await ask("tungsten", .once)
        let strayPage = await ask("https://en.wikipedia.org/wiki/Tin", search: false, .notNow)
        expect("a yes to one search doesn't cover a page it didn't find", searchAllowed && !strayPage)
        consent.endReply()

        consent.beginReply()
        consent.noteResults([page], of: "a search nobody allowed")
        expect("results of a search nobody allowed cover nothing", await ask(page, search: false, .notNow) == false)
        consent.endReply()

        consent.beginReply()
        expect("the next reply asks again, and the setting is still Ask first", await ask("tungsten atomic number", .notNow) == false && consent.policy == .ask)
        consent.endReply()

        consent.beginReply()
        let both = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<2 { group.addTask { await consent.mayUseWeb(detail: "same search", isSearch: true) } }
            await shown()
            try? await Task.sleep(for: .milliseconds(30))
            consent.answer(.once)
            var answers: [Bool] = []
            for await answer in group { answers.append(answer) }
            return answers
        }
        expect("the same search asked twice at once gets one question and one answer", both == [true, true] && consent.pending == nil)
        consent.endReply()

        consent.beginReply()
        async let first = consent.mayUseWeb(detail: "search one", isSearch: true)
        await shown()
        async let second = consent.mayUseWeb(detail: "search two", isSearch: true)
        try? await Task.sleep(for: .milliseconds(30))
        consent.answer(.once)
        let firstAnswer = await first
        let nextUp = consent.pending?.detail
        consent.answer(.notNow)
        let secondAnswer = await second
        expect("two different searches at once are asked about one after the other", firstAnswer && nextUp == "search two" && !secondAnswer)
        consent.endReply()

        consent.beginReply()
        let stopped = Task { await consent.mayUseWeb(detail: "z", isSearch: true) }
        await shown()
        stopped.cancel()
        let afterStop = await stopped.value
        await gone()
        expect("Stop while it's asking: refused, and the question goes away", afterStop == false && consent.pending == nil)
        consent.endReply()

        consent.beginReply()
        _ = await ask("allowed before stop", .once)
        let late = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await consent.mayUseWeb(detail: "allowed before stop", isSearch: true)
        }
        expect("a reply that was stopped sends nothing more, even what it had a yes for", await late.value == false)
        consent.endReply()

        consent.beginReply()
        async let left = consent.mayUseWeb(detail: "w", isSearch: true)
        await shown()
        consent.endReply()
        let afterEnd = await left
        expect("a reply that ends while it's asking: refused", afterEnd == false && consent.pending == nil)

        consent.beginReply()
        async let waiting = consent.mayUseWeb(detail: "v", isSearch: true)
        await shown()
        consent.policy = .off
        let afterNever = await waiting
        expect("choosing Never while it's asking: refused, and the question goes away", afterNever == false && consent.pending == nil)
        consent.endReply()

        consent.policy = .ask
        consent.beginReply()
        expect("Always allow: allowed, and the setting changes", await ask("anything", .always) && consent.policy == .allowed)
        consent.endReply()
        expect("after that nothing asks", await quiet("x") == true)

        consent.policy = .off
        let inside = await WebConsent.$inTest.withValue(true) { await consent.mayUseWeb(detail: "x", isSearch: true) }
        expect("a test the person started may look things up", inside)
        expect("and only inside that test", await quiet("x") == false)
        return lines
    }
    #endif
}
