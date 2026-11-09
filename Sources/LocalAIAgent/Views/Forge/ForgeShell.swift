import AppKit
import SwiftUI

/// The app's layout: a sidebar on near-black, with each page in a rounded panel beside it.
struct ForgeShell: View {
    @Environment(UIState.self) private var ui
    @Environment(DevSession.self) private var dev

    /// One side of a comparison has the whole window, so the sidebar steps aside too.
    private var pageFills: Bool { ui.destination == .chat && dev.isOn && dev.compareFillsWindow }

    var body: some View {
        HStack(spacing: 0) {
            if !pageFills {
                ForgeSidebar().transition(.move(edge: .leading))
            }
            MainPage()
                // Clear of the window's title bar, where clicks would drag the window.
                .safeAreaPadding(.top, 22)
                .background(Forge.panel.opacity(0.84))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
                .padding([.vertical, .trailing], 10)
                .padding(.leading, pageFills ? 10 : 0)
        }
        .animation(Motion.quick, value: pageFills)
        .overlay(alignment: .bottom) { ToastHost() }
        .background(WindowBackdrop())
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

/// The AI-generated picture behind the whole window.
private struct WindowBackdrop: View {
    var body: some View {
        if let picture = Art.window {
            Image(nsImage: picture)
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Sidebar

private struct ForgeSidebar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(BackendController.self) private var backends
    @Environment(TestLab.self) private var lab
    /// So the highlight slides from one item to the next.
    @Namespace private var highlight

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                BrandMark(size: 56)
                BrandWordmark(size: 13)
                Text(Brand.tagline).font(.uiCaption).foregroundStyle(Palette.accent)
            }
            .padding(.top, 46)
            .padding(.bottom, 26)

            VStack(spacing: 4) {
                item("house.fill", "Home", selected: ui.destination == .home) { ui.destination = .home }
                item("bubble.left.fill", "Chat", selected: ui.destination == .chat) {
                    withAnimation(Motion.quick) { ui.toggleChats(in: settings) }
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
        .animation(Motion.page, value: ui.destination)
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
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.gradient)
                            .matchedGeometryEffect(id: "icon", in: highlight)
                    }
                }
            Text(title).font(.uiCallout).foregroundStyle(selected ? Forge.ink : Forge.dim)
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.mini) }
            if lit { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
        }
        .padding(.horizontal, 7)
        .frame(height: 42)
        .background {
            if selected {
                ZStack {
                    shape.fill(LinearGradient(colors: [Palette.accent.opacity(0.2), Palette.accent.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
                    shape.strokeBorder(Palette.accent.opacity(0.26), lineWidth: 1)
                }
                .matchedGeometryEffect(id: "row", in: highlight)
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
                Text(harnessOn ? "\(settings.harnessVersion.label) on" : "Local · \(backends.kind.displayName)")
                    .font(.uiCaption2).foregroundStyle(Forge.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Forge.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
        .help(harnessOn ? (WebConsent.shared.policy == .allowed
                               ? "Harness on: search terms go to \(WebConsent.destinations)"
                               : "Harness on: nothing leaves this Mac unless you allow a lookup")
                        : "100% local — prompts and responses never leave this Mac")
    }
}

// MARK: - Toasts

/// A short message at the foot of the window, which goes away by itself.
struct Toast: Equatable {
    let id = UUID()
    let message: String
    let symbol: String
}

private struct ToastHost: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            if let toast = ui.toast {
                Label(toast.message, systemImage: toast.symbol)
                    .font(.uiCallout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Forge.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(Motion.quick, value: ui.toast)
        .allowsHitTesting(false)
    }
}
