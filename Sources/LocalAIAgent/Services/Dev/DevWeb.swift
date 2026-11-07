import AppKit
import Network
import WebKit

/// Web pages in Dev mode. Python here has no display, but a browser engine is built into macOS, so a
/// page gets real graphics, keyboard and mouse with nothing to install. A model writes the page without
/// anyone reading it first, so it's held at least as tightly as a program: it sees the project's own
/// files, read-only, and nothing else, and no connection of any kind leaves the view.
enum DevWeb {
    static let scheme = "prometheus-preview"
    private static let host = "project"

    static func isPage(_ path: String) -> Bool { path.hasSuffix(".html") || path.hasSuffix(".htm") }
    static func isWebFile(_ path: String) -> Bool { isPage(path) || path.hasSuffix(".js") || path.hasSuffix(".css") }

    static func url(for path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.path = "/" + path
        return parts.url
    }

    /// The project path behind a page URL, as a page's own error reports give it.
    static func path(of address: String) -> String? {
        guard let url = URL(string: address), url.scheme == scheme, url.host == host else { return nil }
        let path = String(url.path.drop { $0 == "/" })
        return path.isEmpty ? nil : path
    }

    /// Everything a page may reach. The rule list below is what really holds the line, and this repeats
    /// it in the page's own policy, so one mistake in either still blocks a connection.
    static let policy = "default-src 'self' data: blob: 'unsafe-inline' 'unsafe-eval'; connect-src 'self' data: blob:; form-action 'none'; base-uri 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'"

    private static let blockRules = """
    [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
     {"trigger": {"url-filter": "^\(scheme)://"}, "action": {"type": "ignore-previous-rules"}},
     {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
     {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}}]
    """

    @MainActor private static var compiled: WKContentRuleList?

    /// WebRTC goes out over UDP, past every other limit here: no rule list, page policy or proxy sees it,
    /// and a page can put what it likes in the packets. It can only be switched off in the engine, through
    /// settings WebKit doesn't publish, so this says whether that's possible at all.
    @MainActor
    static func switchOffPeerConnections(_ preferences: WKPreferences) -> Bool {
        guard preferences.responds(to: NSSelectorFromString("_setPeerConnectionEnabled:")) else { return false }
        preferences.setValue(false, forKey: "peerConnectionEnabled")
        if preferences.responds(to: NSSelectorFromString("_setDNSPrefetchingEnabled:")) {
            preferences.setValue(false, forKey: "DNSPrefetchingEnabled")
        }
        return true
    }

    @MainActor private static var peerConnectionsAreOff: Bool?

    /// A page really can't reach for WebRTC here. Checked once on a live page, since this depends on a
    /// private setting that a macOS update could change.
    @MainActor
    private static func confirmPeerConnectionsOff(_ list: WKContentRuleList) async -> Bool {
        if let peerConnectionsAreOff { return peerConnectionsAreOff }
        var answer = false
        if let host = DevPageHost(project: DevProject(root: FileManager.default.temporaryDirectory), blockList: list, probing: false) {
            let names = (try? await host.webView.evaluateJavaScript("[typeof RTCPeerConnection, typeof webkitRTCPeerConnection].join()")) as? String
            answer = names == "undefined,undefined"
            host.close()
        }
        peerConnectionsAreOff = answer
        return answer
    }

    /// Nil means no page can be shown at all, rather than one shown without its limits.
    @MainActor
    static func blockList() async -> WKContentRuleList? {
        guard let list = await compiledList() else { return nil }
        return await confirmPeerConnectionsOff(list) ? list : nil
    }

    @MainActor
    private static func compiledList() async -> WKContentRuleList? {
        if let compiled { return compiled }
        let list: WKContentRuleList? = await withCheckedContinuation { continuation in
            guard let store = WKContentRuleListStore.default() else {
                continuation.resume(returning: nil)
                return
            }
            store.compileContentRuleList(forIdentifier: "PrometheusPagePolicy", encodedContentRuleList: blockRules) { list, _ in
                continuation.resume(returning: list)
            }
        }
        compiled = list
        return list
    }

    private struct Blocks {
        var page: String?
        var styles: [String] = []
        var scripts: [String] = []
    }

    private static func blocks(in reply: String) -> Blocks {
        var found = Blocks()
        var current: [String]?
        var tag = ""
        func close(_ lines: [String]) {
            let text = lines.joined(separator: "\n")
            if tag == "css" {
                found.styles.append(text)
            } else if ["js", "javascript"].contains(tag) {
                found.scripts.append(text)
            } else if text.lowercased().contains("<html") || text.lowercased().contains("<body") || text.lowercased().contains("<canvas") || text.lowercased().contains("<script") {
                if text.count > (found.page?.count ?? 0) { found.page = text }
            } else if tag.isEmpty, text.contains("function ") || text.contains("const ") || text.contains("let ") {
                found.scripts.append(text)
            }
        }
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = current {
                    close(open)
                    current = nil
                } else {
                    tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                    current = []
                }
            } else {
                current?.append(line)
            }
        }
        if let open = current { close(open) }
        if found.page == nil, found.scripts.isEmpty, !reply.contains("```"),
           let start = reply.range(of: "<!doctype", options: .caseInsensitive) ?? reply.range(of: "<html", options: .caseInsensitive) {
            found.page = String(reply[start.lowerBound...])
        }
        return found
    }

    /// One page out of a reply. Asked for one file, small models still often split it into HTML, CSS and
    /// JavaScript blocks and link them by name, so code puts them back together. A reply with only a
    /// script goes into the page it was meant for. Nil if that leaves no usable page.
    static func page(from reply: String, current: String?) -> String? {
        let parts = blocks(in: reply)
        var page: String
        if let found = parts.page {
            page = found
        } else if !parts.scripts.isEmpty, let current, let swapped = replacingLargestScript(in: current, with: parts.scripts.joined(separator: "\n")) {
            page = swapped
        } else {
            return nil
        }
        if !parts.styles.isEmpty {
            page = page.replacingOccurrences(of: #"<link[^>]*stylesheet[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            page = inserting("<style>\n\(parts.styles.joined(separator: "\n"))\n</style>\n", before: "</head>", in: page, fallback: "<body")
        }
        if parts.page != nil, !parts.scripts.isEmpty {
            page = page.replacingOccurrences(of: #"<script[^>]*\ssrc=["'](?!https?:)[^"']*["'][^>]*>\s*</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
            page = inserting("<script>\n\(parts.scripts.joined(separator: "\n"))\n</script>\n", before: "</body>", in: page, fallback: nil)
        }
        let lower = page.lowercased()
        // More scripts opened than closed means the reply was cut off in the middle of one.
        guard lower.components(separatedBy: "<script").count == lower.components(separatedBy: "</script>").count else { return nil }
        return page.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func inserting(_ text: String, before tag: String, in page: String, fallback: String?) -> String {
        if let range = page.range(of: tag, options: [.caseInsensitive, .backwards]) {
            return page.replacingCharacters(in: range.lowerBound..<range.lowerBound, with: text)
        }
        if let fallback, let range = page.range(of: fallback, options: .caseInsensitive) {
            return page.replacingCharacters(in: range.lowerBound..<range.lowerBound, with: text)
        }
        return page + text
    }

    private static func replacingLargestScript(in page: String, with script: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)</script>"#, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: page, range: NSRange(page.startIndex..., in: page))
        guard let largest = matches.max(by: { $0.range(at: 1).length < $1.range(at: 1).length }), let range = Range(largest.range(at: 1), in: page) else { return nil }
        return page.replacingCharacters(in: range, with: "\n\(script)\n")
    }

    static func hasPlaceholders(_ page: String) -> Bool {
        page.matches(#"(//|/\*|<!--)\s*(\.\.\.|…|(the )?rest of (the )?(code|file|game|page|script)|remaining (code|logic|functions)|existing (code|functions)|same as (before|above)|your code|add .{0,30} here|implement (this|the)|todo\b)"#, options: .caseInsensitive)
    }

    /// Puts the skeleton's canvas back when a reply garbled its size, which the browser then reads by its
    /// first digits: `width="80-than"` makes a game 80 pixels wide. A size the model chose on purpose stays.
    static func restoringCanvas(in page: String, from skeleton: String) -> String {
        let tag = #"<canvas\b[^>]*\bid\s*=\s*["']?game\b[^>]*>"#
        guard let original = skeleton.range(of: tag, options: [.regularExpression, .caseInsensitive]),
              let current = page.range(of: tag, options: [.regularExpression, .caseInsensitive]) else { return page }
        let found = String(page[current])
        let clean = { (name: String) in found.matches(#"\b\#(name)\s*=\s*["']?\d+["'\s>/]"#, options: .caseInsensitive) }
        let named = { (name: String) in found.matches(#"\b\#(name)\s*="#, options: .caseInsensitive) }
        let garbled = (named("width") && !clean("width")) || (named("height") && !clean("height"))
        return garbled ? page.replacingCharacters(in: current, with: skeleton[original]) : page
    }

    /// The same, for a first-person shooter. A small model asked for one tends to leave out the two things
    /// that make it a game, enemies arriving and a crosshair that follows the mouse, so those come ready.
    /// It waits for a click to start and stops at no lives, so nothing is lost before you look at it.
    static let firstPersonSkeleton = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Game</title>
    <style>html,body{margin:0;height:100%;background:#111}canvas{display:block;margin:0 auto;cursor:none}</style>
    </head><body><canvas id="game" width="800" height="500"></canvas>
    <script>
    const canvas = document.getElementById("game");
    const ctx = canvas.getContext("2d");
    const mouse = { x: 400, y: 250 };
    canvas.addEventListener("mousemove", e => {
      const box = canvas.getBoundingClientRect();
      mouse.x = (e.clientX - box.left) * canvas.width / box.width;
      mouse.y = (e.clientY - box.top) * canvas.height / box.height;
    });
    canvas.addEventListener("click", shoot);
    let enemies = [], score = 0, lives = 3, playing = false;
    function spawn() {
      enemies.push({ x: 250 + Math.random() * 300, y: 180 + Math.random() * 120, size: 6, speed: 1 });
    }
    function shoot() {
      if (!playing) { enemies = []; score = 0; lives = 3; playing = true; return; }
      const hit = enemies.find(e => Math.hypot(e.x - mouse.x, e.y - mouse.y) < e.size);
      if (hit) { enemies = enemies.filter(e => e !== hit); score += 10; }
    }
    function update() {
      if (Math.random() < 0.02) spawn();
      for (const e of enemies) {
        // grow e a little, and move it out from the middle of the screen
      }
      // One whose numbers broke can't be seen or hit, so it goes.
      enemies = enemies.filter(e => Number.isFinite(e.x + e.y + e.size));
      // An enemy this big has reached you, and costs a life.
      lives -= enemies.filter(e => e.size >= 60).length;
      enemies = enemies.filter(e => e.size < 60);
    }
    function draw() {
      ctx.fillStyle = "#223";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = "#2d2d3d";
      ctx.fillRect(0, canvas.height * 0.62, canvas.width, canvas.height * 0.38);
      // change how the enemies look, if you like
      for (const e of enemies) {
        ctx.fillStyle = "#e5484d";
        ctx.beginPath(); ctx.arc(e.x, e.y, e.size, 0, Math.PI * 2); ctx.fill();
      }
      ctx.strokeStyle = "#fff"; ctx.lineWidth = 2; ctx.beginPath();
      ctx.moveTo(mouse.x - 12, mouse.y); ctx.lineTo(mouse.x + 12, mouse.y);
      ctx.moveTo(mouse.x, mouse.y - 12); ctx.lineTo(mouse.x, mouse.y + 12); ctx.stroke();
      ctx.fillStyle = "#fff"; ctx.font = "20px sans-serif";
      ctx.fillText("Score " + score + "    Lives " + lives, 16, 30);
      if (!playing) {
        ctx.fillStyle = "#fff"; ctx.font = "28px sans-serif"; ctx.textAlign = "center";
        ctx.fillText(lives > 0 ? "Click to start" : "Game over. Click to play again", canvas.width / 2, canvas.height / 2);
        ctx.textAlign = "left";
      }
    }
    function loop() { if (playing) update(); if (lives <= 0) playing = false; draw(); requestAnimationFrame(loop); }
    loop();
    </script></body></html>
    """

    /// Shaped to fill in, since a small model that starts from a working loop rarely gets the loop wrong.
    static let gameSkeleton = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Game</title>
    <style>html,body{margin:0;height:100%;background:#111}canvas{display:block;margin:0 auto}</style>
    </head><body><canvas id="game" width="800" height="500"></canvas>
    <script>
    const canvas = document.getElementById("game");
    const ctx = canvas.getContext("2d");
    const keys = {};
    addEventListener("keydown", e => { keys[e.code] = true; e.preventDefault(); });
    addEventListener("keyup", e => { keys[e.code] = false; });
    let score = 0;
    function update() {
      // move things, spawn things, check hits
    }
    function draw() {
      ctx.fillStyle = "#111";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      // draw things, and the score
    }
    function loop() { update(); draw(); requestAnimationFrame(loop); }
    loop();
    </script></body></html>
    """
}

/// Serves a page and its files from the project, read-only, through the same path guard as everything
/// else. So `../` and `.env` get a 404 here, just as they would get refused anywhere else.
final class DevPageFiles: NSObject, WKURLSchemeHandler {
    private let project: DevProject
    private static let maxBytes = 50 << 20

    init(project: DevProject) {
        self.project = project
    }

    private static func type(of path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "woff2": return "font/woff2"
        default: return "text/plain; charset=utf-8"
        }
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let headers = ["Content-Security-Policy": DevWeb.policy, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"]
        guard let address = task.request.url, let path = DevWeb.path(of: address.absoluteString), task.request.httpMethod == nil || task.request.httpMethod == "GET",
              let data = project.contents(of: path, limit: Self.maxBytes) else {
            let missing = HTTPURLResponse(url: task.request.url ?? URL(fileURLWithPath: "/"), statusCode: 404, httpVersion: "HTTP/1.1", headerFields: headers)
            if let missing { task.didReceive(missing) }
            task.didReceive(Data())
            task.didFinish()
            return
        }
        var fields = headers
        fields["Content-Type"] = Self.type(of: path)
        if let response = HTTPURLResponse(url: address, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields) { task.didReceive(response) }
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// One page in a locked-down view, used by both the Preview pane and the agent's checks.
@MainActor
final class DevPageHost: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    struct Message: Sendable {
        enum Kind: Sendable { case error, console, resource }
        var kind: Kind
        var text: String
        var file: String?
        var line: Int?
    }

    /// A page can flood this as fast as it likes, and everything in it is the page's own word.
    private static let maxMessages = 400
    private static let channel = "prometheus"

    let webView: WKWebView
    var onMessage: ((Message) -> Void)?
    var onLoaded: (() -> Void)?
    var onCrashed: (() -> Void)?
    private var messages = 0

    private static let watcher = """
    (() => {
      const post = (kind, data) => { try { webkit.messageHandlers.\(channel).postMessage(Object.assign({ kind }, data)); } catch (e) {} };
      addEventListener("error", e => {
        const target = e.target;
        if (target && target !== window && (target.src || target.href)) {
          post("resource", { message: target.src || target.href });
        } else {
          post("error", { message: String(e.message), line: e.lineno || 0, file: e.filename || "" });
        }
      }, true);
      addEventListener("unhandledrejection", e => post("error", { message: "Unhandled rejection: " + e.reason, line: 0, file: "" }));
      // A closed shadow root would hide a link from the path below.
      const attach = Element.prototype.attachShadow;
      const assign = Object.assign;
      Element.prototype.attachShadow = function (options) { return attach.call(this, assign({}, options, { mode: "open" })); };
      // Everything here is taken now, before the page's code can swap any of it for its own, and this
      // listener goes first for the same reason. It stops a clicked link, which WebKit starts to connect to
      // before anything else gets a say.
      const apply = Reflect.apply, Link = URL, read = Element.prototype.getAttribute, isElement = Element, here = location.protocol;
      const stop = Event.prototype.preventDefault, path = Event.prototype.composedPath, base = Object.getOwnPropertyDescriptor(Document.prototype, "URL").get;
      addEventListener("click", e => {
        for (const item of apply(path, e, [])) {
          if (!(item instanceof isElement)) continue;
          const href = apply(read, item, ["href"]) || apply(read, item, ["xlink:href"]);
          if (!href) continue;
          let same = false;
          try { same = new Link(href, apply(base, document, [])).protocol === here; } catch (error) {}
          if (!same) {
            apply(stop, e, []);
            return;
          }
        }
      }, true);
      for (const level of ["log", "info", "warn", "error"]) {
        const original = console[level];
        console[level] = function (...args) {
          post("console", { message: args.map(String).join(" ") });
          original.apply(console, args);
        };
      }
    })();
    """

    /// For the agent's checks: notes which input a page listens for, and puts time in the check's hands.
    /// A view nobody can see has its timers slowed to a crawl, so frames and timers run when it says so,
    /// which also makes a run quick, and the same every time.
    private static let probe = """
    (() => {
      const inputs = new Set(["keydown", "keyup", "keypress", "click", "mousedown", "mouseup", "mousemove", "pointerdown", "pointerup", "pointermove", "touchstart"]);
      window.__heard = new Set();
      const add = EventTarget.prototype.addEventListener;
      EventTarget.prototype.addEventListener = function (type, ...rest) {
        if (inputs.has(type)) window.__heard.add(type);
        return add.call(this, type, ...rest);
      };
      const started = Date.now();
      let now = 0, id = 0;
      const frames = new Map(), timers = new Map();
      const call = (callback, args) => { try { callback(...args); } catch (error) { reportError(error); } };
      window.requestAnimationFrame = callback => { frames.set(++id, callback); return id; };
      window.cancelAnimationFrame = key => { frames.delete(key); };
      const timer = repeats => (callback, delay = 0, ...args) => {
        if (typeof callback !== "function") return 0;
        timers.set(++id, { callback, args, every: repeats ? Math.max(delay, 1) : 0, due: now + delay });
        return id;
      };
      window.setTimeout = timer(false);
      window.setInterval = timer(true);
      window.clearTimeout = window.clearInterval = key => { timers.delete(key); };
      performance.now = () => now;
      Date.now = () => started + now;
      window.__frames = count => {
        for (let i = 0; i < count; i++) {
          now += 16;
          for (const [key, item] of [...timers]) {
            while (timers.has(key) && item.due <= now) {
              if (item.every) item.due += item.every; else timers.delete(key);
              call(item.callback, item.args);
            }
          }
          const batch = [...frames.values()];
          frames.clear();
          for (const callback of batch) call(callback, [now]);
        }
        return "ok";
      };
    })();
    """

    /// Port 9 is the discard port, which nothing listens on here. Only the checks pick another.
    init?(project: DevProject, blockList: WKContentRuleList?, probing: Bool, proxyPort: UInt16 = 9) {
        let configuration = WKWebViewConfiguration()
        let store = WKWebsiteDataStore.nonPersistent()
        // WebKit opens a connection for a clicked link before anyone decides whether to follow it, which
        // no rule list or navigation policy gets a say in. So everything is sent to a proxy that isn't
        // there, which also keeps a host name from reaching DNS.
        store.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: proxyPort) ?? 9))]
        configuration.websiteDataStore = store
        configuration.setURLSchemeHandler(DevPageFiles(project: project), forURLScheme: DevWeb.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.preferences.inactiveSchedulingPolicy = .none
        guard DevWeb.switchOffPeerConnections(configuration.preferences) else { return nil }
        let content = configuration.userContentController
        if let blockList { content.add(blockList) }
        content.addUserScript(WKUserScript(source: Self.watcher, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if probing { content.addUserScript(WKUserScript(source: Self.probe, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), configuration: configuration)
        super.init()
        content.add(self, name: Self.channel)
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func load(_ path: String) {
        guard let url = DevWeb.url(for: path) else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// Ends the page. Without this the channel above would keep the view alive.
    func close() {
        // A page stuck in a loop of its own ignores everything else and keeps a core busy after the view
        // has gone, so its process gets ended. Never with 0, which would mean this whole app's group.
        let selector = NSSelectorFromString("_webProcessIdentifier")
        if webView.responds(to: selector), let process = webView.value(forKey: "_webProcessIdentifier") as? Int32, process > 1 {
            kill(process, SIGKILL)
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.channel)
        webView.removeFromSuperview()
        onMessage = nil
        onLoaded = nil
        onCrashed = nil
    }

    /// Cut by length rather than by character: one "character" can carry megabytes of combining marks.
    private static func shortened(_ text: Any?) -> String {
        guard let text = text as? NSString else { return "" }
        return text.length <= 500 ? text as String : text.substring(to: 500)
    }

    private func deliver(_ message: Message) {
        guard messages < Self.maxMessages else { return }
        messages += 1
        onMessage?(message)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        let text = Self.shortened(body["message"])
        switch kind {
        case "error":
            // The page's own word, so it can only ever point at another web file.
            let file = (body["file"] as? String).flatMap(DevWeb.path(of:)).flatMap { DevWeb.isWebFile($0) ? $0 : nil }
            deliver(Message(kind: .error, text: text, file: file, line: body["line"] as? Int))
        case "resource":
            deliver(Message(kind: .resource, text: text))
        default:
            deliver(Message(kind: .console, text: text))
        }
    }

    /// Only the page itself and its own files. Any other destination goes nowhere.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        return url.scheme == DevWeb.scheme || url.absoluteString == "about:blank" ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoaded?() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onLoaded?() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onLoaded?() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onCrashed?() }

    /// No pop-up windows, and alert() goes to the Terminal rather than stopping the app with a dialog.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        deliver(Message(kind: .console, text: Self.shortened(message)))
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool { true }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? { defaultText }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision { .deny }
}

/// What a page is for, which decides what trying it means.
enum DevPageKind: String, Codable, Sendable {
    /// Something to look at.
    case page
    /// Something to use: fields to fill in and buttons to press.
    case app
    /// Something that moves and is played.
    case game
}

/// What trying a page showed.
struct DevPageReport: Sendable {
    var failure: DevFailure?
    var console: [String] = []
    /// What a person would make of it, for the agent's step list.
    var summary = ""
    var hasContent = false
    var listens = false
    var moved = false
    var responded = false
    /// It opened without an error, a crash or a freeze.
    var loaded = false
    /// Some style sheet applies, so it isn't the browser's plain black on white.
    var styled = false
    /// Nothing on it is wider than the window.
    var fits = true
    /// It asked for nothing from the internet.
    var offline = true
    /// Filling in its fields and pressing its buttons changed something. Nil if it wasn't tried.
    var used: Bool?
    /// How many fields and buttons it has.
    var controls = 0
    /// Whether what was typed into it shows up on the page afterwards. Nil if it wasn't used.
    var showsTyped: Bool?
    /// It shows template tags, such as {{ name }} or {% for %}, that only a server would fill in.
    var rawTemplate = false
}

/// Opens a page out of sight and plays with it: it loads, watches for errors, then sends keys and clicks
/// and sees whether anything changes. That's the page's traceback, and the only check a model can't talk
/// its way through.
@MainActor
enum DevPageCheck {
    private struct Mark: Decodable, Equatable {
        struct Canvas: Decodable, Equatable {
            var hash: Int
            var colors: Int
            var width = 0
            var height = 0
        }
        var canvases: [Canvas]
        var text: Int
        var body: String
        var elements: Int
        var listens: Bool
        var rules = 0
        var wide = false
        var controls = 0
        var template = false
    }

    private static let measure = #"""
    (() => {
      const read = c => {
        try {
          if (!c.width || !c.height) return { hash: 0, colors: 0, width: c.width || 0, height: c.height || 0 };
          // Close to full size: shrunk much further, a small crosshair or sprite falls between the pixels read,
          // and a working game looks blank.
          const s = Math.min(1, Math.sqrt(250000 / (c.width * c.height)));
          const w = Math.max(1, Math.round(c.width * s)), h = Math.max(1, Math.round(c.height * s));
          const t = document.createElement("canvas");
          t.width = w; t.height = h;
          const x = t.getContext("2d");
          x.drawImage(c, 0, 0, w, h);
          const d = x.getImageData(0, 0, w, h).data;
          let hash = -2128831035;
          const colors = new Set();
          for (let i = 0; i < d.length; i += 4) {
            // Alpha counts too: black ink on a clear canvas has the same colour as the canvas.
            colors.add((d[i] * 65536 + d[i + 1] * 256 + d[i + 2]) * 256 + d[i + 3]);
            // A byte at a time (FNV-1a). Adding whole pixels and keeping 32 bits drops most of the top byte,
            // which is red, so a red player could move and the picture still looked the same.
            hash = Math.imul(hash ^ d[i], 16777619);
            hash = Math.imul(hash ^ d[i + 1], 16777619);
            hash = Math.imul(hash ^ d[i + 2], 16777619);
            hash = Math.imul(hash ^ d[i + 3], 16777619);
          }
          return { hash, colors: colors.size, width: c.width, height: c.height };
        } catch (e) { return { hash: 0, colors: 0, width: c.width || 0, height: c.height || 0 }; }
      };
      const body = document.body;
      const html = body ? body.innerHTML : "";
      let mark = 0;
      for (let i = 0; i < html.length; i++) mark = (mark * 31 + html.charCodeAt(i)) | 0;
      const props = ["onkeydown", "onkeyup", "onkeypress", "onclick", "onmousedown", "onmouseup", "onmousemove", "onpointerdown", "onpointermove", "ontouchstart"];
      const targets = [window, document, body].concat([...document.querySelectorAll("canvas,button,input,select,textarea,a,[onclick],[onkeydown]")]);
      const listens = (window.__heard && window.__heard.size > 0) || targets.some(t => t && props.some(p => t[p])) || document.querySelectorAll("button,input,select,textarea").length > 0;
      let rules = 0;
      for (const sheet of document.styleSheets) { try { rules += sheet.cssRules.length; } catch (e) {} }
      return JSON.stringify({
        canvases: [...document.querySelectorAll("canvas")].map(read),
        text: body ? body.innerText.trim().length : 0,
        body: String(mark),
        elements: body ? body.querySelectorAll("svg *, img, table, ul, ol, button, input, select").length : 0,
        listens,
        rules,
        wide: document.documentElement.scrollWidth > innerWidth + 4,
        controls: document.querySelectorAll("input:not([type=hidden]), textarea, select, button, [role=button]").length,
        template: !!body && /\{\{[^{}]{1,80}\}\}|\{%[^%]{1,80}%\}|<\?php/.test(body.innerText)
      });
    })()
    """#

    /// Presses what games usually use, and clicks around the middle of the page.
    private static let play = #"""
    (() => {
      const codes = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Space", "KeyA", "KeyD", "KeyW", "KeyS", "Enter"];
      const keyOf = c => c === "Space" ? " " : c.startsWith("Key") ? c.slice(3).toLowerCase() : c;
      const send = (type, code) => {
        for (const target of [window, document, document.body]) {
          if (target) target.dispatchEvent(new KeyboardEvent(type, { key: keyOf(code), code, bubbles: target === document.body, cancelable: true }));
        }
      };
      for (const code of codes) {
        send("keydown", code);
        __frames(6);
        send("keyup", code);
        __frames(1);
      }
      const place = document.querySelector("canvas") || document.querySelector("button") || document.body;
      if (place) {
        const box = place.getBoundingClientRect();
        const at = (a, b) => ({ clientX: box.left + box.width * a, clientY: box.top + box.height * b, bubbles: true, cancelable: true, button: 0, buttons: 1 });
        const fire = (types, options) => {
          for (const type of types) place.dispatchEvent(new (type.startsWith("pointer") ? PointerEvent : MouseEvent)(type, options));
        };
        // Clicks, for games, and a drag, for anything you draw on.
        for (const [a, b] of [[0.5, 0.5], [0.3, 0.4], [0.7, 0.6]]) {
          fire(["pointermove", "mousemove", "pointerdown", "mousedown", "pointerup", "mouseup", "click"], at(a, b));
          __frames(4);
        }
        fire(["pointermove", "mousemove", "pointerdown", "mousedown"], at(0.2, 0.2));
        for (let step = 1; step <= 12; step++) {
          fire(["pointermove", "mousemove"], at(0.2 + step * 0.05, 0.2 + step * 0.04));
          __frames(1);
        }
        fire(["pointerup", "mouseup"], at(0.8, 0.68));
      }
      for (const button of [...document.querySelectorAll("button")].slice(0, 3)) button.click();
      __frames(20);
      return "sent";
    })()
    """#

    /// Uses the page the way someone trying an app would: fills in every field, submits each form,
    /// presses the buttons, then does it again for anything that appeared in answer, such as a delete
    /// button on a new item. It notes whether anything changed after each step, since adding an item and
    /// then clearing the list would leave the page as it started.
    private static let use = #"""
    (() => {
      const visible = el => { const box = el.getBoundingClientRect(), style = getComputedStyle(el); return box.width > 0 && box.height > 0 && style.visibility !== "hidden" && style.display !== "none"; };
      const sign = () => {
        const html = document.documentElement.outerHTML;
        let mark = 0;
        for (let i = 0; i < html.length; i++) mark = (mark * 31 + html.charCodeAt(i)) | 0;
        const shown = [...document.querySelectorAll("input[readonly], input[disabled], output, textarea[readonly]")].map(f => f.value).join("|");
        return mark + "|" + shown;
      };
      const samples = { email: "sam@example.com", number: "3", tel: "5551234", url: "https://example.com", date: "2026-11-07", time: "09:30",
                        "datetime-local": "2026-11-07T09:30", month: "2026-11", week: "2026-W45", color: "#3366ff", password: "secret123" };
      let filled = 0, actions = 0, changed = false, last = sign();
      const settle = count => { __frames(count); const now = sign(); if (now !== last) { changed = true; last = now; } };
      const fill = () => {
        for (const field of document.querySelectorAll("input, textarea, select")) {
          if (field.disabled || field.readOnly || !visible(field)) continue;
          const type = (field.getAttribute("type") || "text").toLowerCase();
          if (field.tagName === "SELECT") {
            if (field.options.length > 1 && field.selectedIndex <= 0) field.selectedIndex = 1;
          } else if (["checkbox", "radio", "button", "submit", "reset", "file", "hidden", "image"].includes(type)) {
            continue;
          } else if (type === "range") {
            field.value = String((Number(field.min || 0) + Number(field.max || 100)) / 2);
          } else if (field.value) {
            continue;
          } else {
            field.value = samples[type] || ("Sample item" + (filled ? " " + (filled + 1) : ""));
          }
          filled++;
          field.dispatchEvent(new Event("input", { bubbles: true }));
          field.dispatchEvent(new Event("change", { bubbles: true }));
        }
      };
      const forms = new Set(), buttons = new Set();
      for (let round = 0; round < 2; round++) {
        fill();
        settle(2);
        for (const form of document.querySelectorAll("form")) {
          if (forms.has(form) || !visible(form)) continue;
          forms.add(form);
          const submit = form.querySelector("button:not([type=button]):not([type=reset]), input[type=submit]");
          if (submit && visible(submit) && !submit.disabled) submit.click();
          else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
          actions++;
          settle(3);
          fill();
        }
        for (const button of document.querySelectorAll("button, [role=button], input[type=button]")) {
          if (buttons.size >= 10) break;
          if (buttons.has(button) || button.closest("form") || button.disabled || !visible(button)) continue;
          buttons.add(button);
          button.click();
          actions++;
          settle(3);
        }
      }
      settle(10);
      return JSON.stringify({ changed, actions, filled, shown: !!document.body && document.body.innerText.includes("Sample item") });
    })()
    """#

    private struct Used: Decodable {
        var changed: Bool
        var actions: Int
        var filled: Int
        var shown = false
    }

    /// Runs a script, giving up on a page stuck in a loop of its own, which would never answer.
    private static func evaluate(_ script: String, in host: DevPageHost, timeout: Double = 3) async -> String? {
        await withCheckedContinuation { continuation in
            var finished = false
            let finish: (String?) -> Void = { value in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }
            host.webView.evaluateJavaScript(script) { value, _ in finish(value as? String) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    private static func mark(_ host: DevPageHost) async -> Mark? {
        guard let text = await evaluate(measure, in: host), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Mark.self, from: data)
    }

    /// A JavaScript error as a failure, the way a traceback is one.
    private static func failure(_ message: DevPageHost.Message, page: String, output: String) -> DevFailure {
        let parts = message.text.groups(of: #"^(?:Uncaught )?(\w*Error): (.*)$"#)
        return DevFailure(file: message.file ?? page, line: message.line.flatMap { $0 > 0 ? $0 : nil }, kind: parts?[1] ?? "PageError",
                          message: parts?[2] ?? message.text, output: output)
    }

    static func run(folder: URL, page: String, game: Bool, picture: URL? = nil) async -> DevPageReport {
        await run(folder: folder, page: page, kind: game ? .game : .page, picture: picture)
    }

    static func run(folder: URL, page: String, kind: DevPageKind, picture: URL? = nil) async -> DevPageReport {
        let game = kind == .game
        var report = DevPageReport()
        func fail(_ kind: String, _ message: String) -> DevPageReport {
            report.failure = DevFailure(file: page, kind: kind, message: message, output: report.console.suffix(6).joined(separator: "\n"))
            report.summary = message
            return report
        }
        guard let list = await DevWeb.blockList(), let host = DevPageHost(project: DevProject(root: folder), blockList: list, probing: true) else {
            return fail("Exit", "The page view couldn't start safely, so nothing was tried.")
        }
        defer { host.close() }

        final class Log {
            var errors: [DevPageHost.Message] = []
            var blocked: [String] = []
            var crashed = false
            var console: [String] = []
        }
        let log = Log()
        host.onMessage = { message in
            switch message.kind {
            case .error: log.errors.append(message)
            case .resource: log.blocked.append(message.text)
            case .console: log.console.append(message.text)
            }
        }
        host.onCrashed = { log.crashed = true }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var waiting = true
            let done = {
                guard waiting else { return }
                waiting = false
                continuation.resume()
            }
            host.onLoaded = done
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: done)
            host.load(page)
        }
        host.onLoaded = nil

        /// Anything that went wrong so far, worst first.
        func problem() -> DevFailure? {
            report.console = Array(log.console.suffix(20))
            if log.crashed { return DevFailure(file: page, kind: "Limit", message: "The page crashed. It may have used too much memory.", output: "") }
            if let error = log.errors.first {
                return failure(error, page: page, output: (log.errors.prefix(3).map(\.text) + log.console.suffix(4)).joined(separator: "\n"))
            }
            if let missing = log.blocked.first {
                let isLocal = missing.hasPrefix(DevWeb.scheme)
                let name = DevWeb.path(of: missing) ?? missing
                return DevFailure(file: page, kind: "Resource", message: isLocal ? "The page asks for \(name), which isn't in the project." : "The page asks for \(name) from the internet, which is blocked here.", output: "")
            }
            return nil
        }

        // Long enough for anything it fetched to arrive.
        try? await Task.sleep(for: .seconds(0.3))
        report.offline = !log.blocked.contains { !$0.hasPrefix(DevWeb.scheme) }
        guard let first = await mark(host) else {
            if let failure = problem() { report.failure = failure; return report }
            return fail("Limit", "The page froze, so there's probably a loop that never ends.")
        }
        report.styled = first.rules >= 5
        report.fits = !first.wide
        report.hasContent = first.text > 0 || first.elements > 0 || first.canvases.contains { $0.colors > 1 }
        report.rawTemplate = first.template
        report.controls = first.controls
        let ran = await evaluate("__frames(45)", in: host)
        let second = ran == nil ? nil : await mark(host)
        let played = second == nil ? nil : await evaluate(play, in: host)
        let third = played == nil ? nil : await mark(host)
        // An app gets used as well as poked, once it has something to use.
        var usedReport: Used?
        if kind == .app, let third, third.controls > 0 {
            let said = log.console.count
            if let text = await evaluate(use, in: host, timeout: 5), let data = text.data(using: .utf8) {
                usedReport = try? JSONDecoder().decode(Used.self, from: data)
                report.used = (usedReport?.changed ?? false) || log.console.count > said
                report.showsTyped = usedReport?.shown
            }
        }
        let after = kind == .app && third != nil ? await mark(host) : third
        report.offline = !log.blocked.contains { !$0.hasPrefix(DevWeb.scheme) }
        // Whether it ran cleanly, apart from asking the internet for things, which counts on its own.
        report.loaded = !log.crashed && log.errors.isEmpty && after != nil
        if let failure = problem() {
            report.failure = failure
            report.summary = failure.title
            if let picture { await save(host, to: picture) }
            return report
        }
        guard let second, let third, let after else {
            if let picture { await save(host, to: picture) }
            return fail("Limit", "The page froze while it was being played, so there's probably a loop that never ends.")
        }

        report.hasContent = after.text > 0 || after.elements > 0 || after.canvases.contains { $0.colors > 1 }
        report.listens = third.listens
        report.moved = first != second
        report.responded = second != third
        report.fits = !first.wide && !after.wide
        if let picture { await save(host, to: picture) }
        guard report.hasContent else { return fail("Output", "The page is blank.") }
        // A model asked for a web app often writes a server's template, which shows here as raw tags.
        if report.rawTemplate || after.template {
            report.rawTemplate = true
            return fail("Output", "The page shows template tags, such as {{ name }} or {% for %}, that only a server fills in.")
        }
        if game {
            // A garbled size, like width="80-than", which the browser reads as 80.
            if let main = third.canvases.max(by: { $0.width * $0.height < $1.width * $1.height }), main.width > 0, min(main.width, main.height) < 100 {
                return fail("Output", "The game's canvas is only \(main.width) by \(main.height) pixels, so it shows as a thin strip. Check the width and height on the <canvas> tag.")
            }
            guard report.listens else { return fail("Output", "It's a game, but it doesn't listen to the keyboard or the mouse.") }
            guard report.moved || report.responded else { return fail("Output", "Nothing moves on the page, and pressing keys and clicking changes nothing.") }
        }
        if kind == .app, third.controls > 0, report.used == false, !report.responded {
            let tried = usedReport.map { "I filled in \($0.filled) \($0.filled == 1 ? "field" : "fields") and pressed \($0.actions) \($0.actions == 1 ? "button" : "buttons")" } ?? "I filled in the fields and pressed the buttons"
            return fail("Output", "\(tried), and nothing on the page changed.")
        }
        report.summary = [report.moved ? "It moves by itself." : nil,
                          report.used == true ? "It answers when it's used." : report.responded ? "It reacts to keys and clicks." : nil,
                          report.moved || report.responded || report.used == true ? nil : "It shows a still page.",
                          report.fits ? nil : "Something on it is wider than the window."]
            .compactMap { $0 }.joined(separator: " ")
        return report
    }

    /// For the measuring runs, so a person can see what came out. It goes through a window off the screen,
    /// since a view in no window draws nothing.
    private static func save(_ host: DevPageHost, to file: URL) async {
        let window = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 800, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host.webView
        window.orderBack(nil)
        defer { window.close() }
        _ = await evaluate("__frames(5)", in: host)
        try? await Task.sleep(for: .seconds(0.3))
        let image: NSImage? = await withCheckedContinuation { continuation in
            host.webView.takeSnapshot(with: nil) { image, _ in continuation.resume(returning: image) }
        }
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: file)
    }
}
