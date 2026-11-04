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
                BrandMark(size: 92)
                    .padding(.bottom, 6)
                BrandWordmark(size: 38)
                Text(Brand.tagline)
                    .font(Font.usesGeist ? .geistMono(13) : Brand.display(17, weight: .regular).italic())
                    .foregroundStyle(.secondary)
                if let model = backends.selectedModel {
                    Text("Running **\(model.displayName)** on your \(monitor.chipName)\(settings.harnessEnabled && backends.kind.supportsTools ? "." : " — nothing leaves this Mac.")")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
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
                    .buttonStyle(.plain)
                    .disabled(!chat.canSend)
                }
            }
        }
    }
}

private struct FrameworkSetupCard: View {
    @Environment(BackendController.self) private var backends

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "powerplug")
                .font(.system(size: 40))
                .foregroundStyle(Palette.accent)
            VStack(spacing: 6) {
                Text("\(backends.kind.displayName) isn't running")
                    .font(.uiTitle2.weight(.semibold))
                Text("The app talks to a local inference framework on this Mac. Start it, or pick another framework from the toolbar.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if backends.kind == .ollama && backends.ollamaInstalled {
                Button {
                    backends.startOllama()
                } label: {
                    if backends.isStartingOllama {
                        ProgressView().controlSize(.small).padding(.horizontal, 30)
                    } else {
                        Label("Start Ollama", systemImage: "play.fill").padding(.horizontal, 8)
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(backends.isStartingOllama)
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set up \(backends.kind.displayName)").font(.uiHeadline)
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
                    Text("Expected at \(backends.settings.baseURL(for: backends.kind)) — change it in Settings.")
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 520)
        }
    }
}

private struct FirstModelCard: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 40))
                .foregroundStyle(Palette.accent)
            VStack(spacing: 6) {
                Text("Download your first model")
                    .font(.uiTitle2.weight(.semibold))
                Text("These verified models are picked for your \(monitor.chipName) with \(Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())) GB of memory.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if backends.kind.supportsModelDownloads {
                VStack(spacing: 10) {
                    ForEach(recommended) { model in
                        ModelCard(model: model, compact: true)
                    }
                }
                .frame(maxWidth: 560)
            } else {
                Text("Load a model in \(backends.kind.displayName); verified models appear here automatically.")
                    .foregroundStyle(.secondary)
            }
            Button("Browse the full library") { ui.destination = .library }
                .buttonStyle(.link)
        }
    }

    private var recommended: [CatalogModel] {
        let fits = ModelCatalog.all.filter { $0.featured }.filter {
            MemoryFit.verdict(requiredBytes: backends.memoryEstimate(for: $0), budget: monitor.gpuBudgetBytes) == .great
        }
        return Array(fits.prefix(3))
    }
}
