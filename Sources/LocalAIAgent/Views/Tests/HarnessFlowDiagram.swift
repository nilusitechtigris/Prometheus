import SwiftUI

/// What v3 does to a task, step by step: the four steps of its loop, with the task's type choosing the
/// route through step 2. v5 starts the same way. The Versions tab shows them all.
struct HarnessFlowDiagram: View {
    private struct Route: Identifiable {
        let kind: String
        let symbol: String
        let steps: [String]
        var id: String { kind }
    }

    private static let routes = [
        Route(kind: "Math or code", symbol: "function", steps: ["Writes a program", "Runs in the sandbox"]),
        Route(kind: "Fact", symbol: "magnifyingglass", steps: ["Searches 4 sources", "Picks passages"]),
        Route(kind: "Long text", symbol: "doc.text", steps: ["Follows the notes", "Picks key lines"]),
        Route(kind: "Writing or other", symbol: "pencil.line", steps: ["No tools needed"]),
    ]

    private static let guards: [(symbol: String, title: String, detail: String)] = [
        ("terminal", "Sandbox", "No internet, no other programs, no access to your files. Limits of 10 seconds, 1 GB of memory and 10 MB of files."),
        ("globe", "Trusted sites", "Pages open only from \(TrustedSites.all.count) trusted sites. Other sites, query strings and redirects away are refused in code."),
        ("line.3.horizontal.decrease.circle", "Injection guard", "Strips hidden text, images, encoded blobs and anything aimed at the assistant, then marks the rest as data."),
        ("checkmark.shield", "Reply filter", "After the web has been read, takes links to untrusted sites out of the reply, whatever the model wrote."),
    ]

    private let rowHeight: CGFloat = 52
    /// The routes, plus a row above them for the step's title.
    private var rows: Int { Self.routes.count + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                wide
                stacked
            }
            loopNote
            guardrails
            Text("This is \(HarnessVersion.loop.title), and \(HarnessVersion.council.title) prepares its shared notes the same way. The harness is off in chat until you pick a version with the Harness button under the message box. With it on, search terms go to Wikipedia, Stack Overflow, arXiv and MDN, pages come from the trusted sites, and every search and page is listed above the reply. Test questions are fixed, so a test sends nothing of yours. In a test the model can also call the web search, page reader, calculator and code runner itself. In chat, v2, v3 and v5 keep those tools with the harness, so a web page can't steer one while your chat is in view. In v1 the model holds them, so once it has read the web it can't search again and can only open links it was given. The guard is basic protection: it blocks common attacks like the ones in this test, not every possible one. Code runs on this Mac only.")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Layouts

    private var wide: some View {
        VStack(spacing: 0) {
            wideRow
            ZStack {
                LoopBackLine(leftInset: 310, rightInset: 147).stroke(Palette.accent.opacity(0.7), lineWidth: 1.5)
                Text("Failed a check? Go round again")
                    .font(.uiCaption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: Capsule())
                    .offset(y: 11)
            }
            .frame(height: 26)
        }
    }

    private var wideRow: some View {
        HStack(spacing: 0) {
            FlowEnd(title: "Your task", symbol: "text.bubble.fill")
            FlowArrow()
            StageNode(stage: .understand).frame(width: 126)
            FanLines(rows: rows, opening: true).stroke(Palette.accent.opacity(0.55), lineWidth: 1.5).frame(width: 40)
            routes
            FanLines(rows: rows, opening: false).stroke(Palette.accent.opacity(0.55), lineWidth: 1.5).frame(width: 40)
            StageNode(stage: .answer).frame(width: 126)
            FlowArrow()
            StageNode(stage: .check).frame(width: 126)
            FlowArrow()
            FlowEnd(title: "Reply", symbol: "checkmark.bubble.fill")
        }
        .frame(height: rowHeight * CGFloat(rows))
        .frame(minWidth: 1_040)
    }

    /// For narrow windows: the same steps, top to bottom.
    private var stacked: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                FlowEnd(title: "Your task", symbol: "text.bubble.fill")
                FlowArrow()
                StageNode(stage: .understand)
            }
            FlowArrow(down: true)
            routes
            FlowArrow(down: true)
            HStack(spacing: 0) {
                StageNode(stage: .answer)
                FlowArrow()
                StageNode(stage: .check)
                FlowArrow()
                FlowEnd(title: "Reply", symbol: "checkmark.bubble.fill")
            }
        }
    }

    private var routes: some View {
        VStack(spacing: 0) {
            StageTitle(stage: .act).frame(height: rowHeight)
            ForEach(Self.routes) { route in
                HStack(spacing: 0) {
                    Label(route.kind, systemImage: route.symbol)
                        .font(.uiCaption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 126, alignment: .leading)
                    ForEach(route.steps, id: \.self) { step in
                        FlowArrow(small: true)
                        Text(step)
                            .font(.uiCaption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 6)
                            // No ideal width, so the row never decides which layout fits.
                            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, minHeight: 30)
                            .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The way back from Check to Act.
    private var loopNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Check fails? Back to step 2").font(.uiCallout.weight(.semibold))
                Text("Code checks every reply: was it cut off, does it state the tool's result, is the answer in the sources, does it break a rule such as a word count or a banned letter. If it fails, the harness goes round again with what it learned, up to the rounds set in Settings › Safety. Each round can read the next page, search again, fix the program or rewrite one sentence. It stops when a round changes nothing, and it always keeps the best attempt so far.")
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var guardrails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guardrails, enforced in code at every step").font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                guardRow(Self.guards).frame(minWidth: 840)
                VStack(spacing: 10) {
                    guardRow(Array(Self.guards.prefix(2)))
                    guardRow(Array(Self.guards.suffix(2)))
                }
            }
        }
    }

    /// Cards of one width and height.
    private func guardRow(_ items: [(symbol: String, title: String, detail: String)]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(items, id: \.title) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.title, systemImage: item.symbol)
                        .font(.uiCallout.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Text(item.detail).font(.uiCaption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                // No ideal width, so the width of the text doesn't decide how many fit in a row.
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A step's number and name.
private struct StageTitle: View {
    let stage: HarnessStage

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(stage.rawValue + 1)")
                .font(.uiCaption.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.onAccent)
                .frame(width: 20, height: 20)
                .background(Palette.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title).font(.uiHeadline).lineLimit(1).minimumScaleFactor(0.8)
                if stage == .act {
                    Text(stage.summary).font(.uiCaption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StageNode: View {
    let stage: HarnessStage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            StageTitle(stage: stage)
            Text(stage.summary)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.10), in: shape)
        .overlay(shape.strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1))
    }
}

/// Where the flow starts and ends.
private struct FlowEnd: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Palette.accent)
            Text(title).font(.uiCaption.weight(.semibold)).lineLimit(1).fixedSize()
        }
        .frame(width: 62)
    }
}

private struct FlowArrow: View {
    var small = false
    var down = false

    var body: some View {
        Image(systemName: down ? "arrow.down" : "arrow.right")
            .font(.system(size: small ? 9 : 12, weight: .bold))
            .foregroundStyle(Palette.accent.opacity(0.8))
            .frame(width: small ? 18 : 22)
    }
}

/// Lines from one step fanning out to each route, or the routes coming back together.
private struct FanLines: Shape {
    let rows: Int
    let opening: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let hub = CGPoint(x: opening ? rect.minX : rect.maxX, y: rect.midY)
        // The first row holds the step's title, so the lines start at the second.
        for row in 1..<rows {
            let y = rect.height * (CGFloat(row) + 0.5) / CGFloat(rows)
            path.move(to: hub)
            path.addCurve(to: CGPoint(x: opening ? rect.maxX : rect.minX, y: y),
                          control1: CGPoint(x: rect.midX, y: hub.y), control2: CGPoint(x: rect.midX, y: y))
        }
        return path
    }
}

/// The way back from Check to Act, along the bottom of the diagram.
private struct LoopBackLine: Shape {
    let leftInset: CGFloat
    let rightInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let start = rect.maxX - rightInset, end = rect.minX + leftInset, bottom = rect.maxY - 2, corner: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: start, y: rect.minY))
        path.addLine(to: CGPoint(x: start, y: bottom - corner))
        path.addQuadCurve(to: CGPoint(x: start - corner, y: bottom), control: CGPoint(x: start, y: bottom))
        path.addLine(to: CGPoint(x: end + corner, y: bottom))
        path.addQuadCurve(to: CGPoint(x: end, y: bottom - corner), control: CGPoint(x: end, y: bottom))
        path.addLine(to: CGPoint(x: end, y: rect.minY))
        path.move(to: CGPoint(x: end - 5, y: rect.minY + 7))
        path.addLine(to: CGPoint(x: end, y: rect.minY))
        path.addLine(to: CGPoint(x: end + 5, y: rect.minY + 7))
        return path
    }
}

/// Every site the harness may read, by purpose.
struct TrustedSiteList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TrustedSite.Purpose.allCases) { purpose in
                VStack(alignment: .leading, spacing: 4) {
                    Text(purpose.rawValue).font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 5) {
                        ForEach(TrustedSites.all.filter { $0.purpose == purpose }) { site in
                            Chip(text: site.name, tint: .secondary).help(site.domain)
                        }
                    }
                }
            }
        }
    }
}
