import AppKit
import SwiftUI

/// The app's layout: a sidebar on near-black, with each page in a rounded panel beside it.
struct ForgeShell: View {
    var body: some View {
        HStack(spacing: 0) {
            ForgeSidebar()
            MainPage()
                // Clear of the window's title bar, where clicks would drag the window.
                .safeAreaPadding(.top, 22)
                .background(Forge.panel)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
                .padding([.vertical, .trailing], 10)
        }
        .background(SidebarBackdrop())
        .background(Forge.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .windowToolbar)
        .background(ForgeWindowStyle())
    }
}

/// The look: near-black, one accent colour that follows the theme, and white at a few strengths.
enum Forge {
    static let black = Color(red: 0.027, green: 0.031, blue: 0.027)
    /// Behind each page.
    static let panel = Color(red: 0.039, green: 0.043, blue: 0.039)
    /// Cards on a page.
    static let card = Color(red: 0.082, green: 0.088, blue: 0.08)
    static let ink = Color.white.opacity(0.94)
    static let dim = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.3)
    static let line = Color.white.opacity(0.09)

    static func rule(vertical: Bool = false) -> some View {
        line.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    /// Small labels above a group.
    static func label(_ text: String, color: Color = dim) -> some View {
        Text(text).font(.uiCaption.weight(.medium)).foregroundStyle(color).lineLimit(1)
    }
}

/// Runs the background up behind the window buttons.
private struct ForgeWindowStyle: NSViewRepresentable {
    final class StyledView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.backgroundColor = NSColor(srgbRed: 0.027, green: 0.031, blue: 0.027, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func makeNSView(context: Context) -> StyledView { StyledView() }

    func updateNSView(_ view: StyledView, context: Context) {}
}

/// A soft glow and a few fine curves behind the sidebar. Drawn once, so it adds no load.
private struct SidebarBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let accent = Palette.accent
            context.fill(Path(ellipseIn: CGRect(x: -120, y: size.height * 0.1, width: 260, height: 420)),
                         with: .radialGradient(Gradient(colors: [accent.opacity(0.13), .clear]),
                                               center: CGPoint(x: 10, y: size.height * 0.1 + 210), startRadius: 0, endRadius: 210))
            for line in 0..<7 {
                let offset = CGFloat(line) * 7
                var curve = Path()
                curve.move(to: CGPoint(x: -10, y: size.height - 120 + offset))
                curve.addCurve(to: CGPoint(x: 226, y: size.height - 210 + offset * 1.6),
                               control1: CGPoint(x: 70, y: size.height - 30 + offset), control2: CGPoint(x: 140, y: size.height - 250 - offset))
                context.stroke(curve, with: .color(accent.opacity(0.1)), lineWidth: 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar

private struct ForgeSidebar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(BackendController.self) private var backends
    @Environment(TestLab.self) private var lab

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                BrandMark(size: 44)
                BrandWordmark(size: 13)
                Text(Brand.tagline).font(.uiCaption).foregroundStyle(Palette.accent)
            }
            .padding(.top, 46)
            .padding(.bottom, 26)

            VStack(spacing: 4) {
                item("house.fill", "Home", selected: ui.destination == .home) { ui.destination = .home }
                item("bubble.left.fill", "Chat", selected: ui.destination == .chat) {
                    withAnimation(.snappy) { ui.toggleChats(in: settings) }
                }
                .help("Show your chats, or collapse them if they're showing (⌥⌘2)")
                item("checklist", "Tests", selected: ui.destination == .tests, busy: lab.isRunning) { ui.destination = .tests }
                item("cube", "Models", selected: ui.destination == .library) { ui.destination = .library }
                item("gearshape.fill", "Settings", selected: ui.destination == .settings) { ui.destination = .settings }
            }
            .padding(.horizontal, 14)

            Spacer()
            status
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(width: 216)
    }

    private func item(_ symbol: String, _ title: String, selected: Bool, lit: Bool = false, busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) { row(symbol, title, selected: selected, lit: lit, busy: busy) }
            .buttonStyle(.plain)
    }

    private func row(_ symbol: String, _ title: String, selected: Bool, lit: Bool = false, busy: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Palette.onAccent : (lit ? Palette.accent : Forge.dim))
                .frame(width: 26, height: 26)
                .background(selected ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.uiCallout).foregroundStyle(selected ? Forge.ink : Forge.dim)
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.mini) }
            if lit { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
        }
        .padding(.horizontal, 7)
        .frame(height: 42)
        .background {
            if selected {
                shape.fill(LinearGradient(colors: [Palette.accent.opacity(0.2), Palette.accent.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
                shape.strokeBorder(Palette.accent.opacity(0.26), lineWidth: 1)
            }
        }
        .contentShape(shape)
    }

    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

    private var status: some View {
        let online = backends.status.isOnline
        return HStack(spacing: 10) {
            Circle().fill(online ? Palette.good : Palette.critical).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(online ? "Ready to run" : "\(backends.kind.displayName) offline").font(.uiCaption.weight(.medium))
                Text(harnessOn ? "Harness on" : "Local · \(backends.kind.displayName)")
                    .font(.uiCaption2).foregroundStyle(Forge.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Forge.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
        .help(harnessOn ? "Harness on: search terms go to Wikipedia, Stack Overflow, arXiv and MDN"
                        : "100% local — prompts and responses never leave this Mac")
    }
}
