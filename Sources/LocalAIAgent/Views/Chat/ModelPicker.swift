import SwiftUI

/// Model + quantization picker shown under the composer, next to the temperature control.
struct ModelPickerButton: View {
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui
    /// Drops the provider and gives up width first, for tight panels.
    var narrow = false

    var body: some View {
        @Bindable var ui = ui
        Button {
            ui.showModelPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                if let model = backends.selectedModel {
                    Image(systemName: model.isVerified ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(model.isVerified ? Palette.good : Palette.warning)
                    Text(model.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    QuantBadge(text: model.quantLabel)
                    if !narrow {
                        Text("by \(model.quantProvider)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "cube.transparent")
                    Text("Choose a model")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.uiCaption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.uiCallout)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.soft)
        .glassCapsule(interactive: true)
        .help("Choose the model and its quantization (⇧⌘M)")
        .popover(isPresented: $ui.showModelPicker, arrowEdge: .top) {
            ModelPickerPopover { ui.showModelPicker = false }
        }
    }
}

struct QuantBadge: View {
    let text: String
    var selected = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            // A tag is one word. It never wraps or shrinks, however tight its row gets.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.accent.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(selected ? Palette.onAccent : Palette.accent)
    }
}

private struct ModelPickerPopover: View {
    @Environment(BackendController.self) private var backends
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model").font(.uiHeadline)
                Spacer()
                Label(backends.kind.displayName, systemImage: backends.kind.symbol)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if backends.kind == .ollama {
                        if backends.installedGroups.isEmpty {
                            emptyState
                        }
                        ForEach(backends.installedGroups, id: \.catalog.id) { group in
                            CatalogGroupRow(catalog: group.catalog, installed: group.models)
                        }
                    } else {
                        if backends.verifiedModels.isEmpty { emptyState }
                        ForEach(backends.verifiedModels) { model in
                            PlainModelRow(model: model, enabled: true)
                        }
                    }

                    if !backends.unverifiedModels.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.shield")
                            Text(settings.allowUnverifiedModels ? "Unverified" : "Unverified — enable in Settings › Safety")
                        }
                        .font(.uiCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                        ForEach(backends.unverifiedModels) { model in
                            PlainModelRow(model: model, enabled: settings.allowUnverifiedModels)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 460)

            Divider()
            HStack {
                Text("Quant chips with ↓ download that variant.")
                    .font(.uiCaption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Model Library") {
                    dismiss()
                    ui.destination = .library
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 440)
    }

    private var emptyState: some View {
        Text("No verified models installed yet. Open the Model Library to download one.")
            .font(.uiCallout)
            .foregroundStyle(.secondary)
            .padding(12)
    }
}

/// One base model with every quantization the catalog offers.
private struct CatalogGroupRow: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    let catalog: CatalogModel
    let installed: [LocalModel]
    @State private var hovering = false

    private var selectedVariant: QuantVariant? {
        guard let id = backends.selectedModel?.id else { return nil }
        return catalog.variant(forTag: id)
    }

    var body: some View {
        let isSelected = selectedVariant != nil
        let shown = selectedVariant ?? installed.first.flatMap { catalog.variant(forTag: $0.id) } ?? catalog.defaultVariant

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.uiTitle3)
                    .foregroundStyle(isSelected ? Palette.accent : Color.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(catalog.displayName).font(.uiCallout.weight(.semibold))
                        if catalog.thinking {
                            Image(systemName: "brain.head.profile").font(.uiCaption).foregroundStyle(.secondary)
                                .help("Supports thinking")
                        }
                    }
                    Text("\(catalog.publisher) · \(catalog.parameters) · quantized by \(shown.quantizedBy)")
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(catalog.variants) { variant in
                    QuantChip(catalog: catalog, variant: variant,
                              isSelected: variant == selectedVariant,
                              isInstalled: backends.installed(variant) != nil)
                }
            }
            .padding(.leading, 30)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(0.10) : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let first = installed.first { backends.select(first) }
        }
    }
}

private struct QuantChip: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    let catalog: CatalogModel
    let variant: QuantVariant
    let isSelected: Bool
    let isInstalled: Bool

    var body: some View {
        let estimate = backends.memoryEstimate(for: catalog, variant: variant, context: backends.effectiveContext)
        let verdict = MemoryFit.verdict(requiredBytes: estimate, budget: monitor.gpuBudgetBytes)
        let pull = backends.pulls[variant.tag]

        Button {
            // A download that failed used to sit on its ring for good. Now a click tries again.
            if pull?.error != nil { backends.cancelPull(variant.tag) }
            if pull == nil || pull?.error != nil { backends.choose(variant) }
        } label: {
            HStack(spacing: 4) {
                if pull?.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
                } else if let pull {
                    ProgressView(value: pull.fraction).progressViewStyle(.circular).controlSize(.mini)
                } else if !isInstalled {
                    Image(systemName: "arrow.down.circle")
                } else {
                    Circle().fill(verdict.level.color).frame(width: 6, height: 6)
                }
                Text(variant.quant).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(pull.map { $0.error == nil ? "\(Int($0.fraction * 100))%" : "Retry" } ?? variant.size)
                    .font(.system(size: 10.5).monospacedDigit())
                    .opacity(0.75)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .circular).fill(isSelected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(isInstalled ? 0.08 : 0.03)))
            )
            .overlay(
                Capsule(style: .circular).strokeBorder(isInstalled || isSelected ? Color.clear : Color.secondary.opacity(0.35),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .foregroundStyle(isSelected ? Palette.onAccent : (isInstalled ? Color.primary : Color.secondary))
        }
        .buttonStyle(.soft)
        .disabled(!isInstalled && !backends.kind.supportsModelDownloads)
        .help(pull?.error ?? "\(variant.quant) · \(variant.quality) · \(variant.size) · quantized by \(variant.quantizedBy)\n"
              + "≈ \(Format.gigabytes(estimate)) with \(Format.tokens(backends.effectiveContext)) context — \(verdict.label)"
              + (isInstalled ? "" : "\nClick to download and switch"))
    }
}

/// Row for frameworks without a quant catalog (LM Studio, llama.cpp, MLX) and for unverified models.
private struct PlainModelRow: View {
    @Environment(BackendController.self) private var backends
    let model: LocalModel
    let enabled: Bool
    @State private var hovering = false

    var body: some View {
        let isSelected = backends.selectedModel?.id == model.id
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.uiTitle3)
                .foregroundStyle(isSelected ? Palette.accent : Color.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName).font(.uiCallout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    QuantBadge(text: model.quantLabel)
                    Text("by \(model.quantProvider)").font(.uiCaption).foregroundStyle(.secondary)
                    if let size = model.sizeBytes {
                        Text(Format.bytes(size)).font(.uiCaption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                if model.displayName != model.id {
                    Text(model.id).font(.uiCaption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(0.10) : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if enabled { backends.select(model) } }
    }
}
