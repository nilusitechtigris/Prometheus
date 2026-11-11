import SwiftUI

/// The Chat page's two faces: Ask, a conversation with the model, and Dev, where the agent writes code in a
/// project folder. Home has the same choice as a toggle under its question (HomePage.swift); both set
/// `DevSession.isOn`.
///
/// The switch is drawn once, over both faces (see `MainPage`), in the corner where each face's top bar
/// begins. So it stays under the pointer when it is flipped, and the way back is where the way in was.
struct ChatModeSwitch: View {
    @Environment(DevSession.self) private var dev
    @Namespace private var highlight

    private static let segmentWidth: CGFloat = 64
    /// The room the switch takes, which the top bar of each face leaves free for it.
    static let width: CGFloat = segmentWidth * 2 + 6
    /// The height of the bar the switch sits in, the same on both faces.
    static let barHeight: CGFloat = 46
    /// How far the bar's contents are from the page's edges.
    static let barInset: CGFloat = 12

    var body: some View {
        let shape = Capsule(style: .circular)
        HStack(spacing: 0) {
            segment("Ask", symbol: "sparkle", on: false, help: "Ask: a conversation with the model")
            segment("Dev", symbol: "chevron.left.forwardslash.chevron.right", on: true,
                    help: "Dev mode: the agent writes code in a project folder and runs it")
        }
        .padding(3)
        .background(Forge.card, in: shape)
        .overlay(shape.strokeBorder(Forge.edge, lineWidth: 1))
        .animation(Motion.page, value: dev.isOn)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ask or Dev")
    }

    private func segment(_ title: String, symbol: String, on: Bool, help: String) -> some View {
        let selected = dev.isOn == on
        let shape = Capsule(style: .circular)
        return Button {
            dev.isOn = on
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.uiCallout.weight(selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Palette.onAccent : Forge.ink)
            .frame(width: Self.segmentWidth, height: Forge.pillHeight - 6)
            .background {
                if selected { shape.fill(Palette.gradient).matchedGeometryEffect(id: "mode", in: highlight) }
            }
            .hoverFill(shape, when: !selected)
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .help(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension UIState {
    /// Whether the Dev workspace is what the window shows: the Chat page, with its switch on Dev.
    func showsDev(_ dev: DevSession) -> Bool { destination == .chat && dev.isOn }
}
