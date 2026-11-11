import SwiftUI

/// The Chat page's Ask face: a bar across the top, the chats at the left, and the conversation.
struct ChatPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBar()
            Forge.rule()
            HStack(spacing: 0) {
                if settings.chatsOpen {
                    HStack(spacing: 0) {
                        ChatsColumn()
                        Forge.rule(vertical: true)
                    }
                    .transition(.move(edge: .leading))
                }
                ChatView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The list slides in from behind the edge, not over the bar above it.
            .clipped()
            .animation(Motion.quick, value: settings.chatsOpen)
        }
    }
}

/// One line, as tall as Dev's top bar: the Ask | Dev switch, then the button that shows and hides the list
/// of chats. The list could be hidden from its own header, and then only leaving the page brought it back.
private struct ChatTopBar: View {
    @Environment(ChatController.self) private var chat
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let open = settings.chatsOpen
        HStack(spacing: 8) {
            // The switch is drawn over this corner (see `MainPage`). The bar leaves its room free.
            Color.clear.frame(width: ChatModeSwitch.width, height: Forge.pillHeight)
            Button {
                withAnimation(Motion.quick) { settings.chatsOpen.toggle() }
            } label: {
                pill("sidebar.leading", "Chats", lit: open)
            }
            .buttonStyle(.soft)
            .glassCapsule(interactive: true)
            .help(open ? "Hide the list of chats (⌥⌘2)" : "Show the list of chats (⌥⌘2)")
            .accessibilityLabel(open ? "Hide chats" : "Show chats")
            // With the list hidden, its New Chat button is hidden too, so the bar has one.
            if !open {
                Button {
                    chat.newConversation()
                    ui.composerFocusRequest += 1
                } label: {
                    pill("square.and.pencil", "New chat", lit: false)
                }
                .buttonStyle(.soft)
                .glassCapsule(interactive: true)
                .help("New chat (⌘N)")
                .transition(.opacity)
            }
            if let title = chat.selected.flatMap({ $0.messages.isEmpty ? nil : $0.title }) {
                Text(title)
                    .font(.uiCallout)
                    .foregroundStyle(Forge.dim)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, ChatModeSwitch.barInset)
        .frame(height: ChatModeSwitch.barHeight)
        .animation(Motion.quick, value: open)
    }

    private func pill(_ symbol: String, _ title: String, lit: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            Text(title)
        }
        .font(.uiCallout.weight(lit ? .semibold : .regular))
        .foregroundStyle(lit ? Palette.accent : Forge.ink)
        .padding(.horizontal, 11)
        .frame(height: Forge.pillHeight)
        .contentShape(Capsule(style: .circular))
    }
}

struct ChatView: View {
    @Environment(ChatController.self) private var chat

    /// The open chat, or nil for the empty page. The first message moves from one to the other.
    private var openChat: Conversation? {
        chat.selected.flatMap { $0.messages.isEmpty ? nil : $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageSwap(value: openChat?.id) {
                if let openChat {
                    MessageList(conversation: openChat)
                } else {
                    EmptyChatView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ComposerView()
        }
    }
}

private struct MessageList: View {
    @Environment(ChatController.self) private var chat
    let conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if chat.trimmedMessageCount > 0 {
                        Label("\(chat.trimmedMessageCount) older message\(chat.trimmedMessageCount == 1 ? "" : "s") didn't fit the context window and weren't sent. Increase the context window to include them.",
                              systemImage: "text.badge.minus")
                            .font(.uiCaption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message,
                                   isStreaming: message.id == chat.streamingMessageID,
                                   isLast: message.id == conversation.messages.last?.id)
                            .id(message.id)
                            .transition(.arrive)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                // On the count, so a streaming reply's text isn't animated as it comes in.
                .animation(Motion.quick, value: conversation.messages.count)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: scrollKey) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: conversation.id) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Changes whenever new text streams in or a message is added.
    private var scrollKey: Int {
        let last = conversation.messages.last
        return conversation.messages.count &* 1_000_003 &+ (last?.content.count ?? 0) &+ (last?.thinking?.count ?? 0)
    }
}
