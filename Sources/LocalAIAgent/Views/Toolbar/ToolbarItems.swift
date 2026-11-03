import SwiftUI

/// Compact always-visible health readout in the toolbar.
struct VitalsStrip: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = monitor.snapshot
        Button {
            openWindow(id: TelemetryWidgetKind.hardware.windowID)
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
        .help("Live system health. Click for the Hardware widget.")
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
