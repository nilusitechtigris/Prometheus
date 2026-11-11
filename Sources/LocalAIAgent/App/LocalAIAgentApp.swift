import AppKit
import SwiftUI

/// Transient UI state shared between the window, menus and keyboard shortcuts.
@MainActor
@Observable
final class UIState {
    /// What the main area shows.
    enum Destination: Hashable { case home, chat, tests, library, settings }

    var destination: Destination = .home
    /// Which results the Tests page shows.
    var testTab: TestTab = .hardware
    /// Which section the Settings page shows.
    var settingsTab: SettingsTab = .general
    var showModelPicker = false
    var showTestModelPicker = false
    var composerFocusRequest = 0
    var draft = ""
    var chatSearch = ""
    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?
    /// Select mode in the chats column: ticking several chats to delete them together.
    var selectingChats = false
    var pickedChats: Set<UUID> = []
    /// Set to move the keyboard to the chat search, and cleared once it has.
    var wantsChatSearchFocus = false

    /// Shows a short message at the foot of the window, and reads it out to VoiceOver.
    func showToast(_ message: String, symbol: String) {
        toast = Toast(message: message, symbol: symbol)
        AccessibilityNotification.Announcement(message).post()
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { toast = nil }
        }
    }

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
    @State private var updater: AppUpdater
    @State private var dev: DevSession

    init() {
        AppFonts.register()
        // Before anything reads the saved data, so a build that reads it wrongly can't cost the only copy.
        DataBackup.runIfNeeded()
        let settings = AppSettings()
        let backends = BackendController(settings: settings)
        let chat = ChatController(settings: settings, backends: backends)
        let lab = TestLab()
        let dev = DevSession(backends: backends, settings: settings)
        let updater = AppUpdater(isBusy: { lab.isRunning || chat.isGenerating || !backends.pulls.isEmpty || dev.isBusy },
                                 restartMLX: { await backends.restartMLX() })
        _settings = State(initialValue: settings)
        _backends = State(initialValue: backends)
        _chat = State(initialValue: chat)
        _lab = State(initialValue: lab)
        _updater = State(initialValue: updater)
        _dev = State(initialValue: dev)
        AppDelegate.isBusy = { MainActor.assumeIsolated { lab.isRunning } }
        AppDelegate.onTerminate = {
            MainActor.assumeIsolated {
                chat.saveNow()
                dev.shutDown()
                backends.stopMLX()
            }
        }
    }

    private var inDev: Bool { ui.destination == .chat && dev.isOn }

    /// Opens the editor's find bar, which AppKit reads from the sender's tag.
    private func findInEditor() {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
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
                .environment(updater)
                .environment(dev)
                // With the telemetry panel open the window stays tall enough for the page above it.
                .frame(minWidth: 1100, minHeight: settings.telemetryOpen ? max(640, 400 + settings.telemetryHeight) : 640)
                .task {
                    backends.start()
                    monitor.start()
                    #if DEBUG
                    DebugHooks.install(chat: chat, ui: ui, lab: lab, backends: backends, monitor: monitor, settings: settings, updater: updater, dev: dev)
                    #endif
                }
        }
        .defaultSize(width: 1380, height: 880)
        // The header shows the name. Without this the window's own title came back above it whenever a
        // page other than Home was opened.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.name)") {
                    let centered = NSMutableParagraphStyle()
                    centered.alignment = .center
                    let credits = NSAttributedString(
                        string: "\(Brand.tagline)\nOpen models running on this Mac. Nothing leaves it unless you allow a web lookup.",
                        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                     .paragraphStyle: centered])
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: Brand.name, .credits: credits])
                }
                Button("Update \(Brand.name)…") {
                    ui.settingsTab = .updates
                    ui.destination = .settings
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { ui.destination = .settings }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    dev.isOn = false
                    ui.destination = .chat
                    chat.newConversation()
                    ui.composerFocusRequest += 1
                }
                .keyboardShortcut("n")
            }
            CommandGroup(before: .sidebar) {
                Button("Home") { ui.destination = .home }
                    .keyboardShortcut("1")
                Button("Chat") { ui.destination = .chat }
                    .keyboardShortcut("2")
                Button("Tests") { ui.destination = .tests }
                    .keyboardShortcut("3")
                Button("Models") { ui.destination = .library }
                    .keyboardShortcut("4")
                Divider()
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { dev.save() }
                    .keyboardShortcut("s")
                    .disabled(!inDev || !dev.isDirty)
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
                Button(inDev ? "Run File" : "Regenerate Response") {
                    if inDev, let page = dev.previewPath {
                        dev.preview(page)
                    } else if inDev {
                        dev.runOpenFile()
                    } else {
                        chat.regenerate()
                    }
                }
                .keyboardShortcut("r")
                .disabled(inDev ? !(dev.previewPath != nil || dev.openPath?.hasSuffix(".py") == true || dev.openPath.map(DevWeb.isPage) == true) : !chat.canSend || chat.selected?.messages.isEmpty != false)
                Divider()
                Button("Choose Model…") { ui.showModelPicker = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Model Library") { ui.destination = .library }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button(settings.telemetryOpen ? "Hide Telemetry" : "Show Telemetry") { settings.telemetryOpen.toggle() }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                    .disabled(ui.destination != .chat)
                Button(ui.destination == .chat && settings.chatsOpen ? "Hide Chats" : "Show Chats") { ui.toggleChats(in: settings) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Search Chats") {
                    if inDev {
                        findInEditor()
                        return
                    }
                    ui.destination = .chat
                    settings.chatsOpen = true
                    ui.wantsChatSearchFocus = true
                }
                .keyboardShortcut("f")
                Divider()
                Button("Model Test Results") { settings.showLab = true; ui.openTests(.model) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Hardware Test Results") { ui.openTests(.hardware) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Harness Test Results") { settings.showLab = true; ui.openTests(.harness) }
                    .keyboardShortcut("5", modifiers: [.command, .option])
                Button("Publish Test Results") { settings.showLab = true; ui.openTests(.publish) }
                    .keyboardShortcut("6", modifiers: [.command, .option])
            }
        }
    }
}
