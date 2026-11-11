import SwiftUI

struct ContentView: View {
    var body: some View {
        ForgeShell()
            .tint(Palette.accent)
    }
}

/// What the main area shows: the page, and the chats at its left on the Chat page.
struct MainPage: View {
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @Environment(DevSession.self) private var dev

    /// The page on show. Home counts as two, so flipping its switch swaps pages like any other move.
    private struct Shown: Hashable {
        let destination: UIState.Destination
        let dev: Bool
    }

    var body: some View {
        let showsDev = ui.showsDev(dev)
        HStack(spacing: 0) {
            if ui.destination == .chat && settings.chatsOpen {
                HStack(spacing: 0) {
                    ChatsColumn()
                    Forge.rule(vertical: true)
                }
                .transition(.move(edge: .leading))
            }
            PageSwap(value: Shown(destination: ui.destination, dev: showsDev)) {
                switch ui.destination {
                case .home:
                    if dev.isOn { DevWorkspaceView() } else { HomePage() }
                case .chat: ChatView()
                case .tests: TestsPage()
                case .library: ModelLibraryView()
                case .settings: SettingsView()
                case .telemetry: TelemetryPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            // Home's switch between Ask and Dev, drawn over both so it doesn't move when it's flipped.
            // One side of a comparison filling the window takes this corner too.
            if ui.destination == .home, !(dev.isOn && dev.compareFillsWindow) {
                HomeModeSwitch()
                    .padding(.leading, HomeModeSwitch.barInset)
                    .padding(.top, (HomeModeSwitch.barHeight - Forge.pillHeight) / 2)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // The message box shows the question on the Chat page. Anywhere else it would wait unseen.
            if let request = WebConsent.shared.pending, ui.destination != .chat {
                WebConsentCard(request: request)
                    .frame(maxWidth: 860)
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.quick, value: WebConsent.shared.pending)
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.quick, value: settings.chatsOpen)
        .animation(Motion.page, value: dev.isOn)
        .animation(Motion.quick, value: dev.compareFillsWindow)
    }
}
