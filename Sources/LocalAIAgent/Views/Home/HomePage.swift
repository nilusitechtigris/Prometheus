import SwiftUI

/// The start page: what the app is for, a box to start a task, the model in use and recent work.
/// Every number on it comes from this Mac: if there's nothing to show yet, it says so.
struct HomePage: View {
    @Environment(UIState.self) private var ui
    @Environment(ChatController.self) private var chat

    var body: some View {
        ScrollView {
            ZStack(alignment: .topTrailing) {
                heroPicture
                content
            }
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
    }

    /// The crystal, fading out to the left and at the foot so it melts into the page.
    @ViewBuilder
    private var heroPicture: some View {
        if let picture = Art.homeHero {
            Image(nsImage: picture)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(width: 800)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.36)],
                                     startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                HomeHero()
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        TaskBuilder()
                        RecentTasks()
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    VStack(spacing: 16) {
                        ActiveModelCard()
                        ProTip()
                    }
                    .frame(width: 270)
                }
            }
            .padding(24)
    }
}

// MARK: - Hero

private struct HomeHero: View {
    @Environment(UIState.self) private var ui
    @Environment(ChatController.self) private var chat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Small models.\n").foregroundStyle(Forge.ink) + Text("Serious work.").foregroundStyle(Palette.accent))
                .font(.geist(46, weight: .semibold))
                .lineSpacing(0)
            Text("Turn lightweight LLMs into focused, reliable task executors.")
                .font(.geist(16))
                .foregroundStyle(Forge.dim)
            HStack(spacing: 12) {
                Button {
                    ui.destination = .chat
                    chat.newConversation()
                    ui.composerFocusRequest += 1
                } label: {
                    Label("Start a New Task", systemImage: "play.fill")
                }
                .buttonStyle(AccentButtonStyle())
                Button {
                    ui.destination = .library
                } label: {
                    HStack(spacing: 8) {
                        Text("Browse Models")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 48)
        .frame(height: 334, alignment: .top)
    }
}

// MARK: - Task builder

private struct TaskBuilder: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @State private var task = ""
    @State private var showOptions = false
    @FocusState private var focused: Bool

    private let templates: [(symbol: String, title: String, starter: String)] = [
        ("doc.text", "Summarize", "Summarize this in 3 key points:\n\n"),
        ("tablecells", "Extract Data", "Extract the names, dates and amounts from this as a table:\n\n"),
        ("chart.bar", "Analyze Content", "Analyze this and tell me what matters most:\n\n"),
        ("wand.and.stars", "Build Assistant", "Act as an assistant that helps me with "),
    ]

    private var canSend: Bool { chat.canSend && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        PanelWidget(title: "Task Builder", symbol: "bolt.fill") {
            Button { showOptions.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Advanced")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.uiCaption)
                .foregroundStyle(Forge.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Forge.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Temperature, response length and system instructions")
            .popover(isPresented: $showOptions, arrowEdge: .bottom) { GenerationOptionsView().environment(settings) }
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text("What do you want to accomplish?").font(.geist(19, weight: .medium))
                Text("Describe your goal, or choose a template.").font(.uiCallout).foregroundStyle(Forge.dim)
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                TextField("e.g. Summarize this document in 3 key points…", text: $task, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.uiBody)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .opacity(canSend ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Start this task in a new chat")
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.6) : Forge.line, lineWidth: 1))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { chips }
            }
        }
    }

    private var chips: some View {
        ForEach(templates, id: \.title) { template in
            Button {
                task = template.starter
                focused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: template.symbol).foregroundStyle(Forge.dim)
                    Text(template.title).lineLimit(1).fixedSize()
                }
                .font(.uiCaption)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Forge.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Start from this template")
        }
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

// MARK: - Recent tasks

private struct RecentTasks: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui

    private var recent: [Conversation] { Array(chat.conversations.filter { !$0.messages.isEmpty }.prefix(3)) }

    var body: some View {
        PanelWidget(title: "Your Recent Tasks", symbol: "clock.arrow.circlepath") {
            Button {
                ui.destination = .chat
            } label: {
                HStack(spacing: 5) {
                    Text("View All")
                    Image(systemName: "arrow.right")
                }
                .font(.uiCaption)
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        } content: {
            if recent.isEmpty {
                Text("Tasks you start will show here.").font(.uiCallout).foregroundStyle(Forge.dim)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, conversation in
                        card(conversation, index: index)
                    }
                    ForEach(recent.count..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }

    private func card(_ conversation: Conversation, index: Int) -> some View {
        let running = conversation.messages.last?.id == chat.streamingMessageID && chat.streamingMessageID != nil
        let bars = [Palette.accent, Color(red: 0.49, green: 0.3, blue: 0.95), Color(red: 0.2, green: 0.5, blue: 0.95)]
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            chat.selectedID = conversation.id
            ui.destination = .chat
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title).font(.uiCallout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        if running {
                            ProgressView().controlSize(.mini)
                            Text("Running…")
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
                            Text("Completed · \(TestFormat.relative(conversation.updatedAt))").lineLimit(1)
                        }
                    }
                    .font(.uiCaption2)
                    .foregroundStyle(Forge.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Forge.faint)
            }
            .padding(.leading, 15)
            .padding(.trailing, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: shape)
            .overlay(alignment: .leading) { bars[index % bars.count].frame(width: 3).padding(.vertical, 8) }
            .overlay(shape.strokeBorder(Forge.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active model

private struct ActiveModelCard: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ChatController.self) private var chat
    @Environment(TestLab.self) private var lab
    @Environment(UIState.self) private var ui

    var body: some View {
        PanelWidget(title: "Active Model", symbol: "cpu") {
            EmptyView()
        } content: {
            if let model = backends.selectedModel {
                HStack(spacing: 12) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 66, height: 66)
                        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.displayName).font(.geist(15, weight: .medium)).lineLimit(2)
                        Text(subtitle(model)).font(.uiCaption).foregroundStyle(Forge.dim).lineLimit(1)
                        fit(model)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("No model chosen yet.").font(.uiCallout).foregroundStyle(Forge.dim)
            }
            Button {
                ui.destination = .library
            } label: {
                HStack(spacing: 6) {
                    Text("Change Model")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle())
            performance
        }
    }

    private func subtitle(_ model: LocalModel) -> String {
        guard let catalog = model.catalog else { return model.quantLabel }
        return "\(catalog.parameters) · \(catalog.publisher)"
    }

    @ViewBuilder
    private func fit(_ model: LocalModel) -> some View {
        if let bytes = backends.memoryEstimate(for: model, context: backends.estimatedContext(for: model)) {
            let verdict = MemoryFit.verdict(requiredBytes: bytes, budget: monitor.gpuBudgetBytes)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(verdict.label)
            }
            .font(.uiCaption2.weight(.medium))
            .foregroundStyle(verdict.level.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(verdict.level.color.opacity(0.13), in: Capsule())
        }
    }

    private var performance: some View {
        let average = chat.averages(for: backends.selectedModel?.id)
        let test = lab.latestModelResult(for: backends.selectedModel?.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar").foregroundStyle(Palette.accent)
                Text("Performance").font(.uiCallout.weight(.medium))
                Spacer()
                Text("GPU load, live").font(.uiCaption2).foregroundStyle(Forge.dim)
            }
            Sparkline(points: monitor.gpu.points, color: Palette.accent, domain: 0...100, height: 36)
            HStack(alignment: .top) {
                stat(average.flatMap(\.timeToFirstToken).map(Format.seconds) ?? "—", "First token, this chat")
                Spacer()
                stat(test.map { "\(TestFormat.score($0.score))/100" } ?? "—", "Test score")
            }
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.geist(18, weight: .medium)).monospacedDigit()
            Text(title).font(.uiCaption2).foregroundStyle(Forge.dim)
        }
    }
}

private struct ProTip: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        PanelWidget(title: "Pro Tip", symbol: "lightbulb") {
            EmptyView()
        } content: {
            Text("Turn on the harness for the best results with small models.")
                .font(.uiCaption)
                .foregroundStyle(Forge.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                ui.openTests(.harness)
            } label: {
                HStack(spacing: 5) {
                    Text("Learn More")
                    Image(systemName: "arrow.right")
                }
                .font(.uiCaption)
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
    }
}
