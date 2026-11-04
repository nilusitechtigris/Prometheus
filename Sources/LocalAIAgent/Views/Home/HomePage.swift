import SwiftUI

/// The start page: what the app is for, a box to start a task, the model in use and recent work.
/// Every number on it comes from this Mac: if there's nothing to show yet, it says so.
struct HomePage: View {
    @Environment(UIState.self) private var ui
    @Environment(ChatController.self) private var chat

    var body: some View {
        ScrollView {
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
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
    }
}

// MARK: - Hero

private struct HomeHero: View {
    @Environment(UIState.self) private var ui
    @Environment(ChatController.self) private var chat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CrystalArt()
                .frame(width: 430, height: 300)
                .offset(x: 20, y: -10)
            ModePicker()
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
            .padding(.top, 34)
        }
        .frame(height: 256)
    }
}

/// Local mode or harness on, which is the one switch that decides whether anything leaves this Mac.
private struct ModePicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    @State private var open = false

    private var harness: Bool { settings.harnessEnabled && backends.kind.supportsTools }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 7) {
                Circle().fill(harness ? Palette.warning : Palette.good).frame(width: 8, height: 8)
                Text(harness ? "Harness On" : "Local Mode").font(.uiCaption.weight(.medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Forge.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Forge.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Forge.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                choice("Local Mode", "Everything stays on this Mac.", selected: !harness) { settings.harnessEnabled = false }
                choice("Harness On", "Search terms go to Wikipedia, Stack Overflow, arXiv and MDN.", selected: harness) {
                    settings.harnessEnabled = true
                }
                .disabled(!backends.kind.supportsTools)
            }
            .padding(8)
            .frame(width: 290)
        }
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            open = false
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Forge.faint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.uiCallout.weight(.medium))
                    Text(detail).font(.uiCaption).foregroundStyle(Forge.dim).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The glowing crystal on its platform. Drawn once, so it adds no load to the numbers the app measures.
struct CrystalArt: View {
    var body: some View {
        Canvas { context, size in
            let accent = Palette.accent
            let x = size.width * 0.5
            let middle = size.height * 0.42
            func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: middle + dy) }
            func polygon(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                return path
            }

            // Glow behind everything.
            context.fill(Path(ellipseIn: CGRect(x: x - 210, y: middle - 170, width: 420, height: 340)),
                         with: .radialGradient(Gradient(colors: [accent.opacity(0.26), .clear]), center: point(0, 0), startRadius: 0, endRadius: 200))

            // Orbits, with a bright dot on each.
            var orbits = context
            orbits.opacity = 0.55
            for (width, height, tilt) in [(380.0, 120.0, -0.28), (300.0, 92.0, 0.2)] {
                var orbit = context
                orbit.translateBy(x: x, y: middle + 30)
                orbit.rotate(by: .radians(tilt))
                orbit.stroke(Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)),
                             with: .color(accent.opacity(0.3)), lineWidth: 0.8)
            }
            for spot in [point(-140, -36), point(150, -82)] {
                var dot = context
                dot.addFilter(.shadow(color: accent, radius: 7))
                dot.fill(Path(ellipseIn: CGRect(x: spot.x - 4, y: spot.y - 4, width: 8, height: 8)), with: .color(accent))
            }

            // The platform.
            let floor = middle + 118
            for (index, width) in [340.0, 262.0, 190.0].enumerated() {
                let height = width * 0.17
                context.stroke(Path(ellipseIn: CGRect(x: x - width / 2, y: floor - height / 2 + 8, width: width, height: height)),
                               with: .color(accent.opacity(0.14 + Double(index) * 0.1)), lineWidth: 1)
            }
            context.fill(Path(ellipseIn: CGRect(x: x - 70, y: floor - 10, width: 140, height: 26)), with: .color(Color(white: 0.02)))
            context.stroke(Path(ellipseIn: CGRect(x: x - 70, y: floor - 10, width: 140, height: 26)), with: .color(accent.opacity(0.6)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: x - 34, y: floor - 3, width: 68, height: 12)),
                         with: .radialGradient(Gradient(colors: [accent, .clear]), center: CGPoint(x: x, y: floor + 3), startRadius: 0, endRadius: 34))

            // The crystal, with light coming up from its point.
            let top = point(0, -112), left = point(-68, -8), right = point(68, -8), front = point(6, 8), bottom = point(0, 112)
            let beam = polygon([point(-3, 100), point(3, 100), CGPoint(x: x + 8, y: floor + 3), CGPoint(x: x - 8, y: floor + 3)])
            context.fill(beam, with: .linearGradient(Gradient(colors: [accent.opacity(0.9), accent.opacity(0.2)]), startPoint: point(0, 100), endPoint: CGPoint(x: x, y: floor)))
            var crystal = context
            crystal.addFilter(.shadow(color: accent.opacity(0.75), radius: 26))
            crystal.fill(polygon([top, left, bottom, right]), with: .color(accent.opacity(0.25)))
            context.fill(polygon([top, left, front]), with: .linearGradient(Gradient(colors: [Color(red: 0.88, green: 1, blue: 0.5), Color(red: 0.46, green: 0.66, blue: 0.1)]), startPoint: top, endPoint: left))
            context.fill(polygon([top, front, right]), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.83, blue: 0.2), Color(red: 0.2, green: 0.33, blue: 0.04)]), startPoint: top, endPoint: right))
            context.fill(polygon([left, front, bottom]), with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.45, blue: 0.07), Color(red: 0.8, green: 1, blue: 0.3)]), startPoint: left, endPoint: bottom))
            context.fill(polygon([front, right, bottom]), with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.26, blue: 0.03), Color(red: 0.72, green: 0.95, blue: 0.22)]), startPoint: right, endPoint: bottom))
            var edges = Path()
            edges.addLines([top, left, bottom, right, top])
            edges.addLines([left, front, right])
            edges.addLines([top, front, bottom])
            context.stroke(edges, with: .color(Color(red: 0.9, green: 1, blue: 0.6).opacity(0.5)), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
