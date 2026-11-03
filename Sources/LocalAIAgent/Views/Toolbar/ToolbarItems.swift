import SwiftUI

/// Toggles the telemetry inspector. Filled with the theme gradient so it always reads as a button.
struct TelemetryButton: View {
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false

    var body: some View {
        let open = settings.showInspector
        Button {
            withAnimation(.snappy) { settings.showInspector.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .symbolEffect(.bounce, value: open)
                Text("Telemetry")
                Image(systemName: open ? "chevron.right" : "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Palette.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: Palette.accent.opacity(hovering ? 0.55 : 0.3), radius: hovering ? 6 : 3, y: 1)
            .brightness(hovering ? 0.06 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
        .help(open ? "Hide telemetry (⌥⌘I)" : "Show telemetry (⌥⌘I)")
        .accessibilityLabel(open ? "Hide telemetry" : "Show telemetry")
    }
}

/// Compact always-visible health readout in the toolbar.
struct VitalsStrip: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let s = monitor.snapshot
        Button {
            withAnimation(.snappy) { settings.showInspector = true }
        } label: {
            HStack(spacing: 10) {
                vital("CPU", Format.percent(s.cpuUsage), Thresholds.cpuUsage.level(s.cpuUsage))
                vital("GPU", Format.percent(s.gpuUsage), Thresholds.gpuUsage.level(s.gpuUsage))
                vital("MEM", Format.percent(s.memoryPercent), s.memoryLevel)
                vital("TEMP", Format.temp(s.cpuTemp), Thresholds.cpuTemp.level(s.cpuTemp))
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .help("Live system health — click for details")
    }

    private func vital(_ label: String, _ value: String, _ level: HealthLevel) -> some View {
        HStack(spacing: 4) {
            StatusDot(level: level, size: 6)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}
