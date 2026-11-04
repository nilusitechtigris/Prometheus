import SwiftUI

struct ContentView: View {
    var body: some View {
        ForgeShell()
            .tint(Palette.accent)
    }
}

/// What the main area shows: the page, the chats at its left on the Chat page, and the telemetry
/// panel along the bottom.
struct MainPage: View {
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings

    /// Telemetry belongs to the Chat page, where the model is working.
    private var showsTelemetry: Bool { settings.telemetryOpen && ui.destination == .chat }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if ui.destination == .chat && settings.chatsOpen {
                    HStack(spacing: 0) {
                        ChatsColumn()
                        Forge.rule(vertical: true)
                    }
                    .transition(.move(edge: .leading))
                }
                PageSwap(value: ui.destination) {
                    switch ui.destination {
                    case .home: HomePage()
                    case .chat: ChatView()
                    case .tests: TestsPage()
                    case .library: ModelLibraryView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showsTelemetry {
                TelemetryPanel().transition(.move(edge: .bottom))
            }
        }
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.quick, value: settings.chatsOpen)
        .animation(Motion.quick, value: settings.telemetryOpen)
    }
}
