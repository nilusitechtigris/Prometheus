#if DEBUG
import Foundation

/// The first-run logic that needs no window: which step a new user is on, which model they're offered, what a
/// failed download says, and the prompt the harness gets.
enum FirstRunCheck {
    @MainActor
    static func run() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        // Where a new user is.
        func state(online: Bool = false, checking: Bool = false, isOllama: Bool = true, installed: Bool = true, model: Bool = false) -> SetupState {
            SetupState.state(online: online, checking: checking, isOllama: isOllama, ollamaInstalled: installed, hasModel: model)
        }
        expect("nothing installed: get Ollama", state(installed: false) == .needsOllama)
        expect("installed, not running: start it", state() == .notRunning)
        expect("another framework that's off is never 'get Ollama'", state(isOllama: false, installed: false) == .notRunning)
        expect("running with no model: get a model", state(online: true) == .noModel)
        expect("running with a model: ready", state(online: true, model: true) == .ready)
        expect("still looking: neither ready nor broken", state(checking: true) == .checking && state(checking: true, installed: false) == .checking)
        expect("only ready is green", SetupState.ready.level == .good && [SetupState.checking, .needsOllama, .notRunning, .noModel].allSatisfy { $0.level != .good })
        expect("every unfinished step says what to do", [SetupState.needsOllama, .notRunning, .noModel].allSatisfy { !$0.nextStep.isEmpty })
        expect("the titles name the framework", SetupState.notRunning.title(.lmStudio).contains("LM Studio") && SetupState.needsOllama.title(.ollama) == "Ollama isn't installed")

        // Which models are offered first.
        let featured = ModelCatalog.all.filter(\.featured)
        let all = StarterModels.pick(from: featured) { _ in .great }
        expect("with room for everything: the first three featured models, in order", all.models.map(\.id) == Array(featured.prefix(3)).map(\.id) && !all.tight)
        let first = featured.first?.id
        let small = StarterModels.pick(from: featured) { $0.id == first ? .tight : .tooLarge }
        expect("when nothing fits well: what just fits, marked as tight", small.models.map(\.id) == [first].compactMap { $0 } && small.tight)
        let none = StarterModels.pick(from: featured) { _ in .tooLarge }
        expect("when nothing fits at all: still two to choose from, marked as tight", none.models.count == 2 && none.tight)
        expect("every featured model can be downloaded with Ollama", featured.allSatisfy { !$0.variants(for: .ollama).isEmpty })

        // What a failed download says.
        func problem(_ text: String, _ code: URLError.Code? = nil) -> String { BackendController.pullProblem(text, urlError: code, size: "2.5 GB") }
        expect("a full disk says so, with the size", problem("write /models/blobs: no space left on device").contains("disk is full") && problem("no space left on device").contains("2.5 GB"))
        expect("the app's own request refused: the framework is gone", problem("Could not connect to the server.", .cannotConnectToHost).hasPrefix("The framework stopped answering"))
        expect("the framework's way out refused: a connection problem", problem("pull model manifest: proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused").hasPrefix("The connection dropped"))
        expect("offline says to check the internet", problem("The Internet connection appears to be offline.", .notConnectedToInternet).contains("Check the internet")
               && problem("dial tcp: lookup registry.ollama.ai: no such host").contains("Check the internet"))
        expect("a model gone from the library says so", problem("pull model manifest: file does not exist").contains("doesn't have this model"))
        expect("anything else keeps the framework's words", problem("something odd happened").contains("something odd happened"))
        expect("every message says to press Retry or what else to do", ["no space left", "no such host", "something odd"].allSatisfy { problem($0).contains("Retry") })

        // The prompt.
        let saved = AppSettings.defaultSystemPrompt
        let plain = AppSettings.systemPrompt(saved, harnessOn: false), withHarness = AppSettings.systemPrompt(saved, harnessOn: true)
        expect("the default prompt holds the line about having no tools", saved.contains(AppSettings.offlineClaim))
        expect("with the harness off the prompt is the one in Settings", plain == saved.trimmingCharacters(in: .whitespacesAndNewlines))
        expect("with the harness on that line is left out, and nothing else", !withHarness.contains("no tools") && !withHarness.contains("no internet access")
               && withHarness.count == plain.count - AppSettings.offlineClaim.count && withHarness.hasPrefix("You are a knowledgeable"))
        expect("a prompt the user wrote is never changed", AppSettings.systemPrompt("Answer like a pirate.", harnessOn: true) == "Answer like a pirate.")
        return lines
    }
}
#endif
