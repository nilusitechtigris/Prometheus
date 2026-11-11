import SwiftUI

/// The start page: the flame, one question and a box to answer it in. What is typed here starts the work on
/// the Chat page: a chat, or with Dev on a project built by the agent. So there is no page to pass through
/// before the work begins.
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
    @State private var showProject = false
    @FocusState private var focused: Bool

    private var draft: String { ui.homeDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }
    /// Whether the task will be done both ways. In a chat that needs a framework the harness works with, so
    /// a toggle left on doesn't count where it can't be honoured (and can't be turned off, being disabled).
    private var compare: Bool { ui.homeCompare && (dev.isOn || backends.kind.supportsTools) }

    /// Things to start from: questions for a chat, small apps for Dev.
    private var starters: [(title: String, text: String)] {
        guard dev.isOn else {
            return [("Summarize", "Summarize this in 3 key points:\n\n"),
                    ("Extract data", "Extract the names, dates and amounts from this as a table:\n\n"),
                    ("Analyze content", "Analyze this and tell me what matters most:\n\n")]
        }
        return DevCompare.prompts.filter { $0.group == "Quick" }.prefix(4).map { ($0.title, $0.text) }
    }

    private var canSend: Bool {
        guard !draft.isEmpty else { return false }
        if dev.isOn {
            // A comparison makes its own folders, and a request with no project yet asks for one on the way.
            return compare || dev.project == nil ? dev.canCompare : dev.canSend
        }
        return compare ? chat.canCompare : chat.canSend
    }

    private var placeholder: String {
        if dev.isOn { return compare ? "A web app to build twice: harness off, then on…" : "What should the agent build or change?" }
        return "Summarize this document in 3 key points…"
    }

    var body: some View {
        // What is typed lives in UIState, so it is still here after a look at Telemetry or another page.
        @Bindable var ui = ui
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(placeholder, text: $ui.homeDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.geist(17))
                    .lineLimit(2...6)
                    .focused($focused)
                    .onSubmit(send)
                    .accessibilityLabel("Your task")
                kindRow
                HStack(spacing: 8) {
                    answerChips
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
                    .help(sendHelp)
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
                        ui.homeDraft = starter.text
                        focused = true
                    } label: {
                        pill(starter.title)
                    }
                    .buttonStyle(.soft)
                    .help(dev.isOn ? "Start from this request" : "Start from this template")
                }
                if !dev.isOn {
                    Button {
                        dev.isOn = true
                        focused = true
                    } label: {
                        pill("Build an app")
                    }
                    .buttonStyle(.soft)
                    .help("Turn Dev on, where the agent writes the code and runs it")
                }
            }
        }
        // Ask first: the box is ready for typing as soon as the page shows.
        .onAppear { focused = true }
        .animation(Motion.quick, value: dev.isOn)
        .animation(Motion.quick, value: ui.homeCompare)
    }

    // MARK: What kind of work

    /// Two switches, each explained by a card under the pointer: Dev, and doing the task both ways. With Dev
    /// on, the project the agent will work in is chosen here too.
    private var kindRow: some View {
        @Bindable var ui = ui
        return HStack(spacing: 8) {
            Button { dev.isOn.toggle() } label: {
                toggleChip("chevron.left.forwardslash.chevron.right", "Dev", on: dev.isOn)
            }
            .buttonStyle(.soft)
            .hoverCard("Dev mode", "Instead of an answer in a chat, a coding agent builds what you ask for in a project folder. It writes the files, runs them and fixes what fails. Web apps and games open in Preview, in the window. It all stays on this Mac.")
            .accessibilityLabel("Dev mode")
            .accessibilityValue(dev.isOn ? "on" : "off")

            if dev.isOn && !compare {
                Button { showProject.toggle() } label: {
                    chip("folder", dev.project.map { Self.short($0.name) } ?? "Choose a project", tinted: dev.project != nil)
                }
                .buttonStyle(.soft)
                .help(dev.project?.root.path ?? "The folder the agent works in. Start a new one or open one you have.")
                .popover(isPresented: $showProject, arrowEdge: .top) {
                    DevProjectMenu(project: dev.project) { showProject = false }
                }
                .transition(.opacity)
            }

            Button { ui.homeCompare.toggle() } label: {
                toggleChip("square.split.2x1", "Compare", on: compare)
            }
            .buttonStyle(.soft)
            .disabled(!dev.isOn && !backends.kind.supportsTools)
            .hoverCard("See both results",
                       dev.isOn ? "Your request is built twice, in two new folders: once with the harness off and once with it on. Both apps open side by side with the same scorecard, so you see what the harness adds."
                                : "Ask once and get two replies side by side: the plain model, and the same model with the harness. A line from code says what it could check.")
            .accessibilityLabel("Compare")
            .accessibilityValue(compare ? "on" : "off")
            Spacer(minLength: 0)
        }
    }

    // MARK: What answers

    @ViewBuilder
    private var answerChips: some View {
        @Bindable var ui = ui
        // Each of the three is chosen here, in a menu of its own. The model and the harness
        // used to lead away to Models and Settings, which lost the place.
        let setup = SetupState(backends)
        // With nothing able to answer yet, the first one says what is missing and leads to the
        // chat page, which has the next step.
        Button {
            if setup == .ready {
                ui.showModelPicker.toggle()
            } else {
                dev.isOn = false
                ui.destination = .chat
            }
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

        harnessChip

        Button { showContext.toggle() } label: {
            chip("text.alignleft", "\(Format.tokens(backends.effectiveContext)) context")
        }
        .buttonStyle(.soft)
        .help("How much text the model keeps in view. More takes more memory.")
        .popover(isPresented: $showContext, arrowEdge: .top) {
            ContextPopover { showContext = false }
        }
    }

    /// The harness for what is about to start: the chat's, or with Dev on the agent's. With Compare on the
    /// task is done both ways, so there is nothing to choose.
    @ViewBuilder
    private var harnessChip: some View {
        if compare {
            chip("checkmark.shield", "Harness off and on", tinted: true, menu: false)
                .opacity(0.7)
                .help("Compare does the task both ways")
        } else if dev.isOn {
            Button { dev.harnessOn.toggle() } label: {
                chip(dev.harnessOn ? "checkmark.shield" : "shield.slash", dev.harnessOn ? "Harness on" : "Harness off", tinted: dev.harnessOn, menu: false)
            }
            .buttonStyle(.soft)
            .disabled(dev.isBusy)
            .help(dev.harnessOn ? "The agent plans, writes each file, runs the result and fixes what fails. Click for the plain model instead."
                                : "One reply from the model, saved as it came, with nothing run or checked. Click to turn the agent's harness on.")
        } else {
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
        }
    }

    private var sendHelp: String {
        if dev.isOn {
            if compare { return "Build this twice, harness off and on, and show both" }
            return dev.project == nil ? "Name a project folder, then the agent starts on this" : "The agent starts on this in \(dev.project?.name ?? "the project")"
        }
        return compare ? "Ask the plain model and the harness, side by side, in a new chat" : "Start this task in a new chat"
    }

    // MARK: Parts

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

    /// A chip that is on or off. The small switch at its end is what tells it from a menu.
    private func toggleChip(_ symbol: String, _ title: String, on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
            Text(title).font(.uiCallout.weight(on ? .semibold : .regular)).lineLimit(1)
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule(style: .circular).fill(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.white.opacity(0.2)))
                Circle().fill(on ? Palette.onAccent : Color.white.opacity(0.85)).padding(2)
            }
            .frame(width: 22, height: 13)
        }
        .foregroundStyle(on ? Palette.accent : Forge.ink)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(on ? Palette.accent.opacity(0.15) : Color.white.opacity(0.07), in: shape)
        .overlay(shape.strokeBorder(on ? Palette.accent.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
        .hoverFill(shape, when: !on)
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

    private static func short(_ name: String) -> String {
        name.count <= 24 ? name : "\(name.prefix(11))…\(name.suffix(11))"
    }

    private func send() {
        guard canSend else { return }
        if HomeTask.start(ui.homeDraft, compare: compare, ui: ui, chat: chat, dev: dev) { ui.homeDraft = "" }
    }
}

/// Starting the work from Home's box. It happens on the Chat page: a new chat, or with Dev on the agent in
/// its project. Kept out of the view so a scripted run can start a task the same way a click does.
@MainActor
enum HomeTask {
    /// False when nothing was started: no project folder was named, or the agent isn't free.
    @discardableResult
    static func start(_ text: String, compare: Bool, ui: UIState, chat: ChatController, dev: DevSession) -> Bool {
        guard dev.isOn else {
            ui.destination = .chat
            chat.newConversation()
            chat.send(text, sideBySide: compare)
            return true
        }
        if compare {
            guard dev.canCompare else { return false }
            ui.destination = .chat
            dev.compare(text)
            return true
        }
        // The agent works in a folder. With none chosen yet, this is where one gets its name.
        if dev.project == nil { dev.newProject() }
        guard dev.project != nil, dev.canSend else { return false }
        dev.showsCompare = false
        ui.destination = .chat
        dev.send(text)
        return true
    }
}
