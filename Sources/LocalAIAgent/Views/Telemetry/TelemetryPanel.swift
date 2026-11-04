import AppKit
import SwiftUI

/// Live telemetry, docked at the right of the main area on every page. It takes its width from the
/// page beside it, so nothing ever sits on top of the chat. Drag its left edge to resize it.
struct TelemetryPanel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 0) {
            PanelResizeHandle(width: $settings.telemetryWidth)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 10) {
                        GenerationWidget()
                        HardwareWidget()
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .frame(width: settings.telemetryWidth)
            .background(Forge.black)
        }
    }

    private var header: some View {
        HStack {
            Text("Telemetry").font(.uiCallout.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            TelemetryPanelToggle()
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Collapses or opens the telemetry panel.
struct TelemetryPanelToggle: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button {
            withAnimation(.snappy) { settings.telemetryOpen.toggle() }
        } label: {
            PixelLabel("Telemetry", systemImage: "sidebar.trailing").labelStyle(.iconOnly)
        }
        .help("\(settings.telemetryOpen ? "Collapse" : "Open") the telemetry panel (⌥⌘1)")
    }
}

/// The panel's left edge. A thin line, with a wider area around it to grab.
private struct PanelResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Color.primary.opacity(0.12)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = startWidth ?? width
                            startWidth = start
                            width = min(max(start - drag.translation.width, AppSettings.telemetryWidths.lowerBound),
                                        AppSettings.telemetryWidths.upperBound)
                        }
                        .onEnded { _ in startWidth = nil })
            }
            .help("Drag to resize the telemetry panel")
    }
}
