import SwiftUI

struct ContentView: View {
    var body: some View {
        ForgeShell()
            .tint(Palette.accent)
    }
}

/// What the main area shows: one page at a time.
struct MainPage: View {
    @Environment(UIState.self) private var ui
    @Environment(DevSession.self) private var dev

    /// The page on show. Chat counts as two, so flipping its switch swaps pages like any other move.
    private struct Shown: Hashable {
        let destination: UIState.Destination
        let dev: Bool
    }

    var body: some View {
        PageSwap(value: Shown(destination: ui.destination, dev: ui.showsDev(dev))) {
            switch ui.destination {
            case .home: HomePage()
            case .chat:
                if dev.isOn { DevWorkspaceView() } else { ChatPage() }
            case .tests: TestsPage()
            case .library: ModelLibraryView()
            case .settings: SettingsView()
            case .telemetry: TelemetryPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // The Chat page's switch between Ask and Dev, drawn over both so it doesn't move when it's flipped.
            // One side of a comparison filling the window takes this corner too.
            if ui.destination == .chat, !(dev.isOn && dev.compareFillsWindow) {
                ChatModeSwitch()
                    .padding(.leading, ChatModeSwitch.barInset)
                    .padding(.top, (ChatModeSwitch.barHeight - Forge.pillHeight) / 2)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // The message box shows the question in a chat. Anywhere else it would wait unseen.
            if let request = WebConsent.shared.pending, ui.destination != .chat || dev.isOn {
                WebConsentCard(request: request)
                    .frame(maxWidth: 860)
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.quick, value: WebConsent.shared.pending)
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.page, value: dev.isOn)
        .animation(Motion.quick, value: dev.compareFillsWindow)
    }
}
