import SwiftUI

/// The foot of the window, one line on every page: the last task at the left (on Home), the dock of pages
/// in the middle, and this Mac's readout at the right, which opens Telemetry from wherever you are.
struct ForgeFoot: View {
    @Environment(UIState.self) private var ui

    /// The height of the cards at either side. The dock is a little lower and sits in the middle of it.
    static let cardHeight: CGFloat = 52

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Both sides take the same share of the width, which keeps the dock in the middle of the window.
            ZStack(alignment: .leading) {
                Color.clear.frame(height: Self.cardHeight)
                if ui.destination == .home {
                    LastTask().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForgeDock().fixedSize()
            HardwareReadout().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .animation(Motion.page, value: ui.destination)
    }
}

// MARK: - Dock

/// The pages, in a row.
private struct ForgeDock: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @Environment(DevSession.self) private var dev
    /// So the highlight slides from one item to the next.
    @Namespace private var highlight

    private var inChat: Bool { ui.destination == .chat }

    var body: some View {
        HStack(spacing: 4) {
            item("sparkle", "Ask", selected: ui.destination == .home) { ui.destination = .home }
                .help("Start a task")
            // Always the chats, with the list showing. It used to fold the list away on a second click,
            // and to show Dev mode when that had been left on.
            item("clock.arrow.circlepath", "History", selected: inChat && !dev.isOn) {
                dev.isOn = false
                settings.chatsOpen = true
                ui.destination = .chat
            }
            .help("Your chats (⌥⌘2 folds the list away)")
            item("chevron.left.forwardslash.chevron.right", "Dev", selected: inChat && dev.isOn) {
                dev.isOn = true
                ui.destination = .chat
            }
            .help("Dev mode: the agent writes code in a project folder and runs it")
            item("cube", "Models", selected: ui.destination == .library) { ui.destination = .library }
            item("checklist", "Tests", selected: ui.destination == .tests, busy: lab.isRunning) { ui.destination = .tests }
            item("gearshape.fill", "Settings", selected: ui.destination == .settings) { ui.destination = .settings }
        }
        .padding(5)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.page, value: dev.isOn)
    }

    private func item(_ symbol: String, _ title: String, selected: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = Capsule(style: .circular)
        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.uiCallout.weight(selected ? .semibold : .regular))
                if busy { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(selected ? Palette.onAccent : Forge.ink)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background {
                if selected { shape.fill(Palette.gradient).matchedGeometryEffect(id: "page", in: highlight) }
            }
            // A page that isn't open shows where a click would land.
            .hoverFill(shape, when: !selected)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Last task

/// The newest chat that has something in it, and how it ended. A click opens it.
private struct LastTask: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui

    var body: some View {
        if let conversation = chat.conversations.first(where: { !$0.messages.isEmpty }) {
            card(conversation)
        }
    }

    private func card(_ conversation: Conversation) -> some View {
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
            // As wide as its side of the dock allows, in a narrow window.
            .frame(maxWidth: 300)
            .frame(height: ForgeFoot.cardHeight)
            .background(Forge.card.opacity(0.9), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .hoverFill(shape)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .help("Open your last task")
    }
}

// MARK: - Readout

/// This Mac in three numbers, on every page. A click opens Telemetry, and a click there goes back to the
/// page it was opened from.
private struct HardwareReadout: View {
    @Environment(UIState.self) private var ui
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let open = ui.destination == .telemetry
        Button { ui.toggleTelemetry() } label: {
            HStack(spacing: 20) {
                stat("GPU", monitor.gpu.points.last.map { String(format: "%.0f%%", $0.value) } ?? "—")
                stat("Memory", monitor.snapshot.memoryPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                stat("Thermal", thermal)
                Image(systemName: open ? "xmark" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(open ? Palette.accent : Forge.faint)
                    .frame(width: 10)
            }
            .padding(.horizontal, 16)
            .frame(height: ForgeFoot.cardHeight)
            .background(Forge.card.opacity(0.9), in: shape)
            .overlay(shape.strokeBorder(open ? Palette.accent.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1))
            .hoverFill(shape)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .fixedSize()
        .help(open ? "Close Telemetry and go back (⌥⌘1)" : "Open Telemetry: load and temperature of the GPU, memory and CPU (⌥⌘1)")
        .accessibilityElement(children: .combine)
        .accessibilityHint(open ? "Closes Telemetry" : "Opens Telemetry")
        .accessibilityAddTraits(open ? .isSelected : [])
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
