import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FrameworkSettings()
                .tabItem { Label("Frameworks", systemImage: "shippingbox") }
            SafetySettings()
                .tabItem { Label("Safety", systemImage: "checkmark.shield") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Responses") {
                LabeledContent("Temperature") {
                    HStack {
                        Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", settings.temperature)).monospacedDigit().frame(width: 40)
                    }
                }
                Picker("Max response length", selection: $settings.maxResponseTokens) {
                    Text("Unlimited").tag(0)
                    ForEach([256, 512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0) tokens").tag($0) }
                }
                Picker("Default context window", selection: $settings.contextLength) {
                    ForEach(AppSettings.contextOptions, id: \.self) { Text("\(Format.tokens($0)) tokens").tag($0) }
                }
                Toggle("Let thinking models reason before answering", isOn: $settings.thinkingEnabled)
                Toggle("Free memory when switching models (Ollama)", isOn: $settings.unloadOnSwitch)
            }
            Section("System instructions") {
                TextEditor(text: $settings.systemPrompt)
                    .font(.callout)
                    .frame(minHeight: 90)
                Button("Reset to Default") { settings.systemPrompt = AppSettings.defaultSystemPrompt }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FrameworkSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends

    var body: some View {
        Form {
            Section {
                ForEach(BackendKind.allCases) { kind in
                    FrameworkRow(kind: kind)
                }
            } footer: {
                Text("All frameworks run on this Mac. Ollama supports one-click downloads and per-chat context windows; LM Studio, llama.cpp and MLX use their OpenAI-compatible server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FrameworkRow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends
    let kind: BackendKind
    @State private var url = ""

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(level: backends.availability[kind] == true ? .good : .critical)
            Image(systemName: kind.symbol).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.body.weight(.medium))
                Text(kind.tagline).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("URL", text: $url, prompt: Text(kind.defaultBaseURL))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .onSubmit(save)
            Button(kind == backends.kind ? "Active" : "Use") {
                save()
                backends.switchBackend(to: kind)
            }
            .disabled(kind == backends.kind)
        }
        .onAppear { url = settings.baseURLs[kind.rawValue] ?? "" }
        .onChange(of: url) { save() }
    }

    private func save() {
        settings.setBaseURL(url, for: kind)
        Task { await backends.refreshAvailability() }
    }
}

private struct SafetySettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verified models only").font(.headline)
                        Text("By default you can only chat with models from the curated catalog: official open weights from well-known publishers, used by millions, distributed as GGUF tensors with no executable code.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.good).font(.title2)
                }
            }
            Section {
                Toggle("Allow unverified models", isOn: $settings.allowUnverifiedModels)
            } footer: {
                Text("Only enable this if you trust where a model came from. Unverified models show an orange shield.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Label("Prompts and responses never leave this Mac. The only internet access is downloading models you choose, through your framework.", systemImage: "lock.shield")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettings: View {
    @Environment(ChatController.self) private var chat
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Conversations") {
                LabeledContent("Saved chats", value: "\(chat.conversations.count)")
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConversationStore().fileURL])
                    }
                    Spacer()
                    Button("Delete All Chats…", role: .destructive) { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all chats?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { chat.clearAll() }
        } message: {
            Text("This permanently removes every conversation from this Mac.")
        }
    }
}
