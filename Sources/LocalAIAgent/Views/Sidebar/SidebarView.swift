import SwiftUI

struct SidebarView: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @State private var search = ""
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var deleting: Conversation?

    /// Selectable sidebar rows: the two test dashboards, then the chats.
    private enum Item: Hashable { case chat(UUID), modelTest, hardwareTest }

    private var selection: Binding<Item?> {
        Binding(get: {
            switch ui.destination {
            case .chat: return chat.selectedID.map(Item.chat)
            case .modelTest: return .modelTest
            case .hardwareTest: return .hardwareTest
            }
        }, set: { item in
            switch item {
            case .chat(let id)?:
                chat.selectedID = id
                ui.destination = .chat
            case .modelTest?: ui.destination = .modelTest
            case .hardwareTest?: ui.destination = .hardwareTest
            case nil: if ui.destination == .chat { chat.selectedID = nil }
            }
        })
    }

    var body: some View {
        List(selection: selection) {
            Section("Telemetry") {
                ForEach(TelemetryWidgetKind.allCases) { WidgetRow(kind: $0) }
            }
            Section("Tests") {
                TestRow(title: "Model Test", symbol: "checkmark.seal.fill", isRunning: lab.modelProgress != nil,
                        status: lab.latestModelResult(for: lab.testModel(in: backends)?.id).map { Format.percent($0.score) })
                    .tag(Item.modelTest)
                TestRow(title: "Hardware Test", symbol: "cpu.fill", isRunning: lab.hardwareProgress != nil,
                        status: lab.hardwareResults.first?.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" })
                    .tag(Item.hardwareTest)
            }
            if chat.conversations.isEmpty {
                Section("Chats") {
                    Text("No chats yet. Press ⌘N to start one.").font(.callout).foregroundStyle(.secondary)
                }
            } else if groups.isEmpty {
                Section("Chats") {
                    Text("No chats match “\(search)”.").font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { conv in
                        ConversationRow(conversation: conv, isStreaming: isStreaming(conv))
                            .tag(Item.chat(conv.id))
                            .contextMenu {
                                Button("Rename…") { renameText = conv.title; renaming = conv }
                                Divider()
                                Button("Delete Chat", role: .destructive) { deleting = conv }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search chats")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                BrandWordmark(size: 17)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BackendStatusFooter()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    ui.destination = .chat
                    chat.newConversation()
                    ui.composerFocusRequest += 1
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New chat (⌘N)")
            }
        }
        .alert("Rename Chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") { if let c = renaming { chat.rename(c.id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let c = deleting { chat.delete(c.id) }; deleting = nil }
        } message: {
            Text("This conversation will be removed from this Mac.")
        }
    }

    private func isStreaming(_ conv: Conversation) -> Bool {
        guard let id = chat.streamingMessageID else { return false }
        return conv.messages.last?.id == id
    }

    private struct Group { let title: String; let items: [Conversation] }

    private var groups: [Group] {
        let filtered = chat.conversations.filter { conv in
            search.isEmpty || conv.title.localizedCaseInsensitiveContains(search)
                || conv.messages.contains { $0.content.localizedCaseInsensitiveContains(search) }
        }
        let cal = Calendar.current
        let now = Date()
        var buckets: [(String, [Conversation])] = [("Today", []), ("Yesterday", []), ("Previous 7 Days", []), ("Previous 30 Days", []), ("Older", [])]
        for conv in filtered {
            let d = conv.updatedAt
            let idx: Int
            if cal.isDateInToday(d) { idx = 0 }
            else if cal.isDateInYesterday(d) { idx = 1 }
            else if let days = cal.dateComponents([.day], from: d, to: now).day, days < 7 { idx = 2 }
            else if let days = cal.dateComponents([.day], from: d, to: now).day, days < 30 { idx = 3 }
            else { idx = 4 }
            buckets[idx].1.append(conv)
        }
        return buckets.filter { !$0.1.isEmpty }.map { Group(title: $0.0, items: $0.1) }
    }
}

/// Shows or hides one floating telemetry widget. A toggle, not a destination, so it's a button row
/// rather than a selectable one.
private struct WidgetRow: View {
    let kind: TelemetryWidgetKind
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let open = ui.openWidgets.contains(kind)
        Button {
            TelemetryWidgetToggle(open: openWindow, dismiss: dismissWindow, ui: ui)(kind)
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(symbol: kind.symbol)
                    .symbolEffect(.bounce, value: open)
                Text(kind.title)
                Spacer()
                Text(open ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(open ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(open ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(open ? "Close the floating \(kind.title) widget" : "Open the \(kind.title) widget in a floating window")
        .accessibilityLabel("\(kind.title) widget, \(open ? "on" : "off")")
    }
}

private struct SidebarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct TestRow: View {
    let title: String
    let symbol: String
    let isRunning: Bool
    let status: String?

    var body: some View {
        HStack(spacing: 8) {
            SidebarIcon(symbol: symbol)
            Text(title)
            Spacer()
            if isRunning {
                ProgressView().controlSize(.mini)
            } else if let status {
                Text(status).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(conversation.title)
                    .lineLimit(1)
                    .font(.body)
                if isStreaming {
                    ProgressView().controlSize(.mini)
                }
            }
            if !conversation.preview.isEmpty {
                Text(conversation.preview)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct BackendStatusFooter: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 8) {
                StatusDot(level: level, size: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.medium))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                    .help("100% local — prompts and responses never leave this Mac")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var level: HealthLevel {
        switch backends.status {
        case .online: return .good
        case .checking: return .warning
        case .offline: return .critical
        }
    }

    private var title: String {
        switch backends.status {
        case .online(let v): return "\(backends.kind.displayName) \(v == "online" ? "" : v)".trimmingCharacters(in: .whitespaces)
        case .checking: return "Connecting to \(backends.kind.displayName)…"
        case .offline: return "\(backends.kind.displayName) offline"
        }
    }

    private var subtitle: String {
        let mem = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return "\(monitor.chipName) · \(mem) GB · runs offline"
    }
}
