import SwiftUI

struct ComposerView: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @FocusState private var focused: Bool
    @State private var showOptions = false
    @State private var sentCount = 0

    var body: some View {
        @Bindable var ui = ui

        VStack(spacing: 10) {
            if let live = chat.live {
                HStack {
                    if let stage = live.stage { HarnessStageStrip(current: stage, round: live.round) }
                    Spacer()
                    LiveTicker(live: live)
                }
                .padding(.horizontal, 8)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $ui.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...10)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.vertical, 7)
                    .disabled(!backends.status.isOnline)

                if chat.isGenerating {
                    Button(action: chat.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.primary.opacity(0.85)))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating (⌘.)")
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .symbolEffect(.bounce, value: sentCount)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(canSend ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(.quaternary)))
                            .foregroundStyle(Palette.onAccent)
                            .shadow(color: canSend ? Palette.accent.opacity(0.45) : .clear, radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send (↩) · new line with ⌥↩")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: chat.isGenerating)
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassPanel(cornerRadius: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.55) : Color.primary.opacity(0.08),
                                  lineWidth: focused ? 1.5 : 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)

            // Framework · Model + quant · Context · Think · Temp. Falls back to a compact row on narrow windows.
            ViewThatFits(in: .horizontal) {
                controlRow(compact: false)
                controlRow(compact: true)
                controlRow(compact: true, narrow: true)
            }
            .padding(.horizontal, 4)

            if harnessOn {
                Label("Harness on: search terms go to Wikipedia, Stack Overflow, arXiv and MDN. Code runs in a sandbox on this Mac.", systemImage: "globe")
                    .font(.uiCaption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: chat.isGenerating)
        .onAppear { focused = true }
        .onChange(of: ui.composerFocusRequest) { focused = true }
    }

    /// `narrow` lets the row shrink to fit, shortening the model name, for tight panels.
    private func controlRow(compact: Bool, narrow: Bool = false) -> some View {
        HStack(spacing: 0) {
            let controls = GlassGroup(spacing: 6) {
                FrameworkPickerButton(compact: compact)
                ModelPickerButton(narrow: narrow)
                ContextPickerButton(compact: compact)
                if backends.supportsThinking { ThinkPill(compact: compact) }
                HarnessPill(compact: compact)
                temperaturePill(compact: compact)
            }
            if narrow {
                controls
            } else {
                controls.fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    private func temperaturePill(compact: Bool) -> some View {
        Button {
            showOptions.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                Text(compact ? Format.samplingTemperature(settings.temperature)
                             : "Temp \(Format.samplingTemperature(settings.temperature))").monospacedDigit()
            }
            .font(.uiCallout)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .help("Temperature, response length and system instructions")
        .popover(isPresented: $showOptions, arrowEdge: .top) {
            GenerationOptionsView().environment(settings)
        }
    }

    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

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
        sentCount += 1
        chat.send(text)
    }
}

private struct ThinkPill: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    var compact = false

    var body: some View {
        let on = settings.thinkingEnabled
        Button {
            withAnimation(.snappy) { settings.thinkingEnabled.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain.head.profile")
                    .symbolEffect(.bounce, value: on)
                if !compact { Text("Think") }
            }
            .font(.uiCallout.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Palette.accent : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Plain glass + accent outline: tinted glass made the whole chat column drop out of window captures.
        .glassCapsule(interactive: true)
        .overlay(Capsule().strokeBorder(on ? Palette.accent.opacity(0.6) : .clear, lineWidth: 1))
        .disabled(backends.kind != .ollama)
        .help(backends.kind == .ollama
              ? (on ? "Thinking on — the model reasons before answering" : "Thinking off — faster, direct answers")
              : "Thinking is controlled by the framework")
    }
}

/// Turns the harness on or off for the next reply, at any point in a chat.
private struct HarnessPill: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    var compact = false

    var body: some View {
        let on = settings.harnessEnabled && backends.kind.supportsTools
        Button {
            withAnimation(.snappy) { settings.harnessEnabled.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shield.lefthalf.filled")
                    .symbolEffect(.bounce, value: on)
                if !compact { Text("Harness") }
            }
            .font(.uiCallout.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Palette.accent : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .overlay(Capsule().strokeBorder(on ? Palette.accent.opacity(0.6) : .clear, lineWidth: 1))
        .disabled(!backends.kind.supportsTools)
        .help(backends.kind.supportsTools
              ? (on ? "Harness on: it picks tools for each message, so search terms leave this Mac. Click to turn it off."
                    : "Harness off: everything stays on this Mac. Click to give the model web search and a code sandbox.")
              : "The harness needs Ollama for now")
        .accessibilityLabel("Harness, \(on ? "on" : "off")")
    }
}

/// The harness's steps while it works on a reply, and the round once it's looping.
private struct HarnessStageStrip: View {
    let current: HarnessStage
    let round: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(Palette.accent)
            if round > 1 { Text("Round \(round)").fontWeight(.semibold).foregroundStyle(Palette.accent) }
            ForEach(HarnessStage.allCases) { stage in
                HStack(spacing: 3) {
                    if stage.rawValue < current.rawValue { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                    Text(stage.title)
                }
                .fontWeight(stage == current ? .semibold : .regular)
                .foregroundStyle(stage == current ? AnyShapeStyle(Palette.accent) : stage.rawValue < current.rawValue ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.uiCaption)
    }
}

/// Live generation numbers next to the composer while a response streams.
private struct LiveTicker: View {
    let live: LiveGeneration

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 10) {
                switch live.phase {
                case .waiting: Text(live.stage == .understand || live.stage == .act ? "Working…" : "Waiting for first token…")
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
                HStack(spacing: 4) {
                    Image(systemName: "stopwatch")
                    Text(Format.seconds(Date().timeIntervalSince(live.startedAt)))
                }
                if live.thinkingTokens > 0 {
                    Text("\(live.thinkingTokens) thinking · \(live.tokens - live.thinkingTokens) output")
                }
            }
            .font(.uiCaption.monospacedDigit())
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
                    Text("Temperature").font(.uiHeadline)
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
                HStack {
                    Text("Precise"); Spacer(); Text("Balanced"); Spacer(); Text("Creative")
                }
                .font(.uiCaption2)
                .foregroundStyle(.secondary)
            }

            Picker("Max response length", selection: $settings.maxResponseTokens) {
                Text("Unlimited").tag(0)
                ForEach([256, 512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0) tokens").tag($0) }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System instructions").font(.uiHeadline)
                    Spacer()
                    Button("Reset") { settings.systemPrompt = AppSettings.defaultSystemPrompt }
                        .controlSize(.small)
                        .disabled(settings.systemPrompt == AppSettings.defaultSystemPrompt)
                }
                TextEditor(text: $settings.systemPrompt)
                    .font(.uiCallout)
                    .frame(height: 170)
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
