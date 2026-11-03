#if DEBUG
import AppKit
import SwiftUI

/// Debug-build-only automation used for UI verification without Screen Recording permission.
///   LOCALAI_SNAPSHOT_DIR=/path      write window snapshots (snap-N.png) every LOCALAI_SNAPSHOT_INTERVAL seconds
///   LOCALAI_AUTOPROMPT="text"       start a new chat and send this prompt after launch
///   LOCALAI_SHOW_LIBRARY=1          open the model library after launch
///   LOCALAI_SHOW_MODEL_PICKER=1     open the model + quant picker after launch
///   LOCALAI_NO_ACTIVATE=1           don't bring the app to the front on launch
///   LOCALAI_DATA_DIR=/path          keep chats in this folder instead of the user's
///   LOCALAI_DESTINATION=model|hardware   open that test dashboard after launch
///   LOCALAI_AUTOTEST=model|hardware      run that test after launch
///   LOCALAI_TEST_MODEL=tag          model the model test runs on (the chat's model stays as it is)
///   LOCALAI_SHOW_TEST_PICKER=1      open the model test's model picker after launch
///   LOCALAI_OPEN_WIDGETS=1          open both floating telemetry widgets after launch (see ContentView)
///   LOCALAI_WIDGET_ZOOM=1.5         resize open widget windows by this factor after 3 s
///   LOCALAI_RENDER_DIR=/path        render both full dashboards (narrow and wide) after LOCALAI_RENDER_DELAY seconds
@MainActor
enum DebugHooks {
    static func install(chat: ChatController, ui: UIState, lab: TestLab, backends: BackendController,
                        monitor: SystemMonitor, settings: AppSettings) {
        let env = ProcessInfo.processInfo.environment
        switch env["LOCALAI_DESTINATION"] {
        case "model": ui.destination = .modelTest
        case "hardware": ui.destination = .hardwareTest
        default: break
        }
        if let zoom = Double(env["LOCALAI_WIDGET_ZOOM"] ?? "") {
            Task {
                try? await Task.sleep(for: .seconds(3))
                for window in NSApp.windows where window.identifier?.rawValue.contains("widget") == true {
                    var frame = window.frame
                    frame.size = NSSize(width: frame.width * zoom, height: frame.height * zoom)
                    window.setFrame(frame, display: true)
                }
            }
        }
        if let dir = env["LOCALAI_RENDER_DIR"] {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_RENDER_DELAY"] ?? "") ?? 3))
                let pages: [(String, AnyView)] = [("model", AnyView(ModelTestDashboard(scrollable: false))),
                                                  ("hardware", AnyView(HardwareTestDashboard(scrollable: false)))]
                for (name, page) in pages {
                    for width in [760.0, 1120.0] {
                        let content = page
                            .environment(settings).environment(backends).environment(chat)
                            .environment(monitor).environment(ui).environment(lab)
                            .frame(width: width)
                            .background(Color(white: 0.12))
                            .environment(\.colorScheme, .dark)
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 2
                        if let cg = renderer.cgImage,
                           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(Int(width)).png"))
                        }
                    }
                }
            }
        }
        lab.testModelID = env["LOCALAI_TEST_MODEL"]
        if env["LOCALAI_SHOW_TEST_PICKER"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                ui.showTestModelPicker = true
            }
        }
        if let test = env["LOCALAI_AUTOTEST"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                try? await Task.sleep(for: .seconds(1))
                if test == "hardware" {
                    lab.runHardwareTest(monitor: monitor, backends: backends)
                } else {
                    lab.runModelTest(backends: backends, settings: settings)
                }
            }
        }
        if let prompt = env["LOCALAI_AUTOPROMPT"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                chat.newConversation()
                chat.send(prompt)
            }
        }
        if env["LOCALAI_SHOW_MODEL_PICKER"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                ui.showModelPicker = true
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
        for (i, popover) in NSApp.windows.filter({ $0.isVisible && $0.className.contains("Popover") }).enumerated() {
            write(popover, to: path.replacingOccurrences(of: ".png", with: "-popover\(i).png"))
        }
        for other in NSApp.windows where other.isVisible && other !== window {
            if let id = other.identifier?.rawValue, id.contains("widget") {
                write(other, to: path.replacingOccurrences(of: ".png", with: "-\(id.split(separator: "-").prefix(2).joined(separator: "-")).png"))
            }
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
