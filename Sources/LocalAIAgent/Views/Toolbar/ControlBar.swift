import SwiftUI

/// Framework · Model · Context pickers shown in the centre of the toolbar.
struct ControlBar: View {
    var body: some View {
        HStack(spacing: 6) {
            FrameworkMenu()
            ModelMenu()
            ContextWindowMenu()
        }
    }
}

private struct PillLabel: View {
    let symbol: String
    let title: String
    var caption: String?
    var dot: HealthLevel?

    var body: some View {
        HStack(spacing: 6) {
            if let dot { StatusDot(level: dot, size: 7) }
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            if let caption {
                Text(caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.callout)
    }
}

struct FrameworkMenu: View {
    @Environment(BackendController.self) private var backends

    var body: some View {
        Menu {
            Section("Framework") {
                ForEach(BackendKind.allCases) { kind in
                    Button {
                        backends.switchBackend(to: kind)
                    } label: {
                        let running = backends.availability[kind] == true
                        Text("\(kind == backends.kind ? "✓ " : "")\(kind.displayName)  —  \(running ? "running" : "not detected")")
                        Text(kind.tagline)
                    }
                }
            }
            Divider()
            SettingsLink { Text("Framework Settings…") }
        } label: {
            PillLabel(symbol: backends.kind.symbol, title: backends.kind.displayName, dot: statusLevel)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Inference framework: \(statusText)")
    }

    private var statusLevel: HealthLevel {
        switch backends.status {
        case .online: return .good
        case .checking: return .warning
        case .offline: return .critical
        }
    }

    private var statusText: String {
        switch backends.status {
        case .online(let v): return "connected (\(v))"
        case .checking: return "connecting…"
        case .offline: return "not running"
        }
    }
}

struct ModelMenu: View {
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        Menu {
            if backends.verifiedModels.isEmpty {
                Text("No verified models installed")
            } else {
                Section("Verified models") {
                    ForEach(backends.verifiedModels) { model in
                        modelButton(model)
                    }
                }
            }
            if !backends.unverifiedModels.isEmpty {
                Section(settings.allowUnverifiedModels ? "Unverified models" : "Unverified (enable in Settings › Safety)") {
                    ForEach(backends.unverifiedModels) { model in
                        modelButton(model).disabled(!settings.allowUnverifiedModels)
                    }
                }
            }
            Divider()
            Button("Model Library…") { ui.showLibrary = true }
        } label: {
            if let model = backends.selectedModel {
                PillLabel(symbol: model.isVerified ? "checkmark.shield.fill" : "exclamationmark.shield",
                          title: model.displayName,
                          caption: model.parameterSize ?? model.catalog?.parameters)
            } else {
                PillLabel(symbol: "shippingbox", title: "Choose a model")
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Model")
    }

    private func modelButton(_ model: LocalModel) -> some View {
        Button {
            backends.select(model)
        } label: {
            let check = model.id == backends.selectedModel?.id ? "✓ " : ""
            Text("\(check)\(model.displayName)")
            Text(subtitle(model))
        }
    }

    private func subtitle(_ model: LocalModel) -> String {
        var parts: [String] = []
        if model.displayName != model.id { parts.append(model.id) }
        if let size = model.sizeBytes { parts.append(Format.bytes(size)) }
        if let est = backends.memoryEstimate(for: model, context: backends.effectiveContext) {
            parts.append(MemoryFit.verdict(requiredBytes: est, budget: monitor.gpuBudgetBytes).label)
        }
        return parts.joined(separator: " · ")
    }
}

struct ContextWindowMenu: View {
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        Menu {
            if backends.kind.supportsPerRequestContext {
                Section("Context window") {
                    ForEach(backends.contextOptions, id: \.self) { option in
                        Button {
                            settings.contextLength = option
                        } label: {
                            let check = option == backends.effectiveContext ? "✓ " : ""
                            Text("\(check)\(Format.tokens(option)) tokens")
                            Text(estimate(for: option))
                        }
                    }
                }
                if let max = backends.maxContext {
                    Text("Model maximum: \(Format.tokens(max)) tokens")
                }
                Text("Larger windows remember more but use more memory.\nChanging it reloads the model.")
            } else {
                Text("\(backends.kind.displayName) sets the context window when the model is loaded.")
                if let ctx = backends.details?.maxContext {
                    Text("Loaded with \(Format.tokens(ctx)) tokens")
                }
            }
        } label: {
            PillLabel(symbol: "text.word.spacing", title: "\(Format.tokens(backends.effectiveContext))", caption: "context")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Context window — how much of the conversation the model can see")
    }

    private func estimate(for context: Int) -> String {
        guard let model = backends.selectedModel,
              let bytes = backends.memoryEstimate(for: model, context: context) else { return "" }
        let verdict = MemoryFit.verdict(requiredBytes: bytes, budget: monitor.gpuBudgetBytes)
        return "≈ \(Format.gigabytes(bytes)) total · \(verdict.label)"
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
