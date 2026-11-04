import SwiftUI

/// Shared capsule label for the pickers under the composer.
struct PickerPill<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        HStack(spacing: 6) {
            label
            PixelIcon("chevron.up.chevron.down")
                .font(.uiCaption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.uiCallout)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .contentShape(PixelRect.pill)
    }
}

// MARK: - Framework

struct FrameworkPickerButton: View {
    @Environment(BackendController.self) private var backends
    var compact = false
    @State private var show = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            PickerPill {
                StatusDot(level: statusLevel, size: 7)
                PixelIcon(backends.kind.symbol).foregroundStyle(.secondary)
                if !compact { Text(backends.kind.displayName).lineLimit(1) }
            }
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .help("Framework: \(backends.kind.displayName) — \(statusText)")
        .popover(isPresented: $show, arrowEdge: .top) {
            FrameworkPopover { show = false }
        }
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

private struct FrameworkPopover: View {
    @Environment(BackendController.self) private var backends
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Framework").font(.uiHeadline).padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(BackendKind.allCases) { kind in
                PopoverRow(selected: kind == backends.kind) {
                    backends.switchBackend(to: kind)
                    dismiss()
                } content: {
                    PixelIcon(kind.symbol)
                        .frame(width: 22)
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.displayName).font(.uiCallout.weight(.semibold))
                        Text(kind.tagline).font(.uiCaption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let running = backends.availability[kind] == true
                    HStack(spacing: 4) {
                        StatusDot(level: running ? .good : .unknown, size: 6)
                        Text(running ? "Running" : "Not detected")
                    }
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                }
            }
            Divider().padding(.vertical, 4)
            SettingsLink {
                PixelLabel("Framework Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(width: 380)
    }
}

// MARK: - Context window

struct ContextPickerButton: View {
    @Environment(BackendController.self) private var backends
    var compact = false
    @State private var show = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            PickerPill {
                PixelIcon("text.word.spacing").foregroundStyle(.secondary)
                Text(Format.tokens(backends.effectiveContext)).monospacedDigit()
                if !compact { Text("context").foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .help("Context window — how much of the conversation the model can see")
        .popover(isPresented: $show, arrowEdge: .top) {
            ContextPopover { show = false }
        }
    }
}

private struct ContextPopover: View {
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Context window").font(.uiHeadline).padding(.horizontal, 8).padding(.bottom, 4)
            if backends.kind.supportsPerRequestContext {
                ForEach(backends.contextOptions, id: \.self) { option in
                    PopoverRow(selected: option == backends.effectiveContext) {
                        settings.contextLength = option
                        dismiss()
                    } content: {
                        Text("\(Format.tokens(option)) tokens").font(.uiCallout.monospacedDigit())
                        Spacer()
                        if let model = backends.selectedModel,
                           let bytes = backends.memoryEstimate(for: model, context: option) {
                            let verdict = MemoryFit.verdict(requiredBytes: bytes, budget: monitor.gpuBudgetBytes)
                            HStack(spacing: 5) {
                                StatusDot(level: verdict.level, size: 6)
                                Text("≈ \(Format.gigabytes(bytes))").monospacedDigit()
                                Text(verdict.label).foregroundStyle(.secondary)
                            }
                            .font(.uiCaption)
                        }
                    }
                }
                Text("\(backends.maxContext.map { "Model maximum: \(Format.tokens($0)) tokens. " } ?? "")Larger windows remember more but use more memory. Changing it reloads the model.")
                    .font(.uiCaption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            } else {
                Text("\(backends.kind.displayName) sets the context window when the model is loaded\(backends.details?.maxContext.map { " — currently \(Format.tokens($0)) tokens" } ?? "").")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .padding(12)
        .frame(width: 330)
    }
}

/// Selectable row used inside the composer popovers.
struct PopoverRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PixelIcon(selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Color.secondary.opacity(0.5))
                content
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                PixelRect(radius: 9)
                    .fill(selected ? Palette.accent.opacity(0.12) : (hovering ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
