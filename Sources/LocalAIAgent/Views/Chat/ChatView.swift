import SwiftUI

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
