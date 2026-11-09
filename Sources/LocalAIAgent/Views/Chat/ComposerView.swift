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
            if let request = WebConsent.shared.pending {
                WebConsentCard(request: request)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let live = chat.live {
                HStack {
                    if let stage = live.stage { HarnessStageStrip(current: stage, round: live.round, speaker: live.speaker) }
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
            .animation(Motion.quick, value: chat.isGenerating)
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
                Label(harnessNote, systemImage: WebConsent.shared.policy == .allowed ? "globe" : "lock")
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
        .animation(Motion.quick, value: chat.isGenerating)
        .animation(Motion.quick, value: harnessOn)
        .animation(Motion.quick, value: WebConsent.shared.pending)
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
                TelemetryPill(compact: compact)
                DevPill(compact: compact)
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

    private var harnessNote: String {
        let version = settings.harnessVersion
        let name = "\(version.label) on"
        let thinking = version.alwaysThinks ? " Thinking stays on for its agents." : ""
        switch WebConsent.shared.policy {
        case .ask:
            return "\(name): math, code and rule checks stay on this Mac. It asks before each web search.\(thinking)"
        case .allowed:
            return "\(name): \(version == .tools ? "the model picks its own searches, which go" : "search terms go") to \(WebConsent.destinations). Code runs in a sandbox on this Mac.\(thinking)"
        case .off:
            return "\(name), offline: math, code and rule checks stay on this Mac. Web lookups are off.\(thinking)"
        }
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
            withAnimation(Motion.quick) { settings.thinkingEnabled.toggle() }
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
        .disabled(!backends.kind.supportsThinkingControl)
        .help(backends.kind.supportsThinkingControl
              ? (on ? "Thinking on — the model reasons before answering" : "Thinking off — faster, direct answers")
              : "Thinking is controlled by the framework")
    }
}

/// Picks the version of the harness for the next reply, or turns it off, at any point in a chat.
private struct HarnessPill: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    var compact = false
    @State private var show = false

    var body: some View {
        let on = settings.harnessEnabled && backends.kind.supportsTools
        let version = settings.harnessVersion
        Button {
            show.toggle()
        } label: {
            PickerPill {
                Image(systemName: "shield.lefthalf.filled")
                    .symbolEffect(.bounce, value: on)
                if on {
                    Text(version == .recommended ? (compact ? "On" : "Harness on") : (compact ? version.short : "Harness \(version.short)"))
                } else {
                    Text(compact ? "Off" : "Harness off")
                }
            }
            .font(.uiCallout.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Palette.accent : .secondary)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .overlay(Capsule().strokeBorder(on ? Palette.accent.opacity(0.6) : .clear, lineWidth: 1))
        .disabled(!backends.kind.supportsTools)
        .help(backends.kind.supportsTools
              ? (on ? "Harness on: code runs the math, checks each reply and can look facts up. Click to change it or turn it off."
                    : "Harness off: the plain model, with nothing checked. Click to turn it on.")
              : "The harness works with Ollama and MLX LM. Pick one of those under the message box to use it.")
        .accessibilityLabel(on ? "Harness, \(version.title)" : "Harness, off")
        .popover(isPresented: $show, arrowEdge: .top) {
            HarnessPopover { show = false }
        }
    }
}

struct HarnessPopover: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    let dismiss: () -> Void
    @State private var showVersions = false

    var body: some View {
        let on = settings.harnessEnabled
        let usual = settings.harnessVersion == .recommended
        VStack(alignment: .leading, spacing: 4) {
            Text("Harness").font(.uiHeadline).padding(.horizontal, 8).padding(.bottom, 4)
            PopoverRow(selected: !on) {
                settings.harnessEnabled = false
                dismiss()
            } content: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Off").font(.uiCallout.weight(.semibold))
                    Text("The plain model. Nothing is checked.").font(.uiCaption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            PopoverRow(selected: on && usual) {
                settings.harnessVersion = .recommended
                settings.harnessEnabled = true
                dismiss()
            } content: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("On").font(.uiCallout.weight(.semibold))
                    Text("Code runs the math, checks each reply and sends it back if it's wrong.")
                        .font(.uiCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            WebLookupsPicker()
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Button {
                withAnimation(Motion.quick) { showVersions.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showVersions ? 90 : 0))
                    Text("Other versions").font(.uiCallout)
                    if on, !usual { Text("· using \(settings.harnessVersion.title)").font(.uiCaption).foregroundStyle(Palette.accent) }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Earlier and newer designs of the harness, kept so you can compare them")

            if showVersions {
                ForEach(HarnessVersion.allCases) { version in
                    PopoverRow(selected: on && settings.harnessVersion == version) {
                        settings.harnessVersion = version
                        settings.harnessEnabled = true
                        dismiss()
                    } content: {
                        HarnessVersionLabel(version: version)
                    }
                }
            }
            Text(footnote)
                .font(.uiCaption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        .padding(12)
        .frame(width: 380)
        .onAppear { showVersions = on && !usual }
    }

    private var footnote: String {
        let canCall = backends.details?.capabilities.contains("tools") ?? true
        return (showVersions && !canCall ? "This model can't call tools, so v1 would answer without them. " : "")
            + "Applies from your next message."
    }
}

/// How the harness may use the web. The same three choices show in the Harness menu and in Settings.
struct WebLookupsPicker: View {
    var body: some View {
        @Bindable var consent = WebConsent.shared
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Web lookups", systemImage: "globe").font(.uiCallout.weight(.medium))
                Spacer()
                Picker("Web lookups", selection: $consent.policy) {
                    ForEach(WebConsent.Policy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text(caption)
                .font(.uiCaption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        switch WebConsent.shared.policy {
        case .ask: return "For a fact, the harness shows you each search first. If you allow it, the search goes to \(WebConsent.destinations), and it reads pages from the trusted sites."
        case .allowed: return "For a fact, search terms go to \(WebConsent.destinations), and pages come from the trusted sites."
        case .off: return "Nothing is looked up in chat. Math, code and rule checks still run on this Mac."
        }
    }
}

/// The question the harness asks before anything leaves this Mac. It sits above the message box, or along
/// the foot of the window when another page is showing. What it would send is shown in full.
struct WebConsentCard: View {
    let request: WebConsent.Request

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "globe").font(.uiTitle2).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.isSearch ? "Look this up?" : "Open this page?").font(.uiCallout.weight(.semibold))
                Text(request.isSearch ? "“\(request.detail)”" : request.detail)
                    .font(.uiCallout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(explanation)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // No keyboard shortcut on purpose: a yes should be a click, not a Return meant for the message box.
            Button("Not now") { WebConsent.shared.answer(.notNow) }
                .help("Answer without looking anything up")
            Button("Always allow") { WebConsent.shared.answer(.always) }
                .help("Stop asking. You can change this in the Harness menu")
            Button("Allow once") { WebConsent.shared.answer(.once) }
                .buttonStyle(AccentButtonStyle(compact: true))
                .help(request.isSearch ? "Send this search and read the pages it finds" : "Open this page")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var explanation: String {
        request.isSearch
            ? "This search would go to \(WebConsent.destinations), and the harness would read pages it finds on the trusted sites. Those sites see the search, the page addresses and your IP address. Nothing else from your chat is sent."
            : "The site sees this address and your IP address. Nothing else from your chat is sent."
    }
}

/// Opens or collapses the hardware telemetry under the chat.
private struct TelemetryPill: View {
    @Environment(AppSettings.self) private var settings
    var compact = false

    var body: some View {
        let on = settings.telemetryOpen
        Button {
            withAnimation(Motion.quick) { settings.telemetryOpen.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                if !compact { Text("Telemetry") }
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
        .help("\(on ? "Collapse" : "Open") the hardware telemetry (⌥⌘1)")
        .accessibilityLabel("Telemetry, \(on ? "on" : "off")")
    }
}

/// The harness's steps while it works on a reply, and the round once it's looping.
private struct HarnessStageStrip: View {
    let current: HarnessStage
    let round: Int
    var speaker: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(Palette.accent)
            if let speaker { Text(speaker).fontWeight(.semibold).foregroundStyle(Palette.accent) }
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
                case .waiting: Text(WebConsent.shared.pending != nil ? "Waiting for your answer" : live.stage == .understand || live.stage == .act ? "Working…" : "Waiting for first token…")
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
