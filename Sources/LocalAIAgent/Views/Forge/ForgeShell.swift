import AppKit
import SwiftUI

/// The app's layout: near-black, one accent colour, Geist type, thin rules instead of boxes, and a few
/// line drawings from Greek pottery and temples.
struct ForgeShell: View {
    var body: some View {
        HStack(spacing: 0) {
            ForgeRail()
            Forge.rule(vertical: true)
            VStack(spacing: 0) {
                ForgeTopBar()
                MeanderFrieze()
                MainPage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Forge.rule()
                ForgeStatusBar()
            }
        }
        .background(Forge.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .windowToolbar)
        .background(ForgeWindowStyle())
    }
}

/// The look: near-black, one accent colour that follows the theme, and white at a few strengths.
enum Forge {
    static let black = Color(red: 0.039, green: 0.039, blue: 0.043)
    @MainActor static var flame: Color { Palette.accent }
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

/// Runs the background up behind the window buttons.
private struct ForgeWindowStyle: NSViewRepresentable {
    final class StyledView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.backgroundColor = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func makeNSView(context: Context) -> StyledView { StyledView() }

    func updateNSView(_ view: StyledView, context: Context) {}
}

// MARK: - Rail

private struct ForgeRail: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 4) {
            BrandMark(size: 34)
                .padding(.top, 44)
                .padding(.bottom, 16)
            chats
            item("checklist", "Tests", .tests)
            item("square.stack.3d.up", "Library", .library)
            Forge.rule().padding(.horizontal, 18).padding(.vertical, 6)
            telemetry
            // A column stands in the empty stretch of the rail, clear of every label.
            DoricColumn()
                .stroke(Forge.faint.opacity(0.6), lineWidth: 1)
                .frame(width: 26)
                .frame(maxHeight: 260)
                .padding(.vertical, 14)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)
            SettingsLink { rowLabel("gearshape", "Settings", selected: false) }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
        }
        .frame(width: 72)
    }

    private func item(_ symbol: String, _ title: String, _ target: UIState.Destination) -> some View {
        Button { ui.destination = target } label: { rowLabel(symbol, title, selected: ui.destination == target) }
            .buttonStyle(.plain)
    }

    /// Opens the Chat page, then opens or collapses the chats beside it.
    private var chats: some View {
        Button {
            withAnimation(.snappy) { ui.toggleChats(in: settings) }
        } label: {
            rowLabel("bubble.left", "Chat", selected: ui.destination == .chat)
        }
        .buttonStyle(.plain)
        .help("Show your chats, or collapse them if they're showing (⌥⌘2)")
    }

    /// Opens or collapses the telemetry panel, lit while it's open.
    private var telemetry: some View {
        Button {
            withAnimation(.snappy) { settings.telemetryOpen.toggle() }
        } label: {
            rowLabel("gauge.with.dots.needle.67percent", "Telemetry", selected: settings.telemetryOpen)
        }
        .buttonStyle(.plain)
        .help("\(settings.telemetryOpen ? "Collapse" : "Open") the telemetry panel (⌥⌘1)")
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

private struct ForgeTopBar: View {
    @Environment(BackendController.self) private var backends

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Brand.name.uppercased())
                    .font(.geistPixel(24))
                    .foregroundStyle(Forge.ink)
                Text(Brand.greekName)
                    .font(.greek(14).italic())
                    .foregroundStyle(Forge.dim)
                    .accessibilityHidden(true)
            }
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

private struct ForgeStatusBar: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings

    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

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
                .help(harnessOn ? "Harness on: search terms go to Wikipedia, Stack Overflow, arXiv and MDN"
                                : "100% local — prompts and responses never leave this Mac")
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
