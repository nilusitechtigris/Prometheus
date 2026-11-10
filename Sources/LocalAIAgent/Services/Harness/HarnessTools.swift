import Foundation

/// The tools a model gets with the harness on. Everything they return from the web goes through
/// PromptGuard first, and they can only read: nothing here can post or change anything.
enum HarnessTools {
    static let definitions = [
        ToolDefinition(name: "web_search",
                       description: "Search Wikipedia, Stack Overflow, arXiv and MDN. Returns titles, links and snippets.",
                       parameters: [.init(name: "query", description: "What to search for")]),
        ToolDefinition(name: "open_page",
                       description: "Read a web page from a trusted site, such as a link from web_search.",
                       parameters: [.init(name: "url", description: "The full https address of the page")]),
        ToolDefinition(name: "calculate",
                       description: "Evaluate arithmetic exactly. Supports + - * / % ^, parentheses, powmod(a,b,m), gcd(a,b), lcm(a,b), comb(n,k), factorial(n) and sqrt(x).",
                       parameters: [.init(name: "expression", description: "The expression, such as powmod(3,200,1000)")]),
        ToolDefinition(name: "run_code",
                       description: "Run a short Python or JavaScript program and get what it prints. It runs in a sandbox with no internet and no access to files.",
                       parameters: [.init(name: "language", description: "python or javascript"),
                                    .init(name: "code", description: "The program, which should print its result")]),
    ]

    static let systemRules = """
    You have tools: web_search, open_page, calculate and run_code. Don't rely on memory or mental arithmetic when a tool can \
    check it: use run_code or calculate for anything computed, and web_search for any fact you aren't certain of. Then give \
    your final reply in the format the question asks for.
    """

    /// Added to the chat's system prompt when the harness is on.
    static let chatRules = """
    The harness is on for this reply, so anything above about having no internet or tools doesn't apply here. What your \
    tools found, if anything, follows the user's message. The user can't see it, so state what matters in your own words \
    without commenting on the tools, and name the source when you use a web page. If it doesn't answer the question, say so.
    """

    /// Added to the chat's system prompt for v1, where the model holds the tools itself.
    static let chatToolRules = """
    The harness is on for this reply, so anything above about having no internet or tools doesn't apply here. \
    \(systemRules) \(PromptGuard.systemRules) Name the source when you use a web page.
    """

    /// Runs one tool call. Returns what the model should read, how much the guard removed from it,
    /// and whether the call failed.
    static func run(_ call: ToolCall) async -> (text: String, removed: Int, failed: Bool) {
        switch call.name {
        case "calculate":
            let result = Calculator.evaluate(call.arguments["expression"] ?? "")
            return (result, 0, result.hasPrefix("Error"))
        case "web_search":
            let query = call.arguments["query"] ?? ""
            switch await WebTools.search(query) {
            case .success(let text):
                let safe = PromptGuard.wrap(text, source: "web search")
                return (safe.text, safe.removed, false)
            case .failure(let error): return ("The search failed: \(error.message)", 0, true)
            }
        case "run_code":
            let language = CodeRunner.Language(rawValue: call.arguments["language"]?.lowercased() ?? "") ?? .python
            let outcome = await CodeRunner.run(call.arguments["code"] ?? "", language: language)
            let safe = PromptGuard.wrap(outcome.output.isEmpty ? "The program printed nothing." : outcome.output, source: "your program")
            return (safe.text, safe.removed, !outcome.succeeded)
        case "open_page":
            let address = call.arguments["url"] ?? ""
            switch await WebTools.open(address) {
            case .success(let text):
                let safe = PromptGuard.wrap(text, source: address)
                return (safe.text, safe.removed, false)
            case .failure(let error): return ("Couldn't open that page: \(error.message)", 0, true)
            }
        default:
            return ("There is no tool called \(call.name).", 0, true)
        }
    }

    /// Marks a tool log line whose call failed.
    static let failedMark = " (failed)"
    /// Marks a tool log line whose call the gate turned down.
    static let refusedMark = " (refused)"

    /// Whether a log line is a real tool run, as opposed to a note about a step of the pipeline.
    static func isToolCall(_ line: String) -> Bool {
        !line.hasSuffix(refusedMark) && ["Searched", "Opened", "Calculated", "Ran"].contains { line.hasPrefix($0) }
    }

    /// One readable line per call, for the test results.
    static func describe(_ call: ToolCall) -> String {
        switch call.name {
        case "web_search": return "Searched: \(call.arguments["query"] ?? "")"
        case "open_page": return "Opened: \(call.arguments["url"] ?? "")"
        case "calculate": return "Calculated: \(call.arguments["expression"] ?? "")"
        case "run_code": return "Ran \(call.arguments["language"] ?? "code")"
        default: return "Tried unknown tool: \(call.name)"
        }
    }
}

/// Stops what a model reads from steering what it sends out. Once the web is in front of it, it can't search
/// again, and the only pages it can open are links it was handed, so a poisoned page can't carry your chat
/// out in a search or an address. The calculator and the sandbox can't reach the internet, so they stay open.
struct ToolGate {
    private var readTheWeb = false
    private var links: Set<String> = []

    /// Why this call isn't allowed, to tell the model. Nil when it is.
    func refusal(of call: ToolCall) -> String? {
        guard readTheWeb else { return nil }
        switch call.name {
        case "web_search":
            return "Refused: you've already read the web for this reply, so you can't search again. Answer from what you have."
        case "open_page" where !links.contains(call.arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""):
            return "Refused: you can only open a link your search returned."
        default:
            return nil
        }
    }

    /// Remembers what a call that ran brought back.
    mutating func note(_ call: ToolCall, result: String) {
        guard call.name == "web_search" || call.name == "open_page" else { return }
        readTheWeb = true
        links.formUnion(HarnessText.hits(in: result).map(\.url))
    }
}

enum WebTools {
    struct Failure: Error {
        let message: String
    }

    #if DEBUG
    nonisolated(unsafe) static var lastError = ""
    #endif

    #if DEBUG
    /// Pages for automated checks, by address, so the harness's reading can be checked without the internet.
    nonisolated(unsafe) static var stub: ((URL) -> String?)?
    #endif

    /// All web traffic goes through here.
    private static func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        #if DEBUG
        if let canned = stub?(url) {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])
            return (Data(canned.utf8), response ?? URLResponse())
        }
        if ProcessInfo.processInfo.environment["LOCALAI_WEB_VIA_CURL"] != nil { return try await fetchWithCurl(url) }
        #endif
        return try await session.data(from: url)
    }

    #if DEBUG
    /// For automated runs in sandboxes where only curl may reach the network. It doesn't follow
    /// redirects, so it can't leave the trusted sites either.
    private static func fetchWithCurl(_ url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["-s", "-m", "20", "-A", "Prometheus/1.0 (local AI test harness for macOS)", "--compressed",
                                 "-w", "\n%{http_code} %{content_type}", url.absoluteString]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            DispatchQueue.global().async {
                // Reading to the end is the wait. waitUntilExit can miss a process that has already gone.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard let newline = data.lastIndex(of: 10) else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                let status = String(decoding: data[(newline + 1)...], as: UTF8.self).split(separator: " ", maxSplits: 1).map(String.init)
                let response = HTTPURLResponse(url: url, statusCode: Int(status.first ?? "") ?? 0, httpVersion: nil,
                                               headerFields: ["Content-Type": status.count > 1 ? status[1] : ""])
                continuation.resume(returning: (Data(data[..<newline]), response ?? URLResponse()))
            }
        }
    }
    #endif

    /// How a request ends when the person hasn't allowed it. Callers look for it to say so plainly.
    static let declined = "no web lookup was allowed for this reply."
    /// The line a reply's steps show in that case, whether the setting is Never or the answer was Not now.
    static let declinedNote = "Skipped the web lookup, which wasn't allowed"

    /// The longest search sent. The harness writes searches of a few words, so this only stops a runaway one.
    static let maxQueryCharacters = 160
    private static let maxPageCharacters = 7_000
    /// How much of a page the harness searches for passages. The model only reads what it picks out.
    static let maxSearchableCharacters = 60_000
    private static let maxDownloadBytes = 3_000_000

    /// Rejects redirects that leave the trusted sites.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.map(TrustedSites.isTrusted) == true ? request : nil)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Nothing that could tie one request to another, or to this Mac's settings.
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": "Prometheus/1.0 (local AI test harness for macOS)", "Accept-Language": "en"]
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    // MARK: Opening pages

    static func open(_ address: String, limit: Int = maxPageCharacters) async -> Result<String, Failure> {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(Failure(message: "that isn't a valid address."))
        }
        // No query strings: they're how a poisoned page would get data sent out in a URL.
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        guard let url = parts.url, TrustedSites.isTrusted(url) else {
            return .failure(Failure(message: "only https pages on the trusted sites can be opened."))
        }
        guard await WebConsent.shared.mayUseWeb(detail: url.absoluteString, isSearch: false) else {
            return .failure(Failure(message: declined))
        }
        do {
            let (data, response) = try await fetch(url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(Failure(message: "the site returned an error."))
            }
            guard data.count <= maxDownloadBytes else { return .failure(Failure(message: "the page is too large.")) }
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard type.contains("html") || type.contains("text") else {
                return .failure(Failure(message: "that isn't a text page."))
            }
            let html = String(decoding: data, as: UTF8.self)
            let text = type.contains("html") ? plainText(html) : html
            return .success(String(text.prefix(limit)))
        } catch {
            #if DEBUG
            lastError = "\(error)"
            #endif
            return .failure(Failure(message: "the site couldn't be reached or redirected away from the trusted sites."))
        }
    }

    /// Reduces a page to its readable text, dropping the places instructions get hidden.
    static func plainText(_ html: String) -> String {
        var text = html
        // Most pages mark their article; everything around it is menus and boilerplate.
        if let start = html.range(of: "<main"), let end = html.range(of: "</main>", options: .backwards), start.lowerBound < end.lowerBound {
            text = String(html[start.lowerBound..<end.upperBound])
        }
        func strip(_ pattern: String, with template: String = " ") {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        strip(#"<!--.*?-->"#)
        strip(#"<(script|style|noscript|svg|nav|footer|header|aside|form|template)\b.*?</\1>"#)
        strip(#"<(\w+)\b[^>]*(\shidden\b|aria-hidden="true"|display\s*:\s*none|visibility\s*:\s*hidden|font-size\s*:\s*0)[^>]*>.*?</\1>"#)
        strip(#"</(p|div|li|tr|h[1-6]|section|article|blockquote|pre)>|<br\s*/?>"#, with: "\n")
        // Attribute values can contain ">", so a tag ends at the first one outside quotes.
        strip(#"<(?:"[^"]*"|'[^']*'|[^'">])*>"#)
        text = decodingEntities(text)
        strip(#"[ \t]+"#)
        strip(#"\s*\n\s*"#, with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodingEntities(_ text: String) -> String {
        var result = text
        let named = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—"]
        for (entity, character) in named { result = result.replacingOccurrences(of: entity, with: character) }
        if let regex = try? NSRegularExpression(pattern: #"&#(\d{1,6});"#) {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[digits]), let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(whole, with: String(scalar))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Search

    /// Searches the sources with official, keyless search APIs at once.
    static func search(_ query: String) async -> Result<String, Failure> {
        // Short enough to read in full before saying yes to it, and what's asked about is exactly what's sent.
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQueryCharacters))
        guard !query.isEmpty else { return .failure(Failure(message: "the search was empty.")) }
        guard await WebConsent.shared.mayUseWeb(detail: query, isSearch: true) else { return .failure(Failure(message: declined)) }
        async let wikipedia = wikipediaResults(query)
        async let stackOverflow = stackOverflowResults(query)
        async let arxiv = arxivResults(query)
        async let mdn = mdnResults(query)
        let groups = await [wikipedia, stackOverflow, arxiv, mdn]
        if groups.allSatisfy({ $0 == nil }) { return .failure(Failure(message: "no search service could be reached.")) }
        let results = groups.compactMap { $0 }.flatMap { $0 }
        guard !results.isEmpty else { return .success("No results for \"\(query)\".") }
        let text = results.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        // A yes to this search covers reading what it found.
        await WebConsent.shared.noteResults(HarnessText.hits(in: text).map(\.url), of: query)
        return .success(text)
    }

    /// Looks a name up among Wikipedia's page titles, following redirects, so "Mordell conjecture" finds the
    /// page that covers it. Results come back in the same form as `search`.
    static func titleSearch(_ title: String) async -> Result<String, Failure> {
        let query = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQueryCharacters))
        guard !query.isEmpty else { return .failure(Failure(message: "the search was empty.")) }
        guard await WebConsent.shared.mayUseWeb(detail: query, isSearch: true) else { return .failure(Failure(message: declined)) }
        guard let object = await json("https://en.wikipedia.org/w/rest.php/v1/search/title?limit=3&q=\(encoded(query))") else {
            return .failure(Failure(message: "no search service could be reached."))
        }
        let results = (object["pages"] as? [[String: Any]] ?? []).compactMap { page -> String? in
            guard let title = page["title"] as? String, let key = page["key"] as? String else { return nil }
            let path = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            return "\(title) — https://en.wikipedia.org/wiki/\(path)\n   \(snippet(page["description"] as? String))"
        }
        guard !results.isEmpty else { return .success("No results for \"\(query)\".") }
        let text = results.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        await WebConsent.shared.noteResults(HarnessText.hits(in: text).map(\.url), of: query)
        return .success(text)
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))) ?? ""
    }

    private static func json(_ address: String) async -> [String: Any]? {
        guard let url = URL(string: address), let (data, _) = try? await fetch(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func snippet(_ html: String?) -> String { String(plainText(html ?? "").prefix(220)) }

    // Each source returns nil if it couldn't be reached, as opposed to finding nothing.

    private static func wikipediaResults(_ query: String) async -> [String]? {
        guard let object = await json("https://en.wikipedia.org/w/rest.php/v1/search/page?limit=4&q=\(encoded(query))") else { return nil }
        return (object["pages"] as? [[String: Any]] ?? []).compactMap { page in
            guard let title = page["title"] as? String, let key = page["key"] as? String else { return nil }
            let path = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            return "\(title) — https://en.wikipedia.org/wiki/\(path)\n   \(snippet(page["excerpt"] as? String))"
        }
    }

    private static func stackOverflowResults(_ query: String) async -> [String]? {
        guard let object = await json("https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&site=stackoverflow&pagesize=2&q=\(encoded(query))") else { return nil }
        return (object["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String, let link = item["link"] as? String else { return nil }
            return "\(plainText(title)) — \(link)"
        }
    }

    private static func mdnResults(_ query: String) async -> [String]? {
        guard let object = await json("https://developer.mozilla.org/api/v1/search?size=2&locale=en-US&q=\(encoded(query))") else { return nil }
        return (object["documents"] as? [[String: Any]] ?? []).compactMap { document in
            guard let title = document["title"] as? String, let path = document["mdn_url"] as? String else { return nil }
            return "\(title) — https://developer.mozilla.org\(path)\n   \(snippet(document["summary"] as? String))"
        }
    }

    private static func arxivResults(_ query: String) async -> [String]? {
        guard let url = URL(string: "https://export.arxiv.org/api/query?max_results=2&search_query=all:\(encoded(query))"),
              let (data, _) = try? await fetch(url) else { return nil }
        let feed = String(decoding: data, as: UTF8.self)
        func first(_ tag: String, in text: String) -> String? {
            guard let open = text.range(of: "<\(tag)>"), let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
            return text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return feed.components(separatedBy: "<entry>").dropFirst().compactMap { entry in
            guard let title = first("title", in: entry), let id = first("id", in: entry) else { return nil }
            return "\(title.replacingOccurrences(of: "\n", with: " ")) — \(id.replacingOccurrences(of: "http://", with: "https://"))\n   \(String((first("summary", in: entry) ?? "").prefix(220)))"
        }
    }
}
