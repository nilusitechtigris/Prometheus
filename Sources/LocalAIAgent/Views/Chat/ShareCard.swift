import AppKit
import SwiftUI

/// One picture of a side by side reply, made for posting: the message, both replies, what code checked, and
/// the model and Mac it ran on. It always says these were single runs, because that's what they were.
enum ShareCard {
    struct Content {
        let question: String
        let plain: String
        let harness: String
        let verdict: CompareVerdict
        let model: String
        let machine: String
        let date: Date
        var plainSeconds: Double?
        var harnessSeconds: Double?
    }

    static let size = CGSize(width: 800, height: 450)

    @MainActor
    static func png(_ content: Content) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(content: content).frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// A reply as plain text that fits the card: no Markdown marks, no blank lines, and cut with an ellipsis.
    static func plainText(_ reply: String, limit: Int = 330) -> String {
        var text = reply
        for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard joined.count > limit else { return joined }
        // What a long reply settles on is usually at its end, so the card keeps both ends.
        let head = joined.prefix(limit * 2 / 5), tail = joined.suffix(limit * 3 / 5)
        return "\(head.trimmingCharacters(in: .whitespacesAndNewlines)) …\n… \(tail.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    @MainActor
    static func copy(_ png: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    /// Asks where to save the picture. Returns false if the person cancelled or it couldn't be written.
    @MainActor
    static func save(_ png: Data, date: Date) -> Bool {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HHmm"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Prometheus side by side \(format.string(from: date)).png"
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return (try? png.write(to: url, options: .atomic)) != nil
    }
}

private struct ShareCardView: View {
    let content: ShareCard.Content

    private func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .geist(size, weight: weight) }

    /// The same everywhere, since the picture is for other people to read.
    private static let day: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.dateFormat = "d MMM yyyy"
        return format
    }()

    var body: some View {
        ZStack {
            // The window's own look: the theme's ground, lit from where the flame stands beside the name.
            Forge.black
            RadialGradient(colors: [Palette.glow.opacity(0.2), .clear], center: UnitPoint(x: 0.06, y: 0), startRadius: 0, endRadius: 420)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let flame = Art.flame(for: ThemeStore.shared.theme) {
                        Image(nsImage: flame).resizable().scaledToFit().frame(height: 26)
                    }
                    Text("PROMETHEUS").font(text(13, .bold)).kerning(2.2).foregroundStyle(.white)
                    Spacer()
                    Text("Same model, same Mac").font(text(11, .medium)).foregroundStyle(Palette.accent)
                }
                Text(content.question)
                    .font(text(19, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    side("Plain model", content.plain, seconds: content.plainSeconds, tint: Color.white.opacity(0.55), border: Color.white.opacity(0.22))
                    side("With the harness", content.harness, seconds: content.harnessSeconds, tint: Palette.accent, border: Palette.accent.opacity(0.7))
                }
                .frame(maxHeight: .infinity, alignment: .top)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: content.verdict.harnessAhead ? "checkmark.seal.fill" : "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(content.verdict.harnessAhead ? Palette.accent : Color.white.opacity(0.6))
                    Text(content.verdict.text).font(text(13, .medium)).foregroundStyle(.white).lineLimit(2)
                }
                HStack {
                    Text("\(content.model) · \(content.machine) · one run each · \(Self.day.string(from: content.date))")
                    Spacer()
                    Text("github.com/nilusitechtigris/Prometheus")
                }
                .font(text(10))
                .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
        .environment(\.colorScheme, .dark)
    }

    private func side(_ title: String, _ reply: String, seconds: Double?, tint: Color, border: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(text(11, .semibold)).foregroundStyle(tint)
                Spacer()
                if let seconds { Text(Format.seconds(seconds)).font(text(10)).foregroundStyle(Color.white.opacity(0.5)) }
            }
            Text(ShareCard.plainText(reply))
                .font(text(13))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}
