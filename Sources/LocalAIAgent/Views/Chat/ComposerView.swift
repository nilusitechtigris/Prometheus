import SwiftUI

struct ComposerView: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @FocusState private var focused: Bool
    @State private var showOptions = false

    var body: some View {
        @Bindable var ui = ui
        @Bindable var settings = settings

        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $ui.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...10)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.vertical, 6)
                    .disabled(!backends.status.isOnline)

                if chat.isGenerating {
                    Button(action: chat.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.primary.opacity(0.85)))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating (⌘.)")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(canSend ? AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.quaternary)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send (↩)")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.5) : Color.secondary.opacity(0.25), lineWidth: focused ? 1.5 : 0.5))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

            HStack(spacing: 8) {
                if backends.supportsThinking {
                    Toggle(isOn: $settings.thinkingEnabled) {
                        Label("Think", systemImage: "brain.head.profile")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(backends.kind == .ollama ? "Let the model reason step by step before answering" : "Thinking is controlled by the framework")
                    .disabled(backends.kind != .ollama)
                }

                Button {
                    showOptions.toggle()
                } label: {
                    Label("Temp \(String(format: "%.1f", settings.temperature))", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .popover(isPresented: $showOptions, arrowEdge: .top) {
                    GenerationOptionsView().environment(settings)
                }

                if let live = chat.live {
                    LiveTicker(live: live)
                }
                Spacer()
                Text("↩ send · ⌥↩ new line")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .onChange(of: ui.composerFocusRequest) { focused = true }
    }

    private var canSend: Bool {
        chat.canSend && !ui.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholder: String {
        if !backends.status.isOnline { return "Start \(backends.kind.displayName) to begin chatting" }
        if let model = backends.selectedModel { return "Message \(model.displayName)…" }
        return "Choose a model to begin"
    }

    private func send() {
        guard canSend else { return }
        let text = ui.draft
        ui.draft = ""
        chat.send(text)
    }
}

/// Live generation numbers next to the composer while a response streams.
private struct LiveTicker: View {
    let live: LiveGeneration

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 10) {
                switch live.phase {
                case .waiting: Text("Waiting for first token…")
                case .thinking: Text("Thinking")
                case .answering: Text("Answering")
                }
                if let ttft = live.timeToFirstToken {
                    HStack(spacing: 4) {
                        StatusDot(level: Thresholds.timeToFirstToken.level(ttft), size: 6)
                        Text("TTFT \(Format.seconds(ttft))")
                    }
                }
                if let tps = live.tokensPerSecond {
                    HStack(spacing: 4) {
                        StatusDot(level: Thresholds.tokensPerSecond.level(tps), size: 6)
                        Text("\(Format.rate(tps)) tok/s")
                    }
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct GenerationOptionsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Temperature").font(.headline)
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
                HStack {
                    Text("Precise"); Spacer(); Text("Balanced"); Spacer(); Text("Creative")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Picker("Max response length", selection: $settings.maxResponseTokens) {
                Text("Unlimited").tag(0)
                ForEach([256, 512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0) tokens").tag($0) }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System instructions").font(.headline)
                    Spacer()
                    Button("Reset") { settings.systemPrompt = AppSettings.defaultSystemPrompt }
                        .controlSize(.small)
                        .disabled(settings.systemPrompt == AppSettings.defaultSystemPrompt)
                }
                TextEditor(text: $settings.systemPrompt)
                    .font(.callout)
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
