import AppKit
import SwiftUI

/// The app's layout: a header with the title, each page below it, and a dock of pages at the foot.
/// The flame is drawn here once, over everything, and moves between Home and the header.
struct ForgeShell: View {
    @Environment(UIState.self) private var ui
    @Environment(DevSession.self) private var dev
    /// Where the flame can be right now, measured by the pages (see `flamePlace`).
    @State private var flamePlaces: [FlameSlot: CGRect] = [:]

    /// One side of a comparison has the whole window, so the header and the dock step aside too.
    private var pageFills: Bool { ui.destination == .chat && dev.isOn && dev.compareFillsWindow }
    private var isHome: Bool { ui.destination == .home }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 0) {
            if !pageFills {
                ForgeHeader().transition(.move(edge: .top).combined(with: .opacity))
            }
            MainPage()
                // Home has no panel: the question stands on the window itself, in the flame's light.
                .background(isHome ? Color.clear : Forge.panel.opacity(0.92))
                .clipShape(shape)
                .overlay(shape.strokeBorder(isHome ? Color.clear : Forge.line, lineWidth: 1))
                .padding(.horizontal, 10)
                // Without the header, stay clear of the window's title bar, where clicks would drag the window.
                .padding(.top, pageFills ? 30 : 0)
                .padding(.bottom, pageFills ? 10 : 0)
            if !pageFills {
                ForgeDock().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(FlamePlaces.self) { places in
            // Home's place goes when Home does. Keeping the last one would send the flame back to a page
            // that isn't there, so the whole set is replaced.
            flamePlaces = places
        }
        .overlay(alignment: .topLeading) {
            // Home's place while Home is the page; the header's on the way out and everywhere else.
            if !pageFills, let frame = flamePlaces[isHome ? .home : .docked] ?? flamePlaces[.docked] {
                FlameView(target: frame).allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: FlamePlaces.space)
        .animation(Motion.flame, value: isHome)
        .animation(Motion.quick, value: pageFills)
        .overlay(alignment: .bottom) { ToastHost() }
        .background(WindowBackdrop(isHome: isHome))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .windowToolbar)
        .background(ForgeWindowStyle(canvas: ThemeStore.shared.theme.canvasHex))
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

/// Runs the background up behind the window buttons, in the theme's colour.
private struct ForgeWindowStyle: NSViewRepresentable {
    let canvas: UInt32

    final class StyledView: NSView {
        var canvas: UInt32 = 0 { didSet { apply() } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
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

/// The theme's ground, lit by the flame: from the middle on Home, from beside the title anywhere else.
private struct WindowBackdrop: View {
    let isHome: Bool

    var body: some View {
        ZStack {
            Forge.black
            RadialGradient(colors: [Palette.glow.opacity(0.17), .clear], center: UnitPoint(x: 0.5, y: 0.27), startRadius: 0, endRadius: 540)
                .opacity(isHome ? 1 : 0)
            RadialGradient(colors: [Palette.glow.opacity(0.13), .clear], center: UnitPoint(x: 0.08, y: 0), startRadius: 0, endRadius: 440)
                .opacity(isHome ? 0 : 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Header

/// The title with the flame's place beside it, and the things that stay within reach on every page.
private struct ForgeHeader: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat

    private var isHome: Bool { ui.destination == .home }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The flame's place. It is always here, so the title never moves up or down: on Home it has
            // no width, and the flame is in the middle of the page instead.
            Color.clear
                .frame(width: isHome ? 0 : FlameSlot.docked.size.width, height: FlameSlot.docked.size.height)
                .flamePlace(.docked)
                // The foot of the glass stands on the line the title is written on.
                .alignmentGuide(.firstTextBaseline) { $0.height * FlameSlot.foot }
                .padding(.trailing, isHome ? -10 : -2)
            Text(Brand.name).font(.geist(15, weight: .semibold)).foregroundStyle(Forge.ink)
            Spacer(minLength: 12)
            if !isHome {
                Button {
                    chat.newConversation()
                    ui.destination = .home
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .buttonStyle(HeaderPillStyle())
                .help("Back to the start, for a new task")
                .transition(.opacity)
            }
            ThemeSwitch()
            status
        }
        // Clear of the window buttons at the left, and low enough that a click lands on a control and
        // doesn't drag the window by its title bar.
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var harnessOn: Bool { settings.harnessEnabled && backends.kind.supportsTools }

    private var status: some View {
        let state = SetupState(backends)
        let ready = state == .ready
        return HStack(spacing: 8) {
            Circle().fill(state.level.color).frame(width: 7, height: 7)
            Text(ready ? (backends.selectedModel?.displayName ?? state.title(backends.kind)) : state.title(backends.kind))
                .font(.uiCallout.weight(.medium))
                .lineLimit(1)
            Text(ready ? (harnessOn ? "Harness on" : "Ready") : state.nextStep)
                .font(.uiCallout)
                .foregroundStyle(Forge.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
        .contentShape(Capsule(style: .circular))
        // Not ready: the chat page is where the next step is. Ready: the models are a click away.
        .onTapGesture { ui.destination = ready ? .library : .chat }
        .onChange(of: backends.lastError) { _, problem in
            // A model that couldn't be removed used to fail without a word.
            if let problem {
                ui.showToast(problem, symbol: "exclamationmark.triangle.fill")
                backends.lastError = nil
            }
        }
        .help(harnessOn ? (WebConsent.shared.policy == .allowed
                               ? "Harness on: search terms go to \(WebConsent.destinations)"
                               : "Harness on: nothing leaves this Mac unless you allow a lookup")
                        : "100% local — prompts and responses never leave this Mac")
    }
}

/// Ember or Rose, one click apart.
private struct ThemeSwitch: View {
    private var store = ThemeStore.shared
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                let selected = store.theme == theme
                Button {
                    withAnimation(Motion.quick) { store.theme = theme }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(theme.accent).frame(width: 10, height: 10)
                        Text(theme.name).font(.uiCallout.weight(.medium)).foregroundStyle(selected ? Forge.ink : Forge.dim)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule(style: .circular).fill(Color.white.opacity(0.16)).matchedGeometryEffect(id: "pick", in: highlight)
                        }
                    }
                    .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.soft)
                .accessibilityLabel("\(theme.name) theme")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
        .help("Switch between the Ember and Rose looks")
    }
}

/// A quiet pill button for the header.
private struct HeaderPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.uiCallout.weight(.medium))
            .foregroundStyle(Forge.ink)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Forge.card, in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule(style: .circular))
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Dock

/// The pages, in a row at the foot of the window.
private struct ForgeDock: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    /// So the highlight slides from one item to the next.
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            item("sparkle", "Ask", selected: ui.destination == .home) { ui.destination = .home }
                .help("Start a task")
            item("clock.arrow.circlepath", "History", selected: ui.destination == .chat) {
                withAnimation(Motion.quick) { ui.toggleChats(in: settings) }
            }
            .help("Show your chats, or collapse them if they're showing (⌥⌘2)")
            item("cube", "Models", selected: ui.destination == .library) { ui.destination = .library }
            item("checklist", "Tests", selected: ui.destination == .tests, busy: lab.isRunning) { ui.destination = .tests }
            item("gearshape.fill", "Settings", selected: ui.destination == .settings) { ui.destination = .settings }
        }
        .padding(5)
        .background(Forge.card, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(Forge.line, lineWidth: 1))
        .padding(.vertical, 10)
        .animation(Motion.page, value: ui.destination)
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
