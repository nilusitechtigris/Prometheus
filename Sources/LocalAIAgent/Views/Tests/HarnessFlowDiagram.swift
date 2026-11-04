import SwiftUI

/// What the harness does to a task, step by step: the same four steps the pipeline runs, with the
/// task's type choosing the route through step 2.
struct HarnessFlowDiagram: View {
    private struct Route: Identifiable {
        let kind: String
        let symbol: String
        let steps: [String]
        var id: String { kind }
    }

    private static let routes = [
        Route(kind: "Math or code", symbol: "function", steps: ["Writes a program", "Runs in the sandbox"]),
        Route(kind: "Fact", symbol: "magnifyingglass", steps: ["Searches 4 sources", "Reads the top page"]),
        Route(kind: "Long text", symbol: "doc.text", steps: ["Writes a parser", "Runs in the sandbox"]),
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
            guardrails
            Text("Off in chat until you turn it on with the Harness button under the message box. With it on, search terms go to Wikipedia, Stack Overflow, arXiv and MDN, pages come from the trusted sites, and every search and page is listed above the reply. Test questions are fixed, so a test sends nothing of yours. In a test the model can also call the web search, page reader, calculator and code runner itself. In chat only the harness uses them, so a web page can't steer a tool while your chat is in view. The guard is basic protection: it blocks common attacks like the ones in this test, not every possible one. Code runs on this Mac only.")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Layouts

    private var wide: some View {
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
                .foregroundStyle(.white)
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
