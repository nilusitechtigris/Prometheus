import SwiftUI

/// Home's Ask face: the flame, one question and a box to answer it in. Asking here starts a chat, so there
/// is no page to pass through before the work begins. The switch in the corner turns Home to its other
/// face, Dev (HomeModeSwitch.swift).
struct HomePage: View {
    var body: some View {
        GeometryReader { box in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 4)
                    flamePlace
                    VStack(spacing: 10) {
                        Text("What should we work on?")
                            .font(.geist(44, weight: .medium))
                            .foregroundStyle(Forge.ink)
                        Text("Small models, serious work. Everything runs on this Mac.")
                            .font(.geist(16))
                            .foregroundStyle(Forge.dim)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    AskBox()
                        .frame(maxWidth: 760)
                        .padding(.top, 22)
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                // Fills the page, so the question sits in the middle of a tall window and scrolls in a short one.
                .frame(maxWidth: .infinity, minHeight: box.size.height)
            }
        }
    }

    /// The flame. It is lit each time this page is shown, and goes out with the page.
    private var flamePlace: some View {
        FlameView().frame(width: FlameView.size.width, height: FlameView.size.height)
    }
}

// MARK: - The question box

private struct AskBox: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    @Environment(DevSession.self) private var dev
    @State private var showOptions = false
    @State private var showHarness = false
    @State private var showContext = false
    @FocusState private var focused: Bool

    private let starters: [(title: String, starter: String)] = [
        ("Summarize", "Summarize this in 3 key points:\n\n"),
        ("Extract data", "Extract the names, dates and amounts from this as a table:\n\n"),
        ("Analyze content", "Analyze this and tell me what matters most:\n\n"),
    ]

    private var canSend: Bool { chat.canSend && !ui.homeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

    var body: some View {
        // What is typed lives in UIState, so it is still here after a look at Telemetry or another page.
        @Bindable var ui = ui
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Summarize this document in 3 key points…", text: $ui.homeDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.geist(17))
                    .lineLimit(2...6)
                    .focused($focused)
                    .onSubmit(send)
                    .accessibilityLabel("Your task")
                HStack(spacing: 8) {
                    // Each of the three is chosen here, in a menu of its own. The model and the harness
                    // used to lead away to Models and Settings, which lost the place.
                    let setup = SetupState(backends)
                    // With nothing able to answer yet, the first one says what is missing and leads to the
                    // chat page, which has the next step.
                    Button {
                        if setup == .ready { ui.showModelPicker.toggle() } else { ui.destination = .chat }
                    } label: {
                        chip(setup == .ready ? "cube" : "exclamationmark.circle",
                             setup == .ready ? (backends.selectedModel?.displayName ?? "Choose a model") : setup.title(backends.kind),
                             menu: setup == .ready)
                    }
                    .buttonStyle(.soft)
                    .help(setup == .ready ? "Choose the model and its quantization (⇧⌘M)" : setup.nextStep)
                    .popover(isPresented: $ui.showModelPicker, arrowEdge: .top) {
                        ModelPickerPopover { ui.showModelPicker = false }
                    }
                    Button { showHarness.toggle() } label: {
                        // The label is safe for either edition: "Harness" for everyone, the version's name in the lab.
                        chip(harnessOn ? "checkmark.shield" : "shield.slash",
                             harnessOn ? "\(settings.activeHarness.label) on" : "Harness off", tinted: harnessOn)
                    }
                    .buttonStyle(.soft)
                    .disabled(!backends.kind.supportsTools)
                    .help(backends.kind.supportsTools
                          ? "The harness checks a small model's maths, code and rules before you see the reply. Click to turn it on or off."
                          : "The harness works with Ollama and MLX LM")
                    .popover(isPresented: $showHarness, arrowEdge: .top) {
                        HarnessPopover { showHarness = false }
                    }
                    Button { showContext.toggle() } label: {
                        chip("text.alignleft", "\(Format.tokens(backends.effectiveContext)) context")
                    }
                    .buttonStyle(.soft)
                    .help("How much text the model keeps in view. More takes more memory.")
                    .popover(isPresented: $showContext, arrowEdge: .top) {
                        ContextPopover { showContext = false }
                    }
                    Spacer(minLength: 8)
                    Button { showOptions.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Forge.dim)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.soft)
                    .help("Temperature, response length and system instructions")
                    .accessibilityLabel("Options")
                    .popover(isPresented: $showOptions, arrowEdge: .bottom) { GenerationOptionsView().environment(settings) }
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(width: 40, height: 40)
                            .background(Palette.gradient, in: Circle())
                    }
                    .buttonStyle(.soft)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.55)
                    .help("Start this task in a new chat")
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Forge.card.opacity(0.9), in: shape)
            .overlay(shape.strokeBorder(focused ? Palette.accent.opacity(0.55) : Color.white.opacity(0.14), lineWidth: 1))
            // The flame's light falling on the box from above.
            .shadow(color: Palette.glow.opacity(0.2), radius: 30, y: -12)

            HStack(spacing: 8) {
                ForEach(starters, id: \.title) { starter in
                    Button {
                        ui.homeDraft = starter.starter
                        focused = true
                    } label: {
                        pill(starter.title)
                    }
                    .buttonStyle(.soft)
                    .help("Start from this template")
                }
                Button {
                    dev.isOn = true
                } label: {
                    pill("Build an app")
                }
                .buttonStyle(.soft)
                .help("Turn Home to Dev, where the agent writes the code and runs it")
            }
        }
        // Ask first: the box is ready for typing as soon as the page shows.
        .onAppear { focused = true }
    }

    /// One of the choices under the question: what it is now, and the mark of a menu.
    private func chip(_ symbol: String, _ title: String, tinted: Bool = false, menu: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(tinted ? Palette.accent : Forge.dim)
            Text(title).font(.uiCallout).foregroundStyle(Forge.ink).lineLimit(1)
            if menu {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Forge.faint)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Color.white.opacity(0.07), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .hoverFill(shape)
        .contentShape(shape)
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(.uiCallout)
            .foregroundStyle(Forge.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Forge.card.opacity(0.9), in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule(style: .circular))
    }

    private func send() {
        guard canSend else { return }
        let text = ui.homeDraft
        ui.homeDraft = ""
        ui.destination = .chat
        chat.newConversation()
        chat.send(text)
    }
}
