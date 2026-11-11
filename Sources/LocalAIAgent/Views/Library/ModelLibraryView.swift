import AppKit
import SwiftUI

struct ModelLibraryView: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @State private var category: CatalogModel.Category? = nil
    @State private var removing: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Model Library", subtitle: subtitle, caption: frameworkCaption) { FrameworkSwitch() }
                SafetyCallout()
                filterBar
                // Cards in a row share a top edge and a height, whatever each one's button is.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(filtered) { model in
                        ModelCard(model: model)
                    }
                }
                if backends.kind == .ollama && !backends.unverifiedModels.isEmpty {
                    unverifiedSection
                }
            }
            .padding(24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Remove \(removing ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove from Disk", role: .destructive) {
                if let r = removing { Task { await backends.delete(r) } }
                removing = nil
            }
        } message: {
            Text("The model files will be deleted. You can download it again later.")
        }
    }

    private var subtitle: String {
        "\(monitor.chipName) · \(Format.gigabytes(Int64(ProcessInfo.processInfo.physicalMemory))) unified memory · ≈ \(Format.gigabytes(monitor.gpuBudgetBytes)) usable by the GPU · estimates at \(Format.tokens(settings.contextLength)) context"
    }

    private var frameworkCaption: String {
        let state: String
        switch backends.status {
        case .online: state = "Running"
        case .checking: state = "Connecting…"
        case .offline: state = "Not running"
        }
        return "\(state) · chats use this framework too"
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterButton(nil, title: "All", symbol: "square.grid.2x2")
            ForEach(CatalogModel.Category.allCases) { c in
                filterButton(c, title: c.rawValue, symbol: c.symbol)
            }
            Spacer()
        }
    }

    private func filterButton(_ c: CatalogModel.Category?, title: String, symbol: String) -> some View {
        Button {
            withAnimation(Motion.quick) { category = c }
        } label: {
            ChoicePill(title: title, symbol: symbol, selected: category == c)
        }
        .buttonStyle(.soft)
        .accessibilityAddTraits(category == c ? .isSelected : [])
    }

    private var filtered: [CatalogModel] {
        guard let category else { return ModelCatalog.all }
        return ModelCatalog.all.filter { $0.category == category }
    }

    private var unverifiedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Other installed models (unverified)", symbol: "exclamationmark.shield")
            Text("These aren't in the curated list, so they're disabled unless you allow unverified models in Settings › Safety.")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
            ForEach(backends.unverifiedModels) { model in
                Card(padding: 10) {
                    HStack {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(Palette.warning)
                        Text(model.id).font(.uiCallout.monospaced())
                        Text(Format.bytes(model.sizeBytes)).font(.uiCaption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove…", role: .destructive) { removing = model.id }.controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Which framework's models the page shows. It's the same choice as the chat's framework picker, so
/// switching here switches chats too. It waits while a test runs, since the test is using the framework.
private struct FrameworkSwitch: View {
    @Environment(BackendController.self) private var backends
    @Environment(TestLab.self) private var lab

    var body: some View {
        Picker("Framework", selection: Binding(get: { backends.kind }, set: { backends.switchBackend(to: $0) })) {
            ForEach(BackendKind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(lab.isRunning)
        .help(lab.isRunning ? "A test is using this framework. Switch once it finishes."
                            : "Show the models for another framework. Chats switch to it too.")
    }
}

private struct SafetyCallout: View {
    @Environment(BackendController.self) private var backends

    private var source: String {
        backends.kind == .mlx
            ? "They download from Hugging Face as safetensors weight files (tensors only, no executable code), converted for MLX by the mlx-community project, and run fully offline."
            : "They download as GGUF or safetensors weight files (tensors only, no executable code), are checksum-verified by Ollama, and run fully offline."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.uiTitle2)
                .foregroundStyle(Palette.good)
            VStack(alignment: .leading, spacing: 4) {
                Text("Every model here is verified").font(.uiHeadline)
                Text("Curated open-weight models published by Meta, Google, Microsoft, Alibaba Qwen, Mistral AI, IBM, DeepSeek and OpenAI — each one used and evaluated by a very large community. \(source)")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
        .overlay(RoundedRectangle(cornerRadius: Forge.radius, style: .continuous).strokeBorder(Palette.good.opacity(0.28), lineWidth: 1))
    }
}

struct ModelCard: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    let model: CatalogModel
    var compact = false
    @State private var confirmRemove = false
    @State private var chosenTag: String?

    /// The quantizations this framework can run.
    private var available: [QuantVariant] { model.variants(for: backends.kind) }

    /// The quantization this card is acting on: the user's pick, else an installed one, else the default.
    private var variant: QuantVariant {
        if let tag = chosenTag, let v = available.first(where: { $0.tag == tag }) { return v }
        if let selected = backends.selectedModel.flatMap({ model.variant(forTag: $0.id) }), available.contains(selected) { return selected }
        return available.first { backends.installed($0) != nil } ?? available.first(where: \.isDefault) ?? available.first ?? model.defaultVariant
    }

    private var installed: LocalModel? {
        if backends.kind.supportsModelDownloads { return backends.installed(variant) }
        return backends.models.first { $0.catalog?.id == model.id }
    }

    var body: some View {
        let variant = self.variant
        let estimate = backends.memoryEstimate(for: model, variant: variant)
        let verdict = MemoryFit.verdict(requiredBytes: estimate, budget: monitor.gpuBudgetBytes)

        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.displayName).font(.uiHeadline)
                            if model.featured {
                                Image(systemName: "star.fill").font(.uiCaption).foregroundStyle(.yellow)
                                    .help("Staff pick")
                            }
                        }
                        Text("\(model.publisher) · \(model.parameters) · \(model.license)")
                            .font(.uiCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Palette.good)
                        .help(backends.kind == .mlx ? "Verified: \(model.publisher)'s model, converted by mlx-community" : "Verified: official weights from \(model.publisher)")
                }

                if !compact {
                    Text(model.summary)
                        .font(.uiCallout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                }

                if backends.kind.supportsModelDownloads && !available.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            ForEach(available) { v in
                                variantChip(v, selected: v == variant)
                            }
                        }
                        Text("\(variant.quality) · \(variant.size) · quantized by \(variant.quantizedBy)")
                            .font(.uiCaption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Chip(text: "\(Format.tokens(model.maxContext)) ctx", symbol: "text.word.spacing")
                    if model.thinking { Chip(text: "Thinking", symbol: "brain.head.profile", tint: Palette.accent) }
                }

                HStack(spacing: 6) {
                    StatusDot(level: verdict.level, size: 7)
                    Text(verdict.label).font(.uiCaption.weight(.semibold))
                    Text("≈ \(Format.gigabytes(estimate))")
                        .font(.uiCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Estimated memory for weights + \(Format.tokens(settings.contextLength)) context, out of ≈ \(Format.gigabytes(monitor.gpuBudgetBytes)) the GPU can use")
                    Spacer(minLength: 6)
                    action(variant).fixedSize()
                }
                // As tall as its tallest button, so a card to use and a card to download are the same height.
                .frame(minHeight: 28)
            }
        }
        .confirmationDialog("Remove \(model.displayName) \(variant.quant)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from Disk", role: .destructive) {
                if let installed { Task { await backends.delete(installed.id) } }
            }
        } message: {
            Text("Frees \(variant.size). You can download it again any time.")
        }
    }

    private func variantChip(_ v: QuantVariant, selected: Bool) -> some View {
        let isInstalled = backends.installed(v) != nil
        return Button {
            withAnimation(Motion.quick) { chosenTag = v.tag }
        } label: {
            HStack(spacing: 3) {
                if isInstalled { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                Text(v.quant)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.07)),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(selected ? Palette.onAccent : (isInstalled ? Palette.accent : Color.secondary))
        }
        .buttonStyle(.soft)
        .help("\(v.quant) · \(v.quality) · \(v.size)\(isInstalled ? " · installed" : "")")
    }

    @ViewBuilder
    private func action(_ variant: QuantVariant) -> some View {
        if let pull = backends.pulls[variant.tag] {
            if let error = pull.error {
                // The reason is on the page, not behind a pointer hover.
                HStack(spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.uiCaption2).foregroundStyle(Palette.critical)
                        .frame(width: 190, alignment: .trailing).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { backends.cancelPull(variant.tag); backends.pull(variant.tag) }.controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: pull.fraction).frame(width: 90)
                        Text(pull.total > 0 ? "\(pull.status) \(Int(pull.fraction * 100))%" : pull.status)
                            .font(.uiCaption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button { backends.cancelPull(variant.tag) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Cancel download")
                }
            }
        } else if let installed {
            let inUse = backends.selectedModel?.id == installed.id
            HStack(spacing: 6) {
                if inUse {
                    Label("In use", systemImage: "checkmark")
                        .font(.uiCaption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 6)
                } else {
                    Button("Use") { backends.select(installed) }
                        .buttonStyle(OutlineButtonStyle(compact: true))
                }
                if backends.kind.supportsModelDownloads {
                    Menu {
                        Button("Remove from Disk…", role: .destructive) { confirmRemove = true }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        } else if backends.kind == .mlx && available.isEmpty {
            Text("Not on MLX")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .help("No MLX version of this model passed the check for tensors-only files")
        } else if backends.kind.supportsModelDownloads {
            Button {
                backends.pull(variant.tag)
            } label: {
                Label("Download", systemImage: "arrow.down")
            }
            .controlSize(.small)
            .buttonStyle(AccentButtonStyle(compact: true))
            .disabled(!backends.status.isOnline)
        } else {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.huggingFaceHint, forType: .string)
            } label: {
                Label("Copy HF name", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Search for \(model.huggingFaceHint) in \(backends.kind.displayName)")
        }
    }
}
