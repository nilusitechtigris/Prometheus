import SwiftUI

struct ContentView: View {
    var body: some View {
        ForgeShell()
            .tint(Palette.accent)
        .font(.uiCallout)
        .buttonStyle(PixelButtonStyle())
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
                case .chat: ChatView()
                case .tests: TestsPage()
                case .library: ModelLibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if settings.telemetryOpen {
                TelemetryPanel().transition(.move(edge: .trailing))
            }
        }
    }
}
