import AppKit
import SwiftUI

/// Transient UI state shared between the window, menus and keyboard shortcuts.
@MainActor
@Observable
final class UIState {
    /// What the main area shows.
    enum Destination: Hashable { case chat, tests, library }

    var destination: Destination = .chat
    /// Which results the Tests page shows.
    var testTab: TestTab = .model
    var showModelPicker = false
    var showTestModelPicker = false
    var composerFocusRequest = 0
    var draft = ""
    var chatSearch = ""
    /// Set to move the keyboard to the chat search, and cleared once it has.
    var wantsChatSearchFocus = false

    func openTests(_ tab: TestTab) {
        testTab = tab
        destination = .tests
    }

    /// Goes to the Chat page with the chats showing, or collapses them if they already are.
    func toggleChats(in settings: AppSettings) {
        if destination == .chat {
            settings.chatsOpen.toggle()
        } else {
            destination = .chat
            settings.chatsOpen = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onTerminate: (() -> Void)?
    /// True while something is running that quitting would throw away.
    static var isBusy: (() -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also behave like a regular app when launched straight from `swift run`.
        NSApp.setActivationPolicy(.regular)
        // Closing the main window quits, but only once any running test has finished.
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

    /// False so AppKit can't quit in the middle of a test: quitWhenIdle does it instead.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
                // With a panel open the window stays wide enough for the page beside it.
                .frame(minWidth: (settings.telemetryOpen ? 860 + settings.telemetryWidth : 980) + (settings.chatsOpen ? ChatsColumn.width : 0),
                       minHeight: 640)
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
                        string: "\(Brand.tagline)\nOpen models running on this Mac. With the harness off, nothing leaves it.",
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
                Button("Model Library") { ui.destination = .library }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button(settings.telemetryOpen ? "Hide Telemetry" : "Show Telemetry") { settings.telemetryOpen.toggle() }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(ui.destination == .chat && settings.chatsOpen ? "Hide Chats" : "Show Chats") { ui.toggleChats(in: settings) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Search Chats") {
                    ui.destination = .chat
                    settings.chatsOpen = true
                    ui.wantsChatSearchFocus = true
                }
                .keyboardShortcut("f")
                Divider()
                Button("Model Test Results") { ui.openTests(.model) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Hardware Test Results") { ui.openTests(.hardware) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Harness Test Results") { ui.openTests(.harness) }
                    .keyboardShortcut("5", modifiers: [.command, .option])
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
