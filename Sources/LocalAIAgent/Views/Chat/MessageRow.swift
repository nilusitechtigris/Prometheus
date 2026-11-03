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
                    HStack(alignment: .center, spacing: 10) {
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

/// One card of per-reply stats: speed · time (first token + generation) · tokens (output + thinking).
struct MetricsFooter: View {
    let metrics: GenerationMetrics

    var body: some View {
        HStack(spacing: 8) {
            // One row when there's room, two rows when the chat column is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    speed
                    divider
                    time
                    divider
                    tokens
                }
                .fixedSize()
                .statsCard()

                Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow { speed; time }
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .gridCellColumns(2)
                    GridRow { tokens.gridCellColumns(2) }
                }
                .fixedSize()
                .statsCard()
            }
            if metrics.stopReason == "stopped" {
                Chip(text: "Stopped", symbol: "stop.circle")
            } else if metrics.stopReason == "length" {
                Chip(text: "Hit length limit", symbol: "scissors")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 14)
            .padding(.top, 2)
    }

    @ViewBuilder private var speed: some View {
        let tps = metrics.tokensPerSecond
        StatSegment(label: "Speed", symbol: "speedometer", help: "Generation speed") {
            StatusDot(level: Thresholds.tokensPerSecond.level(tps), size: 6)
            Text(Format.rate(tps))
            Text("tok/s").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// Waiting for the first token, then generating (thinking + answer summed).
    @ViewBuilder private var time: some View {
        let parts = timeParts
        let total = parts.reduce(0) { $0 + $1.share }
        StatSegment(label: "Time", symbol: "stopwatch",
                    total: parts.count > 1 ? Format.seconds(total) : nil, help: timeHelp) {
            SplitValues(parts: parts)
        }
    }

    private var timeParts: [SplitPart] {
        var parts: [SplitPart] = []
        if let ttft = metrics.timeToFirstToken {
            // The wait segment keeps its green / yellow / red health colour.
            let level = Thresholds.timeToFirstToken.level(ttft)
            parts.append(SplitPart(value: Format.seconds(ttft), label: "first token",
                                   color: level == .unknown ? .secondary : level.color, share: ttft))
        }
        if let generation = metrics.generationTime {
            parts.append(SplitPart(value: Format.seconds(generation), label: "generation",
                                   color: Palette.accent2, share: generation))
        }
        return parts
    }

    @ViewBuilder private var tokens: some View {
        let output = metrics.outputTokens ?? 0
        let thinking = metrics.thinkingTokens ?? 0
        StatSegment(label: "Tokens", symbol: "number",
                    total: thinking > 0 ? "\(output + thinking)" : nil,
                    help: "\(output) output tokens (the answer)" + (thinking > 0 ? " + \(thinking) thinking tokens (reasoning)" : "")) {
            SplitValues(parts: tokenParts)
        }
    }

    private var tokenParts: [SplitPart] {
        let output = metrics.outputTokens ?? 0
        let thinking = metrics.thinkingTokens ?? 0
        var parts = [SplitPart(value: "\(output)", label: "output", color: Palette.accent2, share: Double(output))]
        if thinking > 0 {
            parts.append(SplitPart(value: "\(thinking)", label: "thinking", color: Palette.accent, share: Double(thinking)))
        }
        return parts
    }

    private var timeHelp: String {
        var lines: [String] = []
        if let ttft = metrics.timeToFirstToken {
            var detail: [String] = []
            if let p = metrics.promptDuration { detail.append("reading the prompt \(Format.seconds(p))") }
            if let load = metrics.loadDuration, load > 0.5 { detail.append("model loading \(Format.seconds(load))") }
            lines.append("First token: \(Format.seconds(ttft))" + (detail.isEmpty ? "" : " (incl. \(detail.joined(separator: ", ")))"))
        }
        if let generation = metrics.generationTime {
            var line = "Generation: \(Format.seconds(generation))"
            if let thinking = metrics.thinkingTime, let output = metrics.outputTime {
                line += " (\(Format.seconds(thinking)) thinking + \(Format.seconds(output)) answer)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// Small caption (and optional total) over a value — the building block of the stats card.
private struct StatSegment<Value: View>: View {
    let label: String
    let symbol: String
    var total: String?
    let help: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
                if let total {
                    Text("· \(total)").font(.system(size: 9.5, weight: .semibold)).monospacedDigit().opacity(0.75)
                }
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                value
            }
            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .help(help)
    }
}

private struct SplitPart {
    let value: String
    let label: String
    let color: Color
    let share: Double
}

/// "● 37 output  ● 379 thinking" on one line, with a proportion bar underneath when there's more than one part.
private struct SplitValues: View {
    let parts: [SplitPart]

    var body: some View {
        let values = HStack(spacing: 10) {
            ForEach(parts.indices, id: \.self) { i in
                LabeledValue(value: parts[i].value, label: parts[i].label, color: parts[i].color)
            }
        }
        if parts.count > 1 {
            // The bar sits under the values and matches their width exactly.
            values
                .padding(.bottom, 8)
                .overlay(alignment: .bottomLeading) { SplitBar(parts: parts) }
        } else {
            values
        }
    }
}

private struct LabeledValue: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Text(value)
            Text(label).font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
        }
    }
}

private struct SplitBar: View {
    let parts: [SplitPart]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let total = max(parts.reduce(0) { $0 + $1.share }, 0.0001)
            let available = geo.size.width - gap * CGFloat(parts.count - 1)
            HStack(spacing: gap) {
                ForEach(parts.indices, id: \.self) { i in
                    let width = max(available * CGFloat(parts[i].share / total), parts[i].share > 0 ? 3 : 0)
                    Capsule().fill(parts[i].color.opacity(0.85)).frame(width: width)
                }
            }
        }
        .frame(height: 4)
    }
}

private extension View {
    func statsCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shape.fill(Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
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
