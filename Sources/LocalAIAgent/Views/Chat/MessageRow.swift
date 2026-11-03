import AppKit
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLast: Bool

    var body: some View {
        switch message.role {
        case .user: UserBubble(message: message)
        case .assistant: AssistantMessage(message: message, isStreaming: isStreaming, isLast: isLast)
        case .system: EmptyView()
        }
    }
}

private struct UserBubble: View {
    let message: ChatMessage
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 120)
            CopyButton(text: message.content).opacity(hovering ? 1 : 0)
            Text(message.content)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Palette.accent.opacity(0.22), Palette.accent2.opacity(0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.accent.opacity(0.18), lineWidth: 0.5))
        }
        .onHover { hovering = $0 }
    }
}

private struct AssistantMessage: View {
    @Environment(ChatController.self) private var chat
    let message: ChatMessage
    let isStreaming: Bool
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandMark(size: 26)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.modelName.map { ModelCatalog.entry(matchingID: $0)?.displayName ?? $0 } ?? "Assistant")
                        .font(.callout.weight(.semibold))
                    Text(message.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let thinking = message.thinking, !thinking.isEmpty {
                    ThinkingView(text: thinking, isLive: isStreaming && message.content.isEmpty,
                                 duration: message.metrics?.thinkingDuration)
                }

                if isStreaming && message.content.isEmpty && (message.thinking ?? "").isEmpty {
                    WaitingIndicator()
                } else if !message.content.isEmpty {
                    MarkdownView(text: message.content)
                        .textSelection(.enabled)
                }

                if let error = message.errorText {
                    ErrorCard(text: error, canRetry: isLast) { chat.regenerate() }
                }

                if let metrics = message.metrics, !isStreaming {
                    HStack(spacing: 10) {
                        MetricsFooter(metrics: metrics)
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            CopyButton(text: message.content)
                            if isLast {
                                Button { chat.regenerate() } label: { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(.borderless)
                                    .help("Regenerate (⌘R)")
                                    .disabled(!chat.canSend)
                            }
                        }
                        .opacity(hovering || isLast ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering = $0 }
    }
}

private struct ThinkingView: View {
    let text: String
    let isLive: Bool
    let duration: Double?
    @State private var expanded: Bool?

    var body: some View {
        let isOpen = expanded ?? isLive
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { expanded = !isOpen }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .symbolEffect(.pulse, isActive: isLive)
                    Text(isLive ? "Thinking…" : (duration.map { "Thought for \(Format.seconds($0))" } ?? "Thoughts"))
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .imageScale(.small)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isOpen {
                ScrollView {
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 220)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.separator).frame(width: 2)
                }
            }
        }
    }
}

private struct WaitingIndicator: View {
    @Environment(ChatController.self) private var chat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var label: String {
        guard let live = chat.live else { return "Waiting…" }
        let waited = Date().timeIntervalSince(live.startedAt)
        return waited > 2 ? "Loading model & reading prompt…" : "Waiting for first token…"
    }
}

private struct ErrorCard: View {
    let text: String
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer(minLength: 0)
            if canRetry {
                Button("Retry", action: retry).controlSize(.small)
            }
        }
        .padding(10)
        .background(Palette.critical.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MetricsFooter: View {
    let metrics: GenerationMetrics

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if let ttft = metrics.timeToFirstToken {
                metric(symbol: "bolt.fill", text: "\(Format.seconds(ttft)) TTFT", level: Thresholds.timeToFirstToken.level(ttft))
                    .help("Time to first token")
            }
            if let task = metrics.taskTime {
                Chip(text: "\(Format.seconds(task)) task", symbol: "stopwatch")
                    .help(taskHelp)
            }
            if let tps = metrics.tokensPerSecond {
                metric(symbol: "speedometer", text: "\(Format.rate(tps)) tok/s", level: Thresholds.tokensPerSecond.level(tps))
                    .help("Generation speed")
            }
            if let out = metrics.outputTokens {
                Chip(text: "\(out) output", symbol: "text.bubble")
                    .help("\(out) output tokens — the visible answer")
            }
            if let thinking = metrics.thinkingTokens, thinking > 0 {
                Chip(text: "\(thinking) thinking", symbol: "brain.head.profile", tint: Palette.accent)
                    .help("\(thinking) thinking tokens — reasoning before the answer")
            }
            if let load = metrics.loadDuration, load > 0.5 {
                Chip(text: "load \(Format.seconds(load))", symbol: "arrow.down.circle")
                    .help("Time spent loading the model into memory (not part of task time)")
            }
            if metrics.stopReason == "stopped" {
                Chip(text: "stopped", symbol: "stop.circle")
            } else if metrics.stopReason == "length" {
                Chip(text: "hit length limit", symbol: "scissors")
            }
        }
    }

    private func metric(symbol: String, text: String, level: HealthLevel) -> some View {
        HStack(spacing: 5) {
            StatusDot(level: level, size: 6)
            Image(systemName: symbol).imageScale(.small)
            Text(text)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(level.color.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private var taskHelp: String {
        var lines = ["Task time: prompt processing + all token generation"]
        if let p = metrics.promptDuration {
            lines.append("Prompt processing: \(Format.seconds(p))\(metrics.promptTokens.map { " (\($0) tokens)" } ?? "")")
        }
        if let g = metrics.generationDuration {
            lines.append("Generation: \(Format.seconds(g))\(metrics.completionTokens.map { " (\($0) tokens)" } ?? "")")
        }
        if metrics.promptDuration == nil && metrics.generationDuration == nil {
            lines.append("Measured from sending to the last token")
        }
        return lines.joined(separator: "\n")
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}
