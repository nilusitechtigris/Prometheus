import SwiftUI

/// The foot of the window, one line on every page: the dock of pages in the middle, and this Mac's
/// readout at the right, which opens Telemetry from wherever you are.
struct ForgeFoot: View {
    /// The height of the readout. The dock is a little lower and sits in the middle of it.
    static let cardHeight: CGFloat = 52

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Both sides take the same share of the width, which keeps the dock in the middle of the window.
            // The left one is empty: the last task used to sit there on Home, and the Chat page lists them all.
            Color.clear.frame(height: Self.cardHeight).frame(maxWidth: .infinity)
            ForgeDock().fixedSize()
            HardwareReadout().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Dock

/// The pages, in a row.
private struct ForgeDock: View {
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    /// So the highlight slides from one item to the next.
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            item("house", "Home", selected: ui.destination == .home) { ui.destination = .home }
                .help("Start something new (⌘1)")
            // The Chat page as it was left: Ask or Dev (ChatModeSwitch), the list of chats shown or hidden.
            // It used to open the list every time, which was the only way to get a hidden list back.
            item("bubble.left.and.bubble.right", "Chat", selected: ui.destination == .chat) { ui.destination = .chat }
                .help("Your chats, and Dev (⌘2)")
            item("cube", "Models", selected: ui.destination == .library) { ui.destination = .library }
            item("checklist", "Tests", selected: ui.destination == .tests, busy: lab.isRunning) { ui.destination = .tests }
            item("gearshape", "Settings", selected: ui.destination == .settings) { ui.destination = .settings }
        }
        .padding(5)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.edge, lineWidth: 1))
        .animation(Motion.page, value: ui.destination)
    }

    private func item(_ symbol: String, _ title: String, selected: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = Capsule(style: .circular)
        return Button(action: action) {
            HStack(spacing: 7) {
                // Every symbol gets the same box, so the titles start at the same distance from them.
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
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
            .background(Forge.card, in: shape)
            .overlay(shape.strokeBorder(open ? Palette.accent.opacity(0.7) : Forge.edge, lineWidth: 1))
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
