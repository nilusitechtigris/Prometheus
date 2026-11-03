import AppKit
import SwiftUI

struct ModelLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @State private var category: CatalogModel.Category? = nil
    @State private var removing: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SafetyCallout()
                    filterBar
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { model in
                            ModelCard(model: model)
                        }
                    }
                    if backends.kind == .ollama && !backends.unverifiedModels.isEmpty {
                        unverifiedSection
                    }
                }
                .padding(22)
            }
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

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Library").font(.title2.weight(.semibold))
                Text("\(monitor.chipName) · \(Format.gigabytes(Int64(ProcessInfo.processInfo.physicalMemory))) unified memory · ≈ \(Format.gigabytes(monitor.gpuBudgetBytes)) usable by the GPU · estimates at \(Format.tokens(settings.contextLength)) context")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterButton(nil, title: "All", symbol: "square.grid.2x2")
            ForEach(CatalogModel.Category.allCases.filter { $0 != .recommended }) { c in
                filterButton(c, title: c.rawValue, symbol: c.symbol)
            }
            Spacer()
        }
    }

    private func filterButton(_ c: CatalogModel.Category?, title: String, symbol: String) -> some View {
        let active = category == c
        return Button {
            withAnimation(.snappy) { category = c }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? AnyShapeStyle(Palette.accent.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
                .foregroundStyle(active ? Palette.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private var filtered: [CatalogModel] {
        guard let category else { return ModelCatalog.all }
        return ModelCatalog.all.filter { $0.category == category }
    }

    private var unverifiedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Other installed models (unverified)", symbol: "exclamationmark.shield")
            Text("These aren't in the curated list, so they're disabled unless you allow unverified models in Settings › Safety.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(backends.unverifiedModels) { model in
                Card(padding: 10) {
                    HStack {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(Palette.warning)
                        Text(model.id).font(.callout.monospaced())
                        Text(Format.bytes(model.sizeBytes)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove…", role: .destructive) { removing = model.id }.controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct SafetyCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(Palette.good)
            VStack(alignment: .leading, spacing: 4) {
                Text("Every model here is verified").font(.headline)
                Text("Curated open-weight models published by Meta, Google, Microsoft, Alibaba Qwen, Mistral AI, IBM, DeepSeek and OpenAI — each one used and evaluated by a very large community. They download as GGUF weight files (tensors only, no executable code), are checksum-verified by Ollama, and run fully offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.good.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.good.opacity(0.25), lineWidth: 0.5))
    }
}

struct ModelCard: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    let model: CatalogModel
    var compact = false
    @State private var confirmRemove = false

    private var installed: LocalModel? {
        backends.models.first { $0.id == model.ollamaTag || $0.id == model.ollamaTag + ":latest" }
            ?? (backends.kind == .ollama ? nil : backends.models.first { $0.catalog?.id == model.id })
    }

    var body: some View {
        let estimate = backends.memoryEstimate(for: model)
        let verdict = MemoryFit.verdict(requiredBytes: estimate, budget: monitor.gpuBudgetBytes)

        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.displayName).font(.headline)
                            if model.featured {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                    .help("Staff pick")
                            }
                        }
                        Text("\(model.publisher) · \(model.parameters) · \(model.license)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Palette.good)
                        .help("Verified: official weights from \(model.publisher)")
                }

                if !compact {
                    Text(model.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                }

                HStack(spacing: 6) {
                    Chip(text: model.downloadSize, symbol: "arrow.down.circle")
                    Chip(text: "\(Format.tokens(model.maxContext)) ctx", symbol: "text.word.spacing")
                    if model.thinking { Chip(text: "Thinking", symbol: "brain.head.profile", tint: Palette.accent) }
                }

                HStack(spacing: 6) {
                    StatusDot(level: verdict.level, size: 7)
                    Text(verdict.label).font(.caption.weight(.semibold))
                    Text("≈ \(Format.gigabytes(estimate))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Estimated memory for weights + \(Format.tokens(settings.contextLength)) context, out of ≈ \(Format.gigabytes(monitor.gpuBudgetBytes)) the GPU can use")
                    Spacer(minLength: 6)
                    action.fixedSize()
                }
            }
        }
        .confirmationDialog("Remove \(model.displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from Disk", role: .destructive) {
                if let installed { Task { await backends.delete(installed.id) } }
            }
        } message: {
            Text("Frees \(model.downloadSize). You can download it again any time.")
        }
    }

    @ViewBuilder
    private var action: some View {
        if let pull = backends.pulls[model.ollamaTag] {
            if let error = pull.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical).help(error)
                    Button("Retry") { backends.cancelPull(model.ollamaTag); backends.pull(model.ollamaTag) }.controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: pull.fraction).frame(width: 90)
                        Text(pull.total > 0 ? "\(pull.status) \(Int(pull.fraction * 100))%" : pull.status)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button { backends.cancelPull(model.ollamaTag) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Cancel download")
                }
            }
        } else if let installed {
            let inUse = backends.selectedModel?.id == installed.id
            HStack(spacing: 4) {
                Button(inUse ? "In Use" : "Use") { backends.select(installed) }
                    .controlSize(.small)
                    .disabled(inUse)
                if backends.kind == .ollama {
                    Menu {
                        Button("Remove from Disk…", role: .destructive) { confirmRemove = true }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        } else if backends.kind.supportsModelDownloads {
            Button {
                backends.pull(model.ollamaTag)
            } label: {
                Label("Download", systemImage: "arrow.down")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
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
