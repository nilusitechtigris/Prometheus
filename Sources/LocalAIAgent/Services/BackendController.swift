import AppKit
import Foundation
import Observation

/// Owns the active framework connection: status, installed models, loaded models and downloads.
@MainActor
@Observable
final class BackendController {
    enum Status: Equatable {
        case checking
        case online(String)
        case offline(String)

        var isOnline: Bool { if case .online = self { return true } else { return false } }
    }

    struct PullState {
        var fraction: Double = 0
        var status = "Starting…"
        var completed: Int64 = 0
        var total: Int64 = 0
        var error: String?
        var task: Task<Void, Never>?
    }

    let settings: AppSettings
    private(set) var status: Status = .checking
    private(set) var models: [LocalModel] = []
    private(set) var details: ModelDetails?
    private(set) var loaded: [LoadedModel] = []
    /// Which frameworks are currently reachable on this Mac.
    private(set) var availability: [BackendKind: Bool] = [:]
    var pulls: [String: PullState] = [:]
    var lastError: String?
    var isStartingFramework = false
    /// Name of the test that's using the model or the hardware right now; chat waits until it ends.
    var activeTest: String?

    private var pollTask: Task<Void, Never>?
    private var detailsFor: String?
    /// The MLX LM server, when the app started it.
    private var mlxServer: Process?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var kind: BackendKind { settings.backendKind }

    var backend: LLMBackend { makeBackend(kind) }

    private func makeBackend(_ kind: BackendKind) -> LLMBackend {
        let url = URL(string: settings.baseURL(for: kind)) ?? URL(string: kind.defaultBaseURL)!
        switch kind {
        case .ollama: return OllamaBackend(baseURL: url)
        default: return OpenAICompatibleBackend(kind: kind, baseURL: url)
        }
    }

    var ollama: OllamaBackend? { backend as? OllamaBackend }

    // MARK: Models

    var verifiedModels: [LocalModel] { models.filter(\.isVerified) }
    var unverifiedModels: [LocalModel] { models.filter { !$0.isVerified } }

    func isSelectable(_ model: LocalModel) -> Bool { model.isVerified || settings.allowUnverifiedModels }

    var selectedModel: LocalModel? {
        guard let id = settings.selectedModel else { return nil }
        return models.first { $0.id == id && isSelectable($0) }
    }

    func select(_ model: LocalModel) {
        guard isSelectable(model) else { return }
        let previous = settings.selectedModel
        settings.selectedModel = model.id
        details = nil
        Task { await refreshDetails() }
        if settings.unloadOnSwitch, let previous, previous != model.id, loaded.contains(where: { $0.name == previous }) {
            Task { await unload(previous) }
        }
    }

    func switchBackend(to kind: BackendKind) {
        guard kind != settings.backendKind else { return }
        settings.backendKind = kind
        status = .checking
        models = []
        loaded = []
        details = nil
        detailsFor = nil
        if kind == .mlx { startMLXIfNeeded() } else { stopMLX() }
        Task { await refresh() }
    }

    /// Largest context the selected model supports (from the framework, or our catalog).
    var maxContext: Int? { details?.maxContext ?? selectedModel?.catalog?.maxContext }

    var contextOptions: [Int] {
        guard let max = maxContext else { return AppSettings.contextOptions }
        let options = AppSettings.contextOptions.filter { $0 <= max }
        return options.isEmpty ? [max] : options
    }

    /// The context window actually requested, clamped to what the model supports.
    var effectiveContext: Int { context(details: details, catalog: selectedModel?.catalog) }

    private func context(details: ModelDetails?, catalog: CatalogModel?) -> Int {
        if !kind.supportsPerRequestContext, let loadedCtx = details?.maxContext { return loadedCtx }
        guard let max = details?.maxContext ?? catalog?.maxContext else { return settings.contextLength }
        return min(settings.contextLength, max)
    }

    /// Context window for any installed model, using what's known without asking the framework.
    func estimatedContext(for model: LocalModel) -> Int {
        context(details: model.id == settings.selectedModel ? details : nil, catalog: model.catalog)
    }

    /// Asks the framework for the context window and thinking support of any installed model,
    /// which may not be the chat's selected one.
    func capabilities(of model: LocalModel) async -> (context: Int, supportsThinking: Bool, supportsTools: Bool) {
        let info = try? await backend.details(for: model.id)
        return (context(details: info, catalog: model.catalog), info?.supportsThinking ?? model.catalog?.thinking ?? false,
                info?.capabilities.contains("tools") ?? false)
    }

    var supportsThinking: Bool { details?.supportsThinking ?? selectedModel?.catalog?.thinking ?? false }

    func memoryEstimate(for catalog: CatalogModel, variant: QuantVariant? = nil, context: Int? = nil) -> Int64 {
        MemoryFit.estimateBytes(weights: (variant ?? catalog.defaultVariant).bytes, kvKBPerToken: catalog.kvKBPerToken,
                                context: min(context ?? settings.contextLength, catalog.maxContext))
    }

    /// The installed model (if any) that holds this exact quantization.
    func installed(_ variant: QuantVariant) -> LocalModel? {
        models.first { variant.matches($0.id) }
    }

    /// Installed, verified models grouped by catalog entry (one group per base model, several quants each).
    var installedGroups: [(catalog: CatalogModel, models: [LocalModel])] {
        var order: [String] = []
        var groups: [String: (CatalogModel, [LocalModel])] = [:]
        for model in verifiedModels {
            guard let c = model.catalog else { continue }
            if groups[c.id] == nil { order.append(c.id); groups[c.id] = (c, []) }
            groups[c.id]!.1.append(model)
        }
        return order.compactMap { groups[$0] }.map { (catalog: $0.0, models: $0.1) }
    }

    /// Selects an installed quantization, or downloads it first and then selects it.
    func choose(_ variant: QuantVariant) {
        if let model = installed(variant) {
            select(model)
        } else if kind.supportsModelDownloads {
            pull(variant.tag, selectWhenDone: true)
        }
    }

    func memoryEstimate(for model: LocalModel, context: Int) -> Int64? {
        if let c = model.catalog { return memoryEstimate(for: c, variant: model.variant, context: context) }
        guard let size = model.sizeBytes else { return nil }
        return MemoryFit.estimateBytes(weights: size, kvKBPerToken: 128, context: context)
    }

    // MARK: Polling

    func start() {
        guard pollTask == nil else { return }
        if kind == .mlx { startMLXIfNeeded() }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(light: tick % 3 != 0)
                if tick % 5 == 0 { await self.refreshAvailability() }
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// `light` refreshes only status + loaded models; a full refresh also re-lists installed models.
    func refresh(light: Bool = false) async {
        let backend = self.backend
        let kindAtStart = kind
        do {
            let version = try await backend.ping()
            guard kindAtStart == kind else { return }
            status = .online(version)
            availability[kind] = true
            if !light || models.isEmpty {
                models = try await backend.listModels()
                ensureSelection()
            }
            loaded = (try? await backend.loadedModels()) ?? []
            if detailsFor != settings.selectedModel { await refreshDetails() }
        } catch {
            guard kindAtStart == kind else { return }
            status = .offline(error.localizedDescription)
            availability[kind] = false
            loaded = []
        }
    }

    func refreshAvailability() async {
        await withTaskGroup(of: (BackendKind, Bool).self) { group in
            for k in BackendKind.allCases {
                let b = makeBackend(k)
                group.addTask { (k, (try? await b.ping()) != nil) }
            }
            for await (k, ok) in group { availability[k] = ok }
        }
    }

    private func ensureSelection() {
        if selectedModel != nil { return }
        let candidates = models.filter(isSelectable)
        let preferred = candidates.first { $0.catalog?.featured == true } ?? candidates.first
        settings.selectedModel = preferred?.id
        details = nil
        detailsFor = nil
    }

    func refreshDetails() async {
        guard let model = settings.selectedModel else { details = nil; return }
        detailsFor = model
        details = try? await backend.details(for: model)
    }

    // MARK: Downloads

    func pull(_ tag: String, selectWhenDone: Bool = false) {
        guard pulls[tag]?.task == nil else { return }
        let updates: AsyncThrowingStream<OllamaBackend.PullUpdate, Error>
        if kind == .mlx {
            updates = MLXRuntime.download(tag, bytes: ModelCatalog.variant(forTag: tag)?.bytes ?? 0)
        } else if let ollama {
            updates = ollama.pull(tag)
        } else {
            return
        }
        var state = PullState()
        state.task = Task { [weak self] in
            do {
                for try await update in updates {
                    guard let self else { return }
                    self.pulls[tag]?.status = Self.prettyPullStatus(update.status)
                    self.pulls[tag]?.fraction = update.fraction
                    self.pulls[tag]?.completed = update.completed
                    self.pulls[tag]?.total = update.total
                }
                guard let self else { return }
                self.pulls[tag] = nil
                await self.refresh()
                if selectWhenDone || self.selectedModel == nil,
                   let m = self.models.first(where: { $0.id == tag || $0.id == tag + ":latest" }) {
                    self.select(m)
                }
            } catch {
                guard let self else { return }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.pulls[tag] = nil
                } else {
                    self.pulls[tag]?.error = error.localizedDescription
                    self.pulls[tag]?.task = nil
                }
            }
        }
        pulls[tag] = state
    }

    func cancelPull(_ tag: String) {
        pulls[tag]?.task?.cancel()
        pulls[tag] = nil
    }

    func delete(_ name: String) async {
        do {
            if kind == .mlx {
                try await MLXRuntime.remove(name)
            } else if let ollama {
                try await ollama.delete(name)
            }
            if settings.selectedModel == name { settings.selectedModel = nil }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unload(_ name: String) async {
        guard let ollama else { return }
        try? await ollama.unload(name)
        loaded = (try? await ollama.loadedModels()) ?? []
    }

    static func prettyPullStatus(_ s: String) -> String {
        if s.hasPrefix("pulling") && s != "pulling manifest" { return "Downloading" }
        switch s {
        case "pulling manifest": return "Preparing"
        case "verifying sha256 digest": return "Verifying checksum"
        case "writing manifest": return "Finishing"
        case "success": return "Done"
        default: return s.capitalized
        }
    }

    // MARK: Starting a framework

    static let ollamaBinaryPaths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]

    var ollamaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
            || Self.ollamaBinaryPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var canStartFramework: Bool { kind == .mlx ? MLXRuntime.isInstalled : kind == .ollama && ollamaInstalled }

    func startFramework() {
        isStartingFramework = true
        if kind == .mlx { startMLX() } else { startOllama() }
        Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.refresh()
                if self?.status.isOnline == true { break }
            }
            self?.isStartingFramework = false
        }
    }

    private func startOllama() {
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Ollama.app"), configuration: .init())
        } else if let path = Self.ollamaBinaryPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    /// MLX LM has no service of its own, so the app runs it while it's the chosen framework.
    private func startMLXIfNeeded() {
        guard MLXRuntime.isInstalled else { return }
        Task { [weak self] in
            guard let self, self.kind == .mlx, (try? await self.backend.ping()) == nil else { return }
            self.startFramework()
        }
    }

    private func startMLX() {
        guard mlxServer?.isRunning != true else { return }
        mlxServer = MLXRuntime.startServer(port: URL(string: settings.baseURL(for: .mlx))?.port ?? 8081)
    }

    /// Stops a server the app started, which also frees the memory its model holds.
    func stopMLX() {
        mlxServer?.terminate()
        mlxServer = nil
    }
}
