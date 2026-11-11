import SwiftUI

/// The start page: the flame, one question and a box to answer it in. Asking here starts a chat, so there
/// is no page to pass through before the work begins. Every number on it comes from this Mac.
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
                    HomeFooter()
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
    @State private var task = ""
    @State private var showOptions = false
    @FocusState private var focused: Bool

    private let starters: [(title: String, starter: String)] = [
        ("Summarize", "Summarize this in 3 key points:\n\n"),
        ("Extract data", "Extract the names, dates and amounts from this as a table:\n\n"),
        ("Analyze content", "Analyze this and tell me what matters most:\n\n"),
    ]

    private var canSend: Bool { chat.canSend && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Summarize this document in 3 key points…", text: $task, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.geist(17))
                    .lineLimit(2...6)
                    .focused($focused)
                    .onSubmit(send)
                    .accessibilityLabel("Your task")
                HStack(spacing: 8) {
                    // The model in use. With nothing able to answer yet, it says what is missing and leads
                    // to the chat page, which has the next step.
                    let setup = SetupState(backends)
                    Button { ui.destination = setup == .ready ? .library : .chat } label: {
                        chip(setup == .ready ? "cube" : "exclamationmark.circle",
                             setup == .ready ? (backends.selectedModel?.displayName ?? "Choose a model") : setup.title(backends.kind),
                             outlined: true)
                    }
                    .buttonStyle(.soft)
                    .help(setup == .ready ? "Change the model" : setup.nextStep)
                    Button {
                        ui.settingsTab = .harness
                        ui.destination = .settings
                    } label: {
                        // The label is safe for either edition: "Harness" for everyone, the version's name in the lab.
                        chip(harnessOn ? "checkmark.shield" : "shield.slash",
                             harnessOn ? "\(settings.activeHarness.label) on" : "Harness off", tinted: harnessOn)
                    }
                    .buttonStyle(.soft)
                    .help("The harness checks a small model's maths, code and rules before you see the reply")
                    Menu {
                        ForEach(AppSettings.contextOptions, id: \.self) { length in
                            Button("\(length / 1024)K") { settings.contextLength = length }
                        }
                    } label: {
                        chip("text.alignleft", "\(settings.contextLength / 1024)K context")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("How much text the model keeps in view. More takes more memory.")
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
                        task = starter.starter
                        focused = true
                    } label: {
                        pill(starter.title)
                    }
                    .buttonStyle(.soft)
                    .help("Start from this template")
                }
                Button {
                    dev.isOn = true
                    ui.destination = .chat
                } label: {
                    pill("Build an app")
                }
                .buttonStyle(.soft)
                .help("Open Dev mode, where the agent writes the code and runs it")
            }
        }
        // Ask first: the box is ready for typing as soon as the page shows.
        .onAppear { focused = true }
    }

    private func chip(_ symbol: String, _ title: String, outlined: Bool = false, tinted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(tinted ? Palette.accent : Forge.dim)
            Text(title).font(.uiCallout).foregroundStyle(outlined ? Forge.ink : Forge.dim).lineLimit(1)
        }
        .padding(.horizontal, outlined ? 11 : 6)
        .frame(height: 32)
        .background(outlined ? Color.white.opacity(0.07) : Color.clear, in: shape)
        .overlay(shape.strokeBorder(outlined ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1))
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
        let text = task
        task = ""
        ui.destination = .chat
        chat.newConversation()
        chat.send(text)
    }
}

// MARK: - Foot of the page

/// The last task at the left and this Mac's state at the right, both from real data.
private struct HomeFooter: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            if let conversation = chat.conversations.first(where: { !$0.messages.isEmpty }) {
                recent(conversation)
            }
            Spacer(minLength: 0)
            hardware
        }
    }

    private func recent(_ conversation: Conversation) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let running = conversation.messages.last?.id == chat.streamingMessageID && chat.streamingMessageID != nil
        return Button {
            chat.selectedID = conversation.id
            ui.destination = .chat
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .medium)).foregroundStyle(Forge.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title).font(.uiCallout.weight(.medium)).foregroundStyle(Forge.ink).lineLimit(1)
                    Group {
                        if running {
                            Text("Running…")
                        } else if conversation.messages.last?.errorText != nil {
                            // A chat whose last reply failed isn't a finished task.
                            Text("Failed · \(TestFormat.relative(conversation.updatedAt))")
                        } else if conversation.messages.last?.role == .user {
                            Text("No reply · \(TestFormat.relative(conversation.updatedAt))")
                        } else {
                            Text("Completed · \(TestFormat.relative(conversation.updatedAt))")
                        }
                    }
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(width: 300, height: 52)
            .background(Forge.card.opacity(0.9), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .help("Open your last task")
    }

    private var hardware: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 22) {
            stat("GPU", monitor.gpu.points.last.map { String(format: "%.0f%%", $0.value) } ?? "—")
            stat("Memory", monitor.snapshot.memoryPercent.map { String(format: "%.0f%%", $0) } ?? "—")
            stat("Thermal", thermal)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Forge.card.opacity(0.9), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var thermal: String {
        switch monitor.snapshot.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "—"
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.uiCaption).foregroundStyle(Forge.dim)
            Text(value).font(.uiCallout.weight(.semibold)).foregroundStyle(Forge.ink).monospacedDigit()
        }
    }
}
