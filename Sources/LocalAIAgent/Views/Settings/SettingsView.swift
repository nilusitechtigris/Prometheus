import AppKit
import SwiftUI

/// The sections of the Settings page.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, harness, appearance, frameworks, safety, data, updates

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .harness: return "checkmark.shield"
        case .appearance: return "paintpalette"
        case .frameworks: return "shippingbox"
        case .safety: return "lock.shield"
        case .data: return "tray.full"
        case .updates: return "arrow.down.circle"
        }
    }
}

/// Settings, as a page in the main window like Tests and Models. Its column is narrower than theirs, and
/// sits in the middle of the page as theirs do; it used to hang at the left with the right half empty.
struct SettingsView: View {
    @Environment(UIState.self) private var ui

    /// A comfortable width for a line of settings.
    private static let width: CGFloat = 820

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Settings", subtitle: "How replies are generated, how the app looks, which framework it uses, and what it's allowed to do.") { EmptyView() }
                // Pills, like the tests on Tests and the kinds of model on Models. They wrap in a narrow window.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            ui.settingsTab = tab
                        } label: {
                            ChoicePill(title: tab.title, symbol: tab.symbol, selected: ui.settingsTab == tab)
                        }
                        .buttonStyle(.soft)
                        .accessibilityAddTraits(ui.settingsTab == tab ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.quick, value: ui.settingsTab)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .frame(maxWidth: Self.width)
            .frame(maxWidth: .infinity)

            ScrollView {
                PageSwap(value: ui.settingsTab) {
                    VStack(alignment: .leading, spacing: 22) {
                        switch ui.settingsTab {
                        case .general: GeneralSettings()
                        case .harness: HarnessSettings()
                        case .appearance: AppearanceSettings()
                        case .frameworks: FrameworkSettings()
                        case .safety: SafetySettings()
                        case .data: DataSettings()
                        case .updates: UpdateSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: Self.width)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - The parts of a section

/// A group of settings: a title, a panel of rows with a line between each, and a note under it. The panel is
/// the one every page uses (`panelSurface`), where the system's grouped form had a shade of its own.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.uiHeadline).foregroundStyle(Forge.ink).padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(SettingsRows()) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelSurface()
            if let footer {
                Text(footer)
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Lays a group's rows out one under the other, each with the same room around it and a line before the next.
private struct SettingsRows: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            if child.id != last {
                Forge.rule().padding(.leading, 16)
            }
        }
    }
}

/// One setting: its name at the left, and what changes it at the right.
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.uiBody).foregroundStyle(Forge.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            control
        }
    }
}

/// A setting that is on or off.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

// MARK: - Sections

private struct AppearanceSettings: View {
    private var store = ThemeStore.shared

    var body: some View {
        SettingsGroup(title: "Color theme",
                      footer: "Themes change accents, the composer glow and the ambient background. Green, yellow and red always keep their health meaning.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeSwatch(theme: theme, selected: store.theme == theme) {
                        withAnimation(Motion.quick) { store.theme = theme }
                    }
                }
            }
            .padding(.vertical, 6)
        }
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
                    Image(systemName: "sparkles").font(.uiTitle2.weight(.semibold)).foregroundStyle(.white)
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
                    Text(theme.name).font(.uiCallout.weight(selected ? .semibold : .regular))
                }
            }
        }
        .buttonStyle(.soft)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsGroup(title: "Responses") {
            SettingsRow(title: "Temperature") {
                Slider(value: $settings.temperature, in: 0...1.5, step: 0.05).frame(width: 300)
                Text(String(format: "%.2f", settings.temperature)).font(.uiCallout).monospacedDigit().foregroundStyle(Forge.dim).frame(width: 36, alignment: .trailing)
            }
            SettingsRow(title: "Max response length") {
                Picker("Max response length", selection: $settings.maxResponseTokens) {
                    Text("Unlimited").tag(0)
                    ForEach([256, 512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0) tokens").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(title: "Default context window") {
                Picker("Default context window", selection: $settings.contextLength) {
                    ForEach(AppSettings.contextOptions, id: \.self) { Text("\(Format.tokens($0)) tokens").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsToggle(title: "Let thinking models reason before answering", isOn: $settings.thinkingEnabled)
            SettingsToggle(title: "Free memory when switching models (Ollama)", isOn: $settings.unloadOnSwitch)
        }
        SettingsGroup(title: "System instructions") {
            TextEditor(text: $settings.systemPrompt)
                .font(.uiCallout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("Reset to Default") { settings.systemPrompt = AppSettings.defaultSystemPrompt }
                    .disabled(settings.systemPrompt == AppSettings.defaultSystemPrompt)
            }
        }
    }
}

private struct FrameworkSettings: View {
    var body: some View {
        SettingsGroup(footer: "All frameworks run on this Mac. Ollama and MLX LM support one-click downloads and per-chat context windows, and the app starts MLX LM when you choose it. LM Studio and llama.cpp use their own OpenAI-compatible servers.") {
            ForEach(BackendKind.allCases) { kind in
                FrameworkRow(kind: kind)
            }
        }
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
            Image(systemName: kind.symbol).foregroundStyle(Forge.dim).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.uiBody.weight(.medium))
                Text(kind.tagline).font(.uiCaption).foregroundStyle(Forge.dim)
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
            .frame(width: 64)
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

/// The harness in chat: whether it's on, how it may use the web, and the choices behind it.
private struct HarnessSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackendController.self) private var backends

    var body: some View {
        @Bindable var settings = settings
        SettingsGroup(footer: "With it on, code runs the math, checks each reply and sends it back if it's wrong. With it off you get the plain model. You can switch at any point: under the message box in a chat, and under the question on Home."
                      + (backends.kind.supportsTools ? "" : " It works with Ollama and MLX LM, so it's resting while \(backends.kind.displayName) is chosen.")) {
            SettingsToggle(title: "Use the harness in chat", isOn: $settings.harnessEnabled)
        }
        SettingsGroup(footer: "A lookup sends search terms, written from your message, and the addresses of the pages it reads. The sites see those and your IP address, and nothing else from your chat. Pages come from a list of \(TrustedSites.all.count) trusted sites, and every search and page is listed with the reply.") {
            WebLookupsPicker()
        }
        if Edition.current.isLab {
            SettingsGroup(title: "For comparing",
                          footer: "Every design of the harness stays in the app, so you can compare them on your own models in Tests. In \(HarnessVersion.loop.short) and \(HarnessVersion.thinking.short), rounds are how many times it may go back and try again when a reply fails its checks. In \(HarnessVersion.council.short), they're how many times the three agents may go round the shared notes. More rounds can fix more replies, and take longer.") {
                SettingsRow(title: "Version") {
                    Picker("Version", selection: $settings.harnessVersion) {
                        ForEach(HarnessVersion.allCases) { version in
                            Text(version == .recommended ? "\(version.title) (recommended)" : version.title).tag(version)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Rounds per task") {
                    Picker("Rounds per task", selection: $settings.harnessMaxRounds) {
                        ForEach(AppSettings.harnessRoundOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

private struct SafetySettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsGroup {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.good).font(.uiTitle2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verified models only").font(.uiHeadline)
                    Text("By default you can only chat with models from the curated catalog: official open weights from well-known publishers, used by millions, distributed as GGUF tensors with no executable code.")
                        .font(.uiCallout)
                        .foregroundStyle(Forge.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        SettingsGroup(footer: "Only enable this if you trust where a model came from. Unverified models show an orange shield.") {
            SettingsToggle(title: "Allow unverified models", isOn: $settings.allowUnverifiedModels)
        }
        SettingsGroup(title: "Privacy") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(Palette.accent).font(.uiTitle2)
                Text("Your chats are saved only on this Mac. The app goes online for three things: downloading a model you choose, through your framework; updating when you press Update; and the harness's web lookups, which ask first unless you've chosen otherwise in Settings › Harness. A lookup sends search terms, written from your message, and page addresses.")
                    .font(.uiCallout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct UpdateSettings: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        SettingsGroup(footer: "Downloads the newest code from GitHub, builds it on this Mac and restarts the app. It also updates Ollama, MLX LM and llama.cpp when Homebrew installed them. It goes online only when you press Update, and waits for a running test, reply or download before it restarts anything. Your chats and settings stay as they are, and if anything goes wrong this copy keeps working.") {
            SettingsRow(title: "This version") {
                // The version says which release this is, and the commit says exactly which code.
                Text([AppUpdater.version, AppUpdater.commit.map { String($0.prefix(7)) } ?? "development build"]
                    .compactMap { $0 }.joined(separator: " · ")).font(.geistMono(13)).foregroundStyle(Forge.dim)
            }
            HStack(spacing: 10) {
                status
                Spacer()
                Button("Update") { updater.update() }
                    .disabled(!updater.canUpdate)
            }
            if Edition.isLabBuild {
                Text("This is Prometheus Lab, the private app. Update builds the public app, so it is off here: build the lab again from the private code with `make install-lab`.")
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !updater.changes.isEmpty {
            SettingsGroup(title: "What's new") {
                ForEach(updater.changes, id: \.self) { Text($0).font(.uiCallout).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.phase {
        case .idle:
            Text("Press Update to get the newest version.")
                .font(.uiCallout)
                .foregroundStyle(Forge.dim)
        case .working(let stage):
            progress(stage)
        case .waitingForWork(let text):
            progress(text)
        case .upToDate:
            Label("You're on the newest version.", systemImage: "checkmark.circle.fill")
                .font(.uiCallout)
                .foregroundStyle(Palette.good)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.uiCallout)
                    .foregroundStyle(Palette.critical)
                Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([AppUpdater.logURL]) }
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.uiCallout)
        }
    }
}

private struct DataSettings: View {
    @Environment(ChatController.self) private var chat
    @State private var confirmClear = false

    var body: some View {
        SettingsGroup(title: "Conversations") {
            SettingsRow(title: "Saved chats") {
                Text("\(chat.conversations.count)").font(.uiBody).monospacedDigit().foregroundStyle(Forge.dim)
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConversationStore().fileURL])
                }
                Spacer()
                Button("Delete All Chats…", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Delete all chats?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { chat.clearAll() }
        } message: {
            Text("This permanently removes every conversation from this Mac.")
        }
    }
}
