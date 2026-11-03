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
                }
        }
        .navigationTitle(chat.selected?.title ?? "Local AI Agent")
        .navigationSubtitle(backends.selectedModel.map { "\($0.displayName) · \(backends.kind.displayName)" } ?? backends.kind.displayName)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                ControlBar()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                VitalsStrip()
                Button {
                    ui.showLibrary = true
                } label: {
                    Label("Model Library", systemImage: "square.stack.3d.down.right")
                }
                .help("Browse and download verified models (⇧⌘L)")
                Button {
                    withAnimation(.snappy) { settings.showInspector.toggle() }
                } label: {
                    Label("Observability", systemImage: "gauge.with.dots.needle.67percent")
                }
                .help("Show or hide observability (⌥⌘I)")
            }
        }
        .sheet(isPresented: $ui.showLibrary) {
            ModelLibraryView()
                .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 760)
        }
    }
}
