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

    var body: some View {
        HStack(spacing: 0) {
            if ui.destination == .chat && settings.chatsOpen && !dev.isOn {
                HStack(spacing: 0) {
                    ChatsColumn()
                    Forge.rule(vertical: true)
                }
                .transition(.move(edge: .leading))
            }
            PageSwap(value: ui.destination) {
                switch ui.destination {
                case .home: HomePage()
                case .chat:
                    if dev.isOn { DevWorkspaceView() } else { ChatView() }
                case .tests: TestsPage()
                case .library: ModelLibraryView()
                case .settings: SettingsView()
                case .telemetry: TelemetryPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            // The message box shows the question on the Chat page. Anywhere else it would wait unseen.
            if let request = WebConsent.shared.pending, ui.destination != .chat || dev.isOn {
                WebConsentCard(request: request)
                    .frame(maxWidth: 860)
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.quick, value: WebConsent.shared.pending)
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.quick, value: settings.chatsOpen)
        .animation(Motion.quick, value: dev.isOn)
    }
}
