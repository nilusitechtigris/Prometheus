import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            FrameworkSettings()
                .tabItem { Label("Frameworks", systemImage: "shippingbox") }
            SafetySettings()
                .tabItem { Label("Safety", systemImage: "checkmark.shield") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 580, height: 460)
        .tint(Palette.accent)
    }
}

private struct AppearanceSettings: View {
    private var store = ThemeStore.shared

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: store.theme == theme) {
                            withAnimation(.snappy) { store.theme = theme }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Color theme")
            } footer: {
                Text("Themes change accents, the composer glow and the ambient background. Green, yellow and red always keep their health meaning. Light and dark mode follow macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [theme.accent, theme.glow, theme.accent2],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkles").font(.title2.weight(.semibold)).foregroundStyle(.white)
                }
                .frame(height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
                        .padding(-3)
                )
                .scaleEffect(hovering ? 1.03 : 1)
                .shadow(color: theme.accent.opacity(hovering || selected ? 0.4 : 0), radius: 8, y: 3)
                HStack(spacing: 4) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                    Text(theme.name).font(.callout.weight(selected ? .semibold : .regular))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.2)) { hovering = h } }
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
                    .frame(minHeight: 240)
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
