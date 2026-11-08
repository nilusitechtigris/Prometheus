import AppKit
import SwiftUI

/// One picture of a comparison: the request and the model, then both pages side by side at full length,
/// each with its score and checks, so nothing is cut off and nothing needs scrolling.
enum DevCompareShot {
    @MainActor
    static func png(comparison: DevComparison, off: NSImage?, on: NSImage?) -> Data? {
        let width = min(max(off?.size.width ?? 0, on?.size.width ?? 0, 480), 1_600)
        let tallest = max(height(off, width: width), height(on, width: width))
        let renderer = ImageRenderer(content: DevCompareShotView(comparison: comparison, off: off, on: on, pageWidth: width))
        // Twice the pixels for a sharp picture, but no more than about 4,000 across or 12,000 down, so a page
        // filling a wide window or a very long one doesn't make a picture too big to share.
        let across = width * 2 + 100, down = tallest + 300
        renderer.scale = max(min(2, 4_000 / across, 12_000 / down), 0.5)
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func height(_ image: NSImage?, width: CGFloat) -> CGFloat {
        guard let image, image.size.width > 0 else { return 0 }
        return image.size.height * width / image.size.width
    }
}

private struct DevCompareShotView: View {
    let comparison: DevComparison
    let off: NSImage?
    let on: NSImage?
    let pageWidth: CGFloat

    /// Text sized for pages about 700 wide, and larger beside wider ones.
    private var k: CGFloat { max(1, pageWidth / 700) }
    private func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .geist(size * k, weight: weight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(comparison.request.split(separator: "\n").first.map(String.init) ?? comparison.request)
                    .font(text(22, .semibold))
                    .foregroundStyle(Forge.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(details).font(text(14)).foregroundStyle(Forge.dim)
            }
            .frame(width: pageWidth * 2 + 28, alignment: .leading)
            HStack(alignment: .top, spacing: 28) {
                column(comparison.off, image: off)
                column(comparison.on, image: on)
            }
        }
        .padding(36)
        .background(Forge.black)
        .environment(\.colorScheme, .dark)
    }

    private var details: String {
        var parts = [comparison.model, comparison.framework]
        if comparison.context > 0 { parts.append("\(comparison.context / 1_024)K context") }
        parts.append(comparison.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private func column(_ side: DevCompareSide, image: NSImage?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(side.harness ? "Harness on" : "Harness off")
                    .font(text(18, .semibold))
                    .foregroundStyle(side.harness ? Palette.accent : Forge.ink)
                Text(side.harness ? "plans, writes each file, tries it and fixes it" : "one reply, saved as it came")
                    .font(text(13))
                    .foregroundStyle(Forge.faint)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if side.total > 0 {
                    Text("\(side.passed)/\(side.total)")
                        .font(.geistMono(20 * k, weight: .semibold))
                        .foregroundStyle(side.passed == side.total ? Palette.good : side.passed * 2 >= side.total ? Palette.warning : Palette.critical)
                }
            }
            page(side, image: image)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(side.score) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: line.passed == true ? "checkmark.circle.fill" : line.passed == false ? "xmark.circle.fill" : "minus.circle")
                            .foregroundStyle(line.passed == true ? Palette.good : line.passed == false ? Palette.critical : Forge.faint)
                        Text(line.name).foregroundStyle(line.passed == nil ? Forge.faint : Forge.ink)
                        if let detail = line.detail, line.passed != true {
                            Text(detail).foregroundStyle(Forge.faint).lineLimit(1)
                        }
                    }
                    .font(text(13))
                }
                if !summary(side).isEmpty {
                    Text(summary(side)).font(text(11.5)).foregroundStyle(Forge.faint).padding(.top, 3)
                }
            }
        }
        .frame(width: pageWidth, alignment: .leading)
    }

    @ViewBuilder
    private func page(_ side: DevCompareSide, image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: pageWidth, height: DevCompareShot.height(image, width: pageWidth))
                .background(Color.white)
        } else {
            Text(side.page != nil ? "The page wasn't running, so there's no picture of it." : side.text.isEmpty ? "Nothing to show." : side.text)
                .font(text(13))
                .foregroundStyle(Forge.dim)
                .lineLimit(40)
                .frame(width: pageWidth - 36, alignment: .topLeading)
                .padding(18)
                .background(Forge.card)
        }
    }

    private func summary(_ side: DevCompareSide) -> String {
        var parts: [String] = []
        if let seconds = side.seconds { parts.append(Format.seconds(seconds)) }
        if let calls = side.calls { parts.append("\(calls) model \(calls == 1 ? "call" : "calls")") }
        let files = side.files.filter { !$0.path.hasPrefix(DevKit.cssName) }
        if !files.isEmpty {
            parts.append("\(files.count) \(files.count == 1 ? "file" : "files"), \(files.reduce(0) { $0 + $1.lines }) lines")
        }
        return parts.joined(separator: " · ")
    }
}
