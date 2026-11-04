import AppKit
import SwiftUI

/// Draft "Forge" layout: near-black, one fire colour, Geist type, thin rules instead of boxes.
/// Turned on from the sidebar or View › Try Forge Draft. The classic layout stays as it was.
struct DraftShell: View {
    var body: some View {
        HStack(spacing: 0) {
            DraftRail()
            Forge.rule(vertical: true)
            VStack(spacing: 0) {
                DraftTopBar()
                Forge.rule()
                MainPage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Forge.rule()
                DraftStatusBar()
            }
        }
        .background(Forge.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.plainControls, true)
        .toolbar(.hidden, for: .windowToolbar)
        .background(DraftWindowStyle())
    }
}

/// The draft's look: near-black, one fire colour, and white at a few strengths.
enum Forge {
    static let black = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let flame = Color(red: 1, green: 0.353, blue: 0.122)
    static let ink = Color.white.opacity(0.94)
    static let dim = Color.white.opacity(0.56)
    static let faint = Color.white.opacity(0.28)
    static let line = Color.white.opacity(0.09)

    /// Thin dividers do the work boxes used to.
    static func rule(vertical: Bool = false) -> some View {
        line.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    /// Small monospaced capitals for labels.
    static func label(_ text: String, color: Color = dim) -> some View {
        Text(text.uppercased())
            .font(.geistMono(10.5, weight: .medium))
            .tracking(0.9)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Runs the draft's background up behind the window buttons, and restores the window on the way out.
private struct DraftWindowStyle: NSViewRepresentable {
    final class StyledView: NSView {
        weak var styledWindow: NSWindow?
        var addedFullSizeContent = false
        var originalBackground: NSColor?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            styledWindow = window
            originalBackground = window.backgroundColor
            window.backgroundColor = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
                addedFullSizeContent = true
            }
        }
    }

    func makeNSView(context: Context) -> StyledView { StyledView() }

    func updateNSView(_ view: StyledView, context: Context) {}

    static func dismantleNSView(_ view: StyledView, coordinator: ()) {
        guard let window = view.styledWindow else { return }
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        if let background = view.originalBackground { window.backgroundColor = background }
        if view.addedFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
    }
}

// MARK: - Rail

private struct DraftRail: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 4) {
            BrandMark(size: 34)
                .padding(.top, 44)
                .padding(.bottom, 16)
            item("bubble.left", "Chat", .chat)
            item("checklist", "Tests", .tests)
            item("square.stack.3d.up", "Library", .library)
            Forge.rule().padding(.horizontal, 18).padding(.vertical, 6)
            widget(.generation, "Speed")
            widget(.hardware, "Vitals")
            Spacer()
            SettingsLink { rowLabel("gearshape", "Settings", selected: false) }
                .buttonStyle(.plain)
            action("arrow.uturn.backward", "Classic") { settings.draftLayout = false }
                .padding(.bottom, 12)
        }
        .frame(width: 72)
    }

    private func item(_ symbol: String, _ title: String, _ target: UIState.Destination) -> some View {
        Button { ui.destination = target } label: { rowLabel(symbol, title, selected: ui.destination == target) }
            .buttonStyle(.plain)
    }

    private func action(_ symbol: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { rowLabel(symbol, title, selected: false) }
            .buttonStyle(.plain)
    }

    /// Opens or closes a floating telemetry widget, lit while it's on screen.
    private func widget(_ kind: TelemetryWidgetKind, _ title: String) -> some View {
        Button {
            TelemetryWidgetToggle(open: openWindow, dismiss: dismissWindow, ui: ui)(kind)
        } label: {
            rowLabel(kind.symbol, title, selected: ui.openWidgets.contains(kind))
        }
        .buttonStyle(.plain)
        .help("Show or hide the floating \(kind.title) widget")
    }

    private func rowLabel(_ symbol: String, _ title: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17))
            Text(title.uppercased()).font(.geistMono(8.5, weight: .medium)).tracking(0.5)
        }
        .foregroundStyle(selected ? Forge.flame : Forge.dim)
        .frame(width: 72, height: 54)
        .overlay(alignment: .leading) {
            if selected { Forge.flame.frame(width: 2, height: 30) }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Top and status bars

private struct DraftTopBar: View {
    @Environment(BackendController.self) private var backends

    var body: some View {
        HStack(spacing: 14) {
            Text(Brand.name.uppercased())
                .font(.geistPixel(24))
                .foregroundStyle(Forge.ink)
            Spacer()
            if let model = backends.selectedModel {
                Text(model.displayName).font(.geistMono(12, weight: .medium)).foregroundStyle(Forge.ink).lineLimit(1)
                Text(model.quantLabel).font(.geistMono(12)).foregroundStyle(Forge.dim)
                Forge.rule(vertical: true).frame(height: 14)
            }
            HStack(spacing: 6) {
                Circle().fill(backends.status.isOnline ? Palette.good : Palette.critical).frame(width: 6, height: 6)
                Forge.label("\(backends.kind.displayName) \(backends.status.isOnline ? "online" : "offline")")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 12)
    }
}

private struct DraftStatusBar: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings

    private var harnessStatus: (text: String, color: Color) {
        guard backends.kind.supportsTools else { return ("Needs Ollama", Forge.ink) }
        return settings.harnessEnabled ? ("On", Forge.flame) : ("Off", Forge.ink)
    }

    private var load: (text: String, color: Color) {
        let s = monitor.snapshot
        let level = max(Thresholds.cpuUsage.level(s.cpuUsage), Thresholds.gpuUsage.level(s.gpuUsage), s.memoryLevel)
        switch level {
        case .good, .unknown: return ("Stable", Palette.good)
        case .warning: return ("Elevated", Palette.warning)
        case .critical: return ("High", Palette.critical)
        }
    }

    private var runningTests: Int {
        [lab.modelProgress != nil, lab.hardwareProgress != nil, lab.harnessProgress != nil].filter { $0 }.count
    }

    var body: some View {
        HStack(spacing: 22) {
            status("Harness", harnessStatus.text, harnessStatus.color)
            status("Load", load.text, load.color)
            status("Tests", runningTests > 0 ? "\(runningTests) running" : "Idle", runningTests > 0 ? Forge.flame : Forge.ink)
            Spacer()
            Forge.label(monitor.chipName, color: Forge.faint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }

    private func status(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Forge.label(title, color: Forge.faint)
            Forge.label(value, color: color)
        }
    }
}
