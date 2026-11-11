import AppKit
import SwiftUI

/// The app's layout: the name in the title bar's row, each page below it, and a dock of pages at the foot.
struct ForgeShell: View {
    @Environment(UIState.self) private var ui
    @Environment(DevSession.self) private var dev
    @Environment(BackendController.self) private var backends

    /// One side of a comparison has the whole window, so the name and the dock step aside too.
    private var pageFills: Bool { ui.destination == .chat && dev.isOn && dev.compareFillsWindow }
    private var isHome: Bool { ui.destination == .home }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 0) {
            if !pageFills {
                titleRow.transition(.opacity)
            }
            MainPage()
                // Home has no panel: the question stands on the window itself, in the flame's light.
                .background(isHome ? Color.clear : Forge.panel.opacity(0.92))
                .clipShape(shape)
                .overlay(shape.strokeBorder(isHome ? Color.clear : Forge.line, lineWidth: 1))
                .padding(.horizontal, 10)
                // Without the title row, stay clear of the window's title bar, where clicks would drag the window.
                .padding(.top, pageFills ? 30 : 0)
                .padding(.bottom, pageFills ? 10 : 0)
            if !pageFills {
                ForgeDock().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.quick, value: pageFills)
        .overlay(alignment: .bottom) { ToastHost() }
        .background(WindowBackdrop(isHome: isHome))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .windowToolbar)
        .background(ForgeWindowStyle(canvas: ThemeStore.shared.theme.canvasHex))
        .onChange(of: backends.lastError) { _, problem in
            // A model that couldn't be removed used to fail without a word.
            if let problem {
                ui.showToast(problem, symbol: "exclamationmark.triangle.fill")
                backends.lastError = nil
            }
        }
    }

    /// The name, on the same line as the window buttons and to their right. It takes no clicks, so the
    /// window can be dragged by it. The theme dots at the far end of this line are part of the title bar
    /// itself (see `ForgeWindowStyle`), because a control drawn here would lose its clicks to the bar.
    private var titleRow: some View {
        Text(Brand.name)
            .font(.geist(13, weight: .semibold))
            .foregroundStyle(Forge.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 78)
            .frame(height: 30)
            .allowsHitTesting(false)
    }
}

/// The look: a dark ground and one accent colour, both from the theme, and white at a few strengths.
enum Forge {
    /// Behind the whole window.
    @MainActor static var black: Color { ThemeStore.shared.theme.canvas }
    /// Behind each page.
    @MainActor static var panel: Color { ThemeStore.shared.theme.panel }
    /// Cards on a page.
    @MainActor static var card: Color { ThemeStore.shared.theme.card }
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

/// Runs the background up behind the window buttons, in the theme's colour, and puts the theme dots in
/// the title bar.
private struct ForgeWindowStyle: NSViewRepresentable {
    let canvas: UInt32

    final class StyledView: NSView {
        var canvas: UInt32 = 0 { didSet { apply() } }
        private var hasDots = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            if !hasDots {
                // An accessory is the title bar's own way to hold a control: its clicks arrive, where a
                // control drawn under the bar by the page would start dragging the window instead.
                let dots = NSTitlebarAccessoryViewController()
                dots.layoutAttribute = .trailing
                let host = NSHostingView(rootView: ThemeDots())
                host.frame.size = host.fittingSize
                dots.view = host
                window.addTitlebarAccessoryViewController(dots)
                hasDots = true
            }
            apply()
        }

        private func apply() {
            // Said again on every update, and once more after it: the window's own title came back once a
            // page had been opened.
            window?.titleVisibility = .hidden
            DispatchQueue.main.async { [weak self] in self?.window?.titleVisibility = .hidden }
            window?.backgroundColor = NSColor(srgbRed: CGFloat((canvas >> 16) & 0xFF) / 255, green: CGFloat((canvas >> 8) & 0xFF) / 255,
                                              blue: CGFloat(canvas & 0xFF) / 255, alpha: 1)
        }
    }

    func makeNSView(context: Context) -> StyledView {
        let view = StyledView()
        view.canvas = canvas
        return view
    }

    func updateNSView(_ view: StyledView, context: Context) { view.canvas = canvas }
}

/// Ember or Rose, as two dots of their colour at the end of the title bar. The one in use has a ring.
private struct ThemeDots: View {
    private var store = ThemeStore.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                let selected = store.theme == theme
                Button {
                    withAnimation(Motion.quick) { store.theme = theme }
                } label: {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 12, height: 12)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(theme.name) theme")
                .accessibilityLabel("\(theme.name) theme")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.trailing, 10)
        .frame(height: 28)
    }
}

/// The theme's ground. On Home the flame lights it from the middle; every other page is unlit.
private struct WindowBackdrop: View {
    let isHome: Bool

    var body: some View {
        ZStack {
            Forge.black
            RadialGradient(colors: [Palette.glow.opacity(0.17), .clear], center: UnitPoint(x: 0.5, y: 0.27), startRadius: 0, endRadius: 540)
                .opacity(isHome ? 1 : 0)
                .animation(Motion.page, value: isHome)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dock

/// The pages, in a row at the foot of the window.
private struct ForgeDock: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @Environment(DevSession.self) private var dev
    /// So the highlight slides from one item to the next.
    @Namespace private var highlight

    private var inChat: Bool { ui.destination == .chat }

    var body: some View {
        HStack(spacing: 4) {
            item("sparkle", "Ask", selected: ui.destination == .home) { ui.destination = .home }
                .help("Start a task")
            // Always the chats, with the list showing. It used to fold the list away on a second click,
            // and to show Dev mode when that had been left on.
            item("clock.arrow.circlepath", "History", selected: inChat && !dev.isOn) {
                dev.isOn = false
                settings.chatsOpen = true
                ui.destination = .chat
            }
            .help("Your chats (⌥⌘2 folds the list away)")
            item("chevron.left.forwardslash.chevron.right", "Dev", selected: inChat && dev.isOn) {
                dev.isOn = true
                ui.destination = .chat
            }
            .help("Dev mode: the agent writes code in a project folder and runs it")
            item("cube", "Models", selected: ui.destination == .library) { ui.destination = .library }
            item("checklist", "Tests", selected: ui.destination == .tests, busy: lab.isRunning) { ui.destination = .tests }
            item("gearshape.fill", "Settings", selected: ui.destination == .settings) { ui.destination = .settings }
        }
        .padding(5)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
        .padding(.vertical, 10)
        .animation(Motion.page, value: ui.destination)
        .animation(Motion.page, value: dev.isOn)
    }

    private func item(_ symbol: String, _ title: String, selected: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = Capsule(style: .circular)
        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.uiCallout.weight(selected ? .semibold : .regular))
                if busy { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(selected ? Palette.onAccent : Forge.ink)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background {
                if selected { shape.fill(Palette.gradient).matchedGeometryEffect(id: "page", in: highlight) }
            }
            // A page that isn't open shows where a click would land.
            .hoverFill(shape, when: !selected)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    // Above the dock.
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(Motion.quick, value: ui.toast)
        .allowsHitTesting(false)
    }
}
