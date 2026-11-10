import AppKit
import SwiftUI

struct EmptyChatView: View {
    @Environment(BackendController.self) private var backends

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                switch backends.status {
                case .checking:
                    ProgressView("Connecting to \(backends.kind.displayName)…")
                case .offline:
                    FrameworkSetupCard()
                case .online:
                    if backends.selectedModel == nil {
                        FirstModelCard()
                    } else {
                        WelcomeHero()
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WelcomeHero: View {
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(SystemMonitor.self) private var monitor
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings

    private let suggestions: [(String, String, String)] = [
        ("lightbulb", "Explain a concept", "Explain how transformers in large language models work, in simple terms with an analogy."),
        ("chevron.left.forwardslash.chevron.right", "Write some code", "Write a Swift function that removes duplicate elements from an array while preserving order, with a short explanation."),
        ("list.bullet.rectangle", "Plan something", "Help me plan a productive week: give me a simple daily structure with focus blocks and breaks."),
        ("envelope", "Draft a message", "Draft a friendly, concise email asking a colleague to review my project proposal by Friday."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                BrandMark(size: 64)
                BrandWordmark(size: 24)
                Text(Brand.tagline)
                    .font(.uiCallout)
                    .foregroundStyle(Palette.accent)
                if let model = backends.selectedModel {
                    Text("Running **\(model.displayName)** on your \(monitor.chipName)\(settings.harnessEnabled && backends.kind.supportsTools ? "." : " — nothing leaves this Mac.")")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            if backends.kind.supportsTools {
                Button { chat.runDemo() } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "rectangle.split.2x1.fill").font(.uiTitle2).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("See the harness at work").font(.uiCallout.weight(.semibold))
                            Text("Three questions, each asked twice on this Mac: the plain model, then the harness. Code says what it could check. About a minute.")
                                .font(.uiCaption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill").foregroundStyle(Palette.accent)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.soft)
                .disabled(!chat.canCompare)
                .help("Runs on your own model. Nothing leaves this Mac for these three")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(suggestions, id: \.1) { symbol, title, prompt in
                    Button {
                        chat.send(prompt)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title).font(.uiCallout.weight(.semibold))
                                Text(prompt).font(.uiCaption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.soft)
                    .disabled(!chat.canSend)
                }
            }
        }
    }
}

private struct FrameworkSetupCard: View {
    @Environment(BackendController.self) private var backends
    @State private var askedForOllama = false
    @State private var showSteps = false

    var body: some View {
        // Looked at again every two seconds: installing Ollama changes nothing the app is told about.
        TimelineView(.periodic(from: .now, by: 2)) { _ in card }
    }

    private var needsOllama: Bool { backends.kind == .ollama && !backends.ollamaInstalled }
    private var name: String { backends.kind.displayName }

    private var card: some View {
        VStack(spacing: 18) {
            BrandMark(size: 56)
            VStack(spacing: 6) {
                Text(needsOllama ? "First, get Ollama" : "\(name) isn't running")
                    .font(.uiTitle2.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
            ForEach(backends.otherRunning) { kind in
                Button("\(kind.displayName) is running on this Mac. Use it instead") { backends.switchBackend(to: kind) }
                    .buttonStyle(.link)
            }
            if backends.kind != .ollama, backends.otherRunning.isEmpty {
                Button("New here? Ollama needs no Terminal. Use Ollama") { backends.switchBackend(to: .ollama) }
                    .buttonStyle(.link)
            }
            steps
        }
        .frame(maxWidth: 520)
    }

    private var explanation: String {
        if needsOllama {
            return "Prometheus runs models with Ollama, a free app that keeps them on this Mac. Download it, move it to Applications and open it once. This page carries on by itself."
        }
        if backends.canStartFramework { return "\(name) is on this Mac but isn't running. Start it and this page carries on by itself." }
        return "Prometheus talks to \(name) on this Mac, at \(backends.settings.baseURL(for: backends.kind)). Start it and this page carries on by itself."
    }

    @ViewBuilder
    private var action: some View {
        if needsOllama {
            VStack(spacing: 8) {
                Button {
                    if let page = BackendController.ollamaDownloadPage { NSWorkspace.shared.open(page) }
                    askedForOllama = true
                } label: {
                    Label("Get Ollama", systemImage: "arrow.down.circle.fill").padding(.horizontal, 8)
                }
                .controlSize(.large)
                .buttonStyle(AccentButtonStyle(compact: true))
                if askedForOllama {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Ollama. Once it's open, the next step shows here.")
                    }
                    .font(.uiCaption).foregroundStyle(.secondary)
                } else {
                    Text("Opens ollama.com in your browser. Prometheus sends nothing.")
                        .font(.uiCaption).foregroundStyle(.secondary)
                }
            }
        } else if backends.canStartFramework {
            Button {
                backends.startFramework()
            } label: {
                if backends.isStartingFramework {
                    ProgressView().controlSize(.small).padding(.horizontal, 30)
                } else {
                    Label("Start \(name)", systemImage: "play.fill").padding(.horizontal, 8)
                }
            }
            .controlSize(.large)
            .buttonStyle(AccentButtonStyle(compact: true))
            .disabled(backends.isStartingFramework)
        }
    }

    /// The typed way, for people who want it. It is the only way for a framework the app can't start, so
    /// there it's open from the start.
    private var steps: some View {
        let onlyWay = !needsOllama && !backends.canStartFramework
        return DisclosureGroup(backends.kind == .lmStudio ? "How to set up LM Studio" : "Set it up in Terminal instead",
                               isExpanded: Binding(get: { showSteps || onlyWay }, set: { showSteps = $0 })) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(backends.kind.setupSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.uiCaption.bold()).frame(width: 18, height: 18).background(Circle().fill(.quaternary))
                        Text(step).font(.system(.callout, design: step.contains(" ") && !step.contains("→") && step.first?.isLowercase == true ? .monospaced : .default))
                            .textSelection(.enabled)
                        Spacer()
                        if step.first?.isLowercase == true {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(step, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .help("Copy command")
                        }
                    }
                }
                Text("Expected at \(backends.settings.baseURL(for: backends.kind)). You can change that in Settings.")
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                if case .offline(let reason) = backends.status, !reason.isEmpty {
                    Text(reason).font(.uiCaption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
        .font(.uiCallout)
        .foregroundStyle(.secondary)
    }
}

private struct FirstModelCard: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(UIState.self) private var ui
    @State private var showOthers = false

    var body: some View {
        let picks = StarterModels.pick(from: ModelCatalog.all.filter(\.featured)) {
            MemoryFit.verdict(requiredBytes: backends.memoryEstimate(for: $0), budget: monitor.gpuBudgetBytes)
        }
        let memory = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        VStack(spacing: 18) {
            BrandMark(size: 56)
            VStack(spacing: 6) {
                Text("Now a model").font(.uiTitle2.weight(.semibold))
                Text(picks.tight
                     ? "Models run on this Mac and stay on it. With \(memory) GB of memory even the smallest verified models are a tight fit, so expect them to be slow."
                     : "Models run on this Mac and stay on it. This one is picked for your \(monitor.chipName) with \(memory) GB of memory.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if backends.kind.supportsModelDownloads {
                if let starter = picks.models.first, let variant = starter.variants(for: backends.kind).first(where: \.isDefault) ?? starter.variants(for: backends.kind).first {
                    StarterDownload(model: starter, variant: variant)
                }
                if picks.models.count > 1 {
                    DisclosureGroup("Other models that fit this Mac", isExpanded: $showOthers) {
                        VStack(spacing: 10) {
                            ForEach(picks.models.dropFirst()) { ModelCard(model: $0, compact: true) }
                        }
                        .padding(.top, 8)
                    }
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Load a model in \(backends.kind.displayName). Verified models show up here by themselves.")
                    .foregroundStyle(.secondary)
            }
            Button("Browse the full library") { ui.destination = .library }
                .buttonStyle(.link)
        }
        .frame(maxWidth: 560)
    }
}

/// Which models a new user is offered first.
enum StarterModels {
    /// The featured models that fit this Mac well, in catalog order. If none does, the two that need the least
    /// memory, marked as a tight fit so the page can say so.
    static func pick(from featured: [CatalogModel], fit: (CatalogModel) -> MemoryFit.Verdict) -> (models: [CatalogModel], tight: Bool) {
        let great = featured.filter { fit($0) == .great }
        if !great.isEmpty { return (Array(great.prefix(3)), false) }
        let possible = featured.filter { fit($0) == .tight }
        return (Array((possible.isEmpty ? featured : possible).prefix(2)), true)
    }
}

/// One button from "no model" to a model that's chosen and ready, with the download's progress and, if it
/// fails, what to do about it.
private struct StarterDownload: View {
    @Environment(BackendController.self) private var backends
    let model: CatalogModel
    let variant: QuantVariant

    var body: some View {
        let pull = backends.pulls[variant.tag]
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName).font(.uiHeadline)
                    Text(model.summary).font(.uiCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("\(model.publisher) · \(model.license) · \(variant.size) to download")
                        .font(.uiCaption).foregroundStyle(.secondary)
                }
                if let pull, let problem = pull.error {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.uiCallout)
                        .foregroundStyle(Palette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") {
                        backends.cancelPull(variant.tag)
                        backends.pull(variant.tag, selectWhenDone: true)
                    }
                    .buttonStyle(AccentButtonStyle(compact: true))
                } else if let pull {
                    ProgressView(value: pull.fraction)
                    HStack {
                        Text(pull.total > 0 ? "\(pull.status) · \(Format.bytes(pull.completed)) of \(Format.bytes(pull.total))" : pull.status)
                            .font(.uiCaption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { backends.cancelPull(variant.tag) }.buttonStyle(.link).font(.uiCaption)
                    }
                    Text("You can leave this page. The download carries on, and the model is chosen when it's done.")
                        .font(.uiCaption).foregroundStyle(.secondary)
                } else {
                    Button {
                        backends.pull(variant.tag, selectWhenDone: true)
                    } label: {
                        Label("Download \(model.displayName)", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(AccentButtonStyle(compact: true))
                    .disabled(!backends.status.isOnline)
                }
            }
        }
    }
}
