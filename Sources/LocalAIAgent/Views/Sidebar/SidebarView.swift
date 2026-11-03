import SwiftUI

struct SidebarView: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui
    @State private var search = ""
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var deleting: Conversation?

    var body: some View {
        @Bindable var chat = chat

        List(selection: $chat.selectedID) {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { conv in
                        ConversationRow(conversation: conv, isStreaming: isStreaming(conv))
                            .tag(conv.id)
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
        .overlay {
            if chat.conversations.isEmpty {
                ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Press ⌘N to start one."))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
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
