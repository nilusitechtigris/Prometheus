import AppKit
import SwiftUI

/// Transient UI state shared between the window, menus and keyboard shortcuts.
@MainActor
@Observable
final class UIState {
    /// What the main area shows: the selected chat or one of the test dashboards.
    enum Destination: Hashable { case chat, modelTest, hardwareTest, harnessTest }

    var destination: Destination = .chat
    /// Telemetry widget windows currently on screen.
    var openWidgets: Set<TelemetryWidgetKind> = []
    var showLibrary = false
    var showModelPicker = false
    var showTestModelPicker = false
    var composerFocusRequest = 0
    var draft = ""
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onTerminate: (() -> Void)?
    /// True while something is running that quitting would throw away.
    static var isBusy: (() -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also behave like a regular app when launched straight from `swift run`.
        NSApp.setActivationPolicy(.regular)
        // The floating widgets count as windows, so closing the main window has to quit explicitly.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard Self.isMainWindow(note.object as? NSWindow) else { return }
            MainActor.assumeIsolated { Self.quitWhenIdle() }
        }
        #if DEBUG
        // Automated snapshot runs shouldn't steal focus from whatever the user is doing.
        if ProcessInfo.processInfo.environment["LOCALAI_NO_ACTIVATE"] != nil { return }
        #endif
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func isMainWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.hasPrefix("main") == true
    }

    /// Quits once any running test has finished, unless the main window has been reopened by then.
    @MainActor private static func quitWhenIdle() {
        Task {
            repeat {
                try? await Task.sleep(for: .milliseconds(200))
            } while isBusy?() == true
            guard !NSApp.windows.contains(where: { isMainWindow($0) && $0.isVisible }) else { return }
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.onTerminate?()
    }
}

@main
struct LocalAIAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var backends: BackendController
    @State private var chat: ChatController
    @State private var monitor = SystemMonitor()
    @State private var ui = UIState()
    @State private var lab: TestLab

    init() {
        AppFonts.register()
        let settings = AppSettings()
        let backends = BackendController(settings: settings)
        let chat = ChatController(settings: settings, backends: backends)
        let lab = TestLab()
        _settings = State(initialValue: settings)
        _backends = State(initialValue: backends)
        _chat = State(initialValue: chat)
        _lab = State(initialValue: lab)
        AppDelegate.isBusy = { MainActor.assumeIsolated { lab.isRunning } }
        AppDelegate.onTerminate = { MainActor.assumeIsolated { chat.saveNow() } }
    }

    var body: some Scene {
        WindowGroup(Brand.name, id: "main") {
            ContentView()
                .environment(settings)
                .environment(backends)
                .environment(chat)
                .environment(monitor)
                .environment(ui)
                .environment(lab)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    backends.start()
                    monitor.start()
                    #if DEBUG
                    DebugHooks.install(chat: chat, ui: ui, lab: lab, backends: backends, monitor: monitor, settings: settings)
                    #endif
                }
        }
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.name)") {
                    let centered = NSMutableParagraphStyle()
                    centered.alignment = .center
                    let credits = NSAttributedString(
                        string: "\(Brand.tagline)\nOpen models running on this Mac. Nothing leaves it.",
                        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                     .paragraphStyle: centered])
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: Brand.name, .credits: credits])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    ui.destination = .chat
                    chat.newConversation()
                    ui.composerFocusRequest += 1
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Picker("Theme", selection: Binding(get: { ThemeStore.shared.theme },
                                                   set: { ThemeStore.shared.theme = $0 })) {
                    ForEach(AppTheme.allCases) { Text($0.name).tag($0) }
                }
                Button(settings.draftLayout ? "Use Classic Layout" : "Try Forge Draft") { settings.draftLayout.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Divider()
            }
            CommandMenu("Chat") {
                Button("Stop Generating") { chat.stop() }
                    .keyboardShortcut(".")
                    .disabled(!chat.isGenerating)
                Button("Regenerate Response") { chat.regenerate() }
                    .keyboardShortcut("r")
                    .disabled(!chat.canSend || chat.selected?.messages.isEmpty != false)
                Divider()
                Button("Choose Model…") { ui.showModelPicker = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Model Library…") { ui.showLibrary = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                WidgetMenuItems(ui: ui)
                Divider()
                Button("Model Test Dashboard") { ui.destination = .modelTest }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Hardware Test Dashboard") { ui.destination = .hardwareTest }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Harness Test Dashboard") { ui.destination = .harnessTest }
                    .keyboardShortcut("5", modifiers: [.command, .option])
            }
        }

        widgetWindow(.generation)
        widgetWindow(.hardware)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(backends)
                .environment(chat)
        }
    }

    /// A floating telemetry widget in its own window.
    private func widgetWindow(_ kind: TelemetryWidgetKind) -> some Scene {
        Window(kind.title, id: kind.windowID) {
            FloatingWidgetWindow(kind: kind)
                .environment(settings)
                .environment(backends)
                .environment(chat)
                .environment(monitor)
                .environment(ui)
                .tint(Palette.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: kind.baseWidth, height: kind == .generation ? 300 : 460)
        .defaultPosition(.topTrailing)
    }
}

/// Chat-menu toggles for the floating telemetry widgets (⌥⌘1, ⌥⌘2).
private struct WidgetMenuItems: View {
    let ui: UIState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let toggle = TelemetryWidgetToggle(open: openWindow, dismiss: dismissWindow, ui: ui)
        ForEach(Array(TelemetryWidgetKind.allCases.enumerated()), id: \.element) { index, kind in
            Button("\(ui.openWidgets.contains(kind) ? "Hide" : "Show") \(kind.title) Widget") { toggle(kind) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
        }
    }
}
