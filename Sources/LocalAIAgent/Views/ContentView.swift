import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var settings = settings
        @Bindable var ui = ui

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            ChatView()
                .inspector(isPresented: $settings.showInspector) {
                    ObservabilityPanel()
                        .inspectorColumnWidth(min: 320, ideal: 360, max: 460)
                        // Inspector toolbar items stay visible even when it's collapsed, so this one
                        // button sits at the far right of the window in both states.
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) { TelemetryButton() }
                        }
                }
        }
        .navigationTitle(chat.selected?.title ?? "Local AI Agent")
        .navigationSubtitle(backends.selectedModel.map { "\($0.displayName) · \($0.quantLabel) · \(backends.kind.displayName)" } ?? backends.kind.displayName)
        .toolbar {
            // Compact vitals only while the full telemetry panel is closed.
            if !settings.showInspector {
                ToolbarItem(placement: .primaryAction) { VitalsStrip() }
            }
        }
        .sheet(isPresented: $ui.showLibrary) {
            ModelLibraryView()
                .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 760)
                .tint(Palette.accent)
        }
        .tint(Palette.accent)
    }
}
