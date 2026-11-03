import AppKit
import SwiftUI

/// The telemetry widgets that float above other windows, each in its own window.
enum TelemetryWidgetKind: String, CaseIterable, Identifiable {
    case generation, hardware

    var id: String { rawValue }
    var windowID: String { "widget-\(rawValue)" }
    var title: String { self == .generation ? "Generation" : "Hardware" }
    var symbol: String { self == .generation ? "bolt.fill" : "gauge.with.dots.needle.67percent" }
    /// Layout width; the window scales everything from here when resized.
    var baseWidth: CGFloat { 340 }
}

/// Root view of a floating widget window.
struct FloatingWidgetWindow: View {
    let kind: TelemetryWidgetKind
    @Environment(UIState.self) private var ui
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        FloatingWidget(baseWidth: kind.baseWidth, onClose: { dismissWindow(id: kind.windowID) }) {
            switch kind {
            case .generation: GenerationWidget()
            case .hardware: HardwareWidget()
            }
        }
        .onAppear { ui.openWidgets.insert(kind) }
        .onDisappear { ui.openWidgets.remove(kind) }
    }
}

/// Lays the widget out at its base width, then scales it to the window, so resizing zooms the whole
/// widget instead of reflowing it. The window keeps the widget's shape, floats above other windows
/// and moves by dragging anywhere on it.
private struct FloatingWidget<Content: View>: View {
    let baseWidth: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var baseHeight: CGFloat = 0
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / baseWidth
            content
                .background(.regularMaterial, in: shape)
                .frame(width: baseWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { inner in
                    Color.clear.preference(key: WidgetHeightKey.self, value: inner.size.height)
                })
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onPreferenceChange(WidgetHeightKey.self) { baseHeight = $0 }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(.thickMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(6)
            .opacity(hovering ? 1 : 0)
            .help("Close widget")
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .background(FloatingWindowConfigurator(baseSize: CGSize(width: baseWidth, height: baseHeight)))
        .ignoresSafeArea()
    }
}

private struct WidgetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Turns the hosting window into a floating, chrome-less widget that keeps the widget's aspect ratio.
private struct FloatingWindowConfigurator: NSViewRepresentable {
    let baseSize: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let size = baseSize
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            guard size.width > 0, size.height > 0 else { return }
            window.contentAspectRatio = size
            window.contentMinSize = NSSize(width: size.width * 0.6, height: size.height * 0.6)
            window.contentMaxSize = NSSize(width: size.width * 3, height: size.height * 3)
            // Snap to the widget's shape when its content height changes.
            let current = window.contentRect(forFrameRect: window.frame).size
            let wanted = NSSize(width: current.width, height: (current.width * size.height / size.width).rounded())
            if abs(current.height - wanted.height) > 1 {
                var frame = window.frame
                frame.origin.y += frame.height - wanted.height
                frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: wanted)).size
                window.setFrame(frame, display: true)
            }
            window.invalidateShadow()
        }
    }
}

/// Opens or closes a telemetry widget window.
@MainActor
struct TelemetryWidgetToggle {
    let open: OpenWindowAction
    let dismiss: DismissWindowAction
    let ui: UIState

    func callAsFunction(_ kind: TelemetryWidgetKind) {
        if ui.openWidgets.contains(kind) {
            dismiss(id: kind.windowID)
        } else {
            open(id: kind.windowID)
        }
    }
}
