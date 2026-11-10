import AppKit
import SwiftUI

/// Live hardware telemetry, docked along the bottom of the Chat page. It takes its height from the page
/// above it, so nothing ever sits on top of the chat. Drag its top edge to resize it.
struct TelemetryPanel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            PanelResizeHandle(height: $settings.telemetryHeight)
            ScrollView {
                HardwareWidget().padding(10)
            }
        }
        .frame(height: settings.telemetryHeight)
        .background(Forge.panel)
    }
}

/// Collapses the telemetry panel.
struct TelemetryPanelToggle: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button {
            withAnimation(Motion.quick) { settings.telemetryOpen = false }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Forge.dim)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.soft)
        .help("Collapse the telemetry panel (⌥⌘1)")
    }
}

/// The panel's top edge. A thin line, with a wider area around it to grab.
private struct PanelResizeHandle: View {
    @Binding var height: Double
    @State private var startHeight: Double?

    var body: some View {
        Forge.line
            .frame(height: 1)
            .overlay {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = startHeight ?? height
                            startHeight = start
                            height = min(max(start - drag.translation.height, AppSettings.telemetryHeights.lowerBound),
                                         AppSettings.telemetryHeights.upperBound)
                        }
                        .onEnded { _ in startHeight = nil })
            }
            .help("Drag to resize the telemetry panel")
    }
}
