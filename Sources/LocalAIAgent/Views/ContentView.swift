import SwiftUI

struct ContentView: View {
    var body: some View {
        ForgeShell()
            .tint(Palette.accent)
    }
}

/// What the main area shows: the page, the chats at its left on the Chat page, and the telemetry
/// panel at its right.
struct MainPage: View {
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            if ui.destination == .chat && settings.chatsOpen {
                HStack(spacing: 0) {
                    ChatsColumn()
                    Forge.rule(vertical: true)
                }
                .transition(.move(edge: .leading))
            }
            Group {
                switch ui.destination {
                case .home: HomePage()
                case .chat: ChatView()
                case .tests: TestsPage()
                case .library: ModelLibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Home has its own Active Model card.
            if settings.telemetryOpen && ui.destination != .home {
                TelemetryPanel().transition(.move(edge: .trailing))
            }
        }
    }
}
