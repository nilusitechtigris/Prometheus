#if DEBUG
import AppKit

/// Debug-build-only automation used for UI verification without Screen Recording permission.
///   LOCALAI_SNAPSHOT_DIR=/path      write window snapshots (snap-N.png) every LOCALAI_SNAPSHOT_INTERVAL seconds
///   LOCALAI_AUTOPROMPT="text"       start a new chat and send this prompt after launch
///   LOCALAI_SHOW_LIBRARY=1          open the model library after launch
@MainActor
enum DebugHooks {
    static func install(chat: ChatController, ui: UIState) {
        let env = ProcessInfo.processInfo.environment
        if let prompt = env["LOCALAI_AUTOPROMPT"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                chat.newConversation()
                chat.send(prompt)
            }
        }
        if env["LOCALAI_SHOW_LIBRARY"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2))
                ui.showLibrary = true
            }
        }
        if let dir = env["LOCALAI_SNAPSHOT_DIR"] {
            let interval = Double(env["LOCALAI_SNAPSHOT_INTERVAL"] ?? "") ?? 4
            let count = Int(env["LOCALAI_SNAPSHOT_COUNT"] ?? "") ?? 5
            Task {
                for i in 0..<count {
                    try? await Task.sleep(for: .seconds(interval))
                    snapshot(to: "\(dir)/snap-\(i).png")
                }
            }
        }
    }

    static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("AppKitWindow") }) ?? NSApp.mainWindow else { return }
        write(window, to: path)
        if let sheet = window.attachedSheet {
            write(sheet, to: path.replacingOccurrences(of: ".png", with: "-sheet.png"))
        }
    }

    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
