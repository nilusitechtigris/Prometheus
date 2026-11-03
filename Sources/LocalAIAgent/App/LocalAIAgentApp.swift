import AppKit
import SwiftUI

/// Transient UI state shared between the window, menus and keyboard shortcuts.
@MainActor
@Observable
final class UIState {
    var showLibrary = false
    var showModelPicker = false
    var composerFocusRequest = 0
    var draft = ""
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also behave like a regular app when launched straight from `swift run`.
        NSApp.setActivationPolicy(.regular)
        #if DEBUG
        // Automated snapshot runs shouldn't steal focus from whatever the user is doing.
        if ProcessInfo.processInfo.environment["LOCALAI_NO_ACTIVATE"] != nil { return }
        #endif
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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

    init() {
        let settings = AppSettings()
        let backends = BackendController(settings: settings)
        let chat = ChatController(settings: settings, backends: backends)
        _settings = State(initialValue: settings)
        _backends = State(initialValue: backends)
        _chat = State(initialValue: chat)
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
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    backends.start()
                    monitor.start()
                    #if DEBUG
                    DebugHooks.install(chat: chat, ui: ui)
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
                Button(settings.showInspector ? "Hide Telemetry" : "Show Telemetry") {
                    settings.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(backends)
                .environment(chat)
        }
    }
}
