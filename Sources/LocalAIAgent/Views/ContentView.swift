import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var ui = ui

        Group {
            if settings.draftLayout {
                DraftShell()
            } else {
                classicLayout
            }
        }
        .sheet(isPresented: $ui.showLibrary) {
            ModelLibraryView()
                .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 760)
                .tint(Palette.accent)
        }
        .tint(Palette.accent)
        #if DEBUG
        .task { await debugWidgetHooks() }
        #endif
    }

    private var classicLayout: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            Group {
                switch ui.destination {
                case .chat: ChatView()
                case .modelTest: ModelTestDashboard()
                case .hardwareTest: HardwareTestDashboard()
                case .harnessTest: HarnessTestDashboard()
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
    }

    #if DEBUG
    private func debugWidgetHooks() async {
        if ProcessInfo.processInfo.environment["LOCALAI_OPEN_WIDGETS"] != nil {
            for kind in TelemetryWidgetKind.allCases { openWindow(id: kind.windowID) }
        }
        // Closes both widgets after 3 s, then reopens Generation after 6 s.
        if ProcessInfo.processInfo.environment["LOCALAI_WIDGET_CYCLE"] != nil {
            try? await Task.sleep(for: .seconds(3))
            for window in NSApp.windows where window.identifier?.rawValue.contains("widget") == true {
                window.performClose(nil)
                window.close()
            }
            try? await Task.sleep(for: .seconds(3))
            TelemetryWidgetToggle(open: openWindow, dismiss: dismissWindow, ui: ui)(.generation)
        }
    }
    #endif

    private var title: String {
        switch ui.destination {
        case .chat: return chat.selected?.title ?? Brand.name
        case .modelTest: return "Model Test"
        case .hardwareTest: return "Hardware Test"
        case .harnessTest: return "Harness Test"
        }
    }
}
