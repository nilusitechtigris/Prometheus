import SwiftUI

/// The chats, docked beside the conversation: pick, search, rename and delete, one or several. It belongs to the Chat
/// page. The rail's Chat button, ⌥⌘2 and the button at its top open and collapse it.
struct ChatsColumn: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var deleting: Conversation?
    @State private var confirmDeletePicked = false
    @FocusState private var searchFocused: Bool

    static let width: CGFloat = 256

    /// A click on empty space keeps the open chat, so the conversation never vanishes by accident.
    private var selection: Binding<UUID?> {
        Binding(get: { chat.selectedID }, set: { id in
            if let id { chat.selectedID = id }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if ui.selectingChats { selectionBar }
            Forge.rule()
            list
            if ui.selectingChats { deleteBar }
        }
        .frame(width: Self.width)
        .background(Forge.panel)
        .task(id: ui.wantsChatSearchFocus) {
            guard ui.wantsChatSearchFocus else { return }
            ui.wantsChatSearchFocus = false
            searchFocused = true
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
        .confirmationDialog("Delete \(chatCount(picked.count))?", isPresented: $confirmDeletePicked, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                chat.delete(picked)
                endSelecting()
            }
        } message: {
            Text("These conversations will be removed from this Mac. This can't be undone.")
        }
    }

    // MARK: Selecting

    /// The chats showing right now, so a search narrows what Select All and Delete touch.
    private var visible: Set<UUID> { Set(groups.flatMap(\.items).map(\.id)) }
    private var picked: Set<UUID> { ui.pickedChats.intersection(visible) }

    private func chatCount(_ count: Int) -> String { "\(count) chat\(count == 1 ? "" : "s")" }

    private func endSelecting() {
        ui.pickedChats = []
        ui.selectingChats = false
    }

    private func toggle(_ id: UUID) {
        if ui.pickedChats.contains(id) { ui.pickedChats.remove(id) } else { ui.pickedChats.insert(id) }
    }

    private var selectionBar: some View {
        let visible = self.visible, picked = self.picked
        return HStack(spacing: 14) {
            barButton("Select All", enabled: !visible.isEmpty && picked.count < visible.count) { ui.pickedChats.formUnion(visible) }
            barButton("Deselect All", enabled: !picked.isEmpty) { ui.pickedChats = [] }
            Spacer()
            barButton("Done", enabled: true, action: endSelecting)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func barButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.uiCaption.weight(.medium))
            .foregroundStyle(enabled ? Palette.accent : Forge.faint)
            .disabled(!enabled)
    }

    private var deleteBar: some View {
        let count = picked.count
        return Button {
            confirmDeletePicked = true
        } label: {
            Label(count == 0 ? "Select chats to delete" : "Delete \(chatCount(count))", systemImage: "trash")
                .font(.uiCallout.weight(.medium))
                .foregroundStyle(count == 0 ? Forge.faint : Palette.critical)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Palette.critical.opacity(count == 0 ? 0.05 : 0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Forge.label("Chats")
            Spacer()
            Button {
                chat.newConversation()
                ui.composerFocusRequest += 1
            } label: {
                Label("New Chat", systemImage: "square.and.pencil").labelStyle(.iconOnly)
            }
            .help("New chat (⌘N)")
            Button {
                if ui.selectingChats { endSelecting() } else { ui.selectingChats = true }
            } label: {
                Label("Select", systemImage: ui.selectingChats ? "checkmark.circle.fill" : "checkmark.circle").labelStyle(.iconOnly)
            }
            .help("Select several chats to delete them")
            .disabled(chat.conversations.isEmpty)
            Button {
                withAnimation(.snappy) { settings.chatsOpen = false }
            } label: {
                Label("Collapse", systemImage: "sidebar.leading").labelStyle(.iconOnly)
            }
            .help("Collapse the chats (⌥⌘2)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        @Bindable var ui = ui
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Forge.dim)
            TextField("Search chats", text: $ui.chatSearch)
                .textFieldStyle(.plain)
                .font(.uiCallout)
                .focused($searchFocused)
                .onExitCommand {
                    ui.chatSearch = ""
                    searchFocused = false
                }
            if !ui.chatSearch.isEmpty {
                Button {
                    ui.chatSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Forge.dim)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .glassPanel(cornerRadius: 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var list: some View {
        // In Select mode a click ticks a chat instead of opening it.
        if ui.selectingChats {
            List { listContent }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
        } else {
            List(selection: selection) { listContent }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var listContent: some View {
            if chat.conversations.isEmpty {
                placeholder("No chats yet. Press ⌘N to start one.")
            } else if groups.isEmpty {
                placeholder("No chats match “\(ui.chatSearch)”.")
            }
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.items) { conv in
                        if ui.selectingChats {
                            selectableRow(conv)
                        } else {
                            ConversationRow(conversation: conv, isStreaming: isStreaming(conv), onDelete: { deleting = conv })
                                .tag(conv.id)
                                .contextMenu {
                                    Button("Rename…") { renameText = conv.title; renaming = conv }
                                    Button("Select…") {
                                        ui.selectingChats = true
                                        ui.pickedChats = [conv.id]
                                    }
                                    Divider()
                                    Button("Delete Chat", role: .destructive) { deleting = conv }
                                }
                        }
                    }
                } header: {
                    Forge.label(group.title, color: Forge.dim)
                }
            }
    }

    private func selectableRow(_ conv: Conversation) -> some View {
        let isPicked = ui.pickedChats.contains(conv.id)
        return Button {
            toggle(conv.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isPicked ? Palette.accent : Forge.faint)
                ConversationRow(conversation: conv, isStreaming: isStreaming(conv))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(conv.title), \(isPicked ? "selected" : "not selected")")
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.uiCallout).foregroundStyle(.secondary).selectionDisabled()
    }

    private func isStreaming(_ conv: Conversation) -> Bool {
        guard let id = chat.streamingMessageID else { return false }
        return conv.messages.last?.id == id
    }

    private struct Group { let title: String; let items: [Conversation] }

    private var groups: [Group] {
        let search = ui.chatSearch
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
    /// Shows a trash button while the pointer is over the row.
    var onDelete: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .lineLimit(1)
                        .font(.uiCallout)
                    if isStreaming {
                        ProgressView().controlSize(.mini)
                    }
                }
                if !conversation.preview.isEmpty {
                    Text(conversation.preview)
                        .lineLimit(1)
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if hovering, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Forge.dim)
                }
                .buttonStyle(.plain)
                .help("Delete this chat")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
