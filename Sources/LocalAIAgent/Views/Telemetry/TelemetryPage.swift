import SwiftUI

/// Live hardware telemetry, as a page of its own. The readout at the foot of the window opens it from any
/// page, and Back returns to the page it was opened from, as that page was left.
struct TelemetryPage: View {
    @Environment(UIState.self) private var ui
    @Environment(DevSession.self) private var dev

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                back
                HardwareWidget()
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var back: some View {
        let shape = Capsule(style: .circular)
        return Button { ui.toggleTelemetry() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Back to \(cameFrom)").font(.uiCallout)
            }
            .foregroundStyle(Forge.ink)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Forge.card, in: shape)
            .overlay(shape.strokeBorder(Forge.line, lineWidth: 1))
            .hoverFill(shape)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        // Esc goes back too.
        .keyboardShortcut(.cancelAction)
        .help("Back to where you were (Esc or ⌥⌘1)")
    }

    /// The page Back leads to, by the name the menus give it.
    private var cameFrom: String {
        switch ui.beforeTelemetry {
        case .home, .telemetry: return "Home"
        case .chat: return dev.isOn ? "Dev" : "Chat"
        case .tests: return "Tests"
        case .library: return "Models"
        case .settings: return "Settings"
        }
    }
}
