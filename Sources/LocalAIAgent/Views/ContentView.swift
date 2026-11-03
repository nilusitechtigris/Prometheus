import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var ui = ui

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            Group {
                switch ui.destination {
                case .chat: ChatView()
                case .modelTest: ModelTestDashboard()
                case .hardwareTest: HardwareTestDashboard()
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(backends.selectedModel.map { "\($0.displayName) · \($0.quantLabel) · \(backends.kind.displayName)" } ?? backends.kind.displayName)
        .toolbar {
            // Compact vitals only while the full telemetry panel is closed.
            if !ui.openWidgets.contains(.hardware) {
                ToolbarItem(placement: .primaryAction) { VitalsStrip() }
            }
        }
        .sheet(isPresented: $ui.showLibrary) {
            ModelLibraryView()
                .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 760)
                .tint(Palette.accent)
        }
        .tint(Palette.accent)
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["LOCALAI_OPEN_WIDGETS"] != nil {
                for kind in TelemetryWidgetKind.allCases { openWindow(id: kind.windowID) }
            }
        }
        #endif
    }

    private var title: String {
        switch ui.destination {
        case .chat: return chat.selected?.title ?? Brand.name
        case .modelTest: return "Model Test"
        case .hardwareTest: return "Hardware Test"
        }
    }
}
