import AppKit
import SwiftUI

/// The same request built twice on the same model, with the harness off and on, side by side: each
/// one's page running live, how long it took, and the same scorecard for both, checked by code.
struct DevCompareView: View {
    @Environment(DevSession.self) private var dev
    @State private var request = ""

    var body: some View {
        VStack(spacing: 0) {
            if let comparison = dev.shown {
                let fills = dev.compareFills
                if fills == nil {
                    DevCompareHeader(comparison: comparison)
                    Forge.rule()
                }
                // Both sides stay put while one fills the window, so neither page starts over and both can be
                // in a screenshot.
                CompareSplit(fills: fills) {
                    DevCompareColumn(comparison: comparison, side: comparison.off)
                    Forge.rule(vertical: true)
                    DevCompareColumn(comparison: comparison, side: comparison.on)
                }
                .clipped()
                if fills == nil {
                    Forge.rule()
                    DevCompareStarter(request: $request, compact: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Palette.accent)
                    Text("Compare the harness").font(Brand.display(24))
                    DevCompareStarter(request: $request)
                        .frame(width: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Where a comparison starts: a request, and a button that builds it both ways.
struct DevCompareStarter: View {
    @Environment(DevSession.self) private var dev
    @Binding var request: String
    var compact = false

    private var ready: Bool { dev.canCompare && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                Forge.label("Compare the harness")
                Text("Builds the same request twice on this model, in two new folders: once with the harness off, as one reply saved as it came, and once with it on. Both get the same checks.")
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 8) {
                TextField(compact ? "Compare another request, or pick one from Prompts" : "A web app to build, or pick one from Prompts", text: $request, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.uiCallout)
                    .lineLimit(1...5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Forge.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
                    .onSubmit(start)
                Menu {
                    ForEach(["Demo", "Quick", "Traps"], id: \.self) { group in
                        Section(group == "Traps" ? "Traps a model alone falls into" : group) {
                            ForEach(DevCompare.prompts.filter { $0.group == group }) { prompt in
                                Button(prompt.title) { request = prompt.text }
                            }
                        }
                    }
                } label: {
                    Label("Prompts", systemImage: "text.badge.star").font(.uiCaption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Requests made for testing the harness. Pick one to fill in the box.")
                Button(action: start) {
                    Label("Compare", systemImage: "square.split.2x1")
                }
                .buttonStyle(AccentButtonStyle(compact: true))
                .disabled(!ready)
                .opacity(ready ? 1 : 0.5)
                .help(dev.blockedReason ?? "Build it with the harness off, then on")
            }
            if let reason = dev.isComparing ? "A comparison is running." : (dev.canCompare ? nil : dev.blockedReason) {
                Text(reason).font(.uiCaption2).foregroundStyle(Palette.warning)
            }
            if !compact, !dev.comparisons.isEmpty {
                Button("Earlier comparisons (\(dev.comparisons.count))") { dev.showComparison(dev.comparisons[0].id) }
                    .buttonStyle(.plain)
                    .font(.uiCaption)
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private func start() {
        guard ready else { return }
        dev.compare(request)
        request = ""
    }
}

private struct DevCompareHeader: View {
    @Environment(DevSession.self) private var dev
    let comparison: DevComparison

    private var isLive: Bool { dev.comparing?.id == comparison.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(comparison.request)
                    .font(.uiHeadline)
                    .foregroundStyle(Forge.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(details)
                    .font(.uiCaption)
                    .foregroundStyle(Forge.faint)
            }
            Spacer(minLength: 8)
            if isLive {
                Button(action: dev.stopCompare) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.plain)
                .font(.uiCaption)
                .foregroundStyle(Palette.critical)
                .help("Stop the comparison. What's done so far is kept.")
            }
            Menu {
                ForEach(dev.comparisons) { item in
                    Button("\(item.request.prefix(60)) · \(item.date.formatted(date: .abbreviated, time: .shortened))") { dev.showComparison(item.id) }
                }
                if !isLive {
                    Divider()
                    Button("Remove This from the List") { dev.removeComparison(comparison.id) }
                }
            } label: {
                Label("Earlier", systemImage: "clock.arrow.circlepath").font(.uiCaption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(dev.comparisons.isEmpty)
            DevCompareShotButton(comparison: comparison)
            Button {
                dev.revealComparison(comparison)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Forge.dim)
            .help("Show both folders in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var details: String {
        var parts = [comparison.model, comparison.framework]
        if comparison.context > 0 { parts.append("\(comparison.context / 1_024)K context") }
        parts.append(comparison.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

private struct DevCompareColumn: View {
    @Environment(DevSession.self) private var dev
    let comparison: DevComparison
    let side: DevCompareSide
    @State private var reload = UUID()

    private var isLive: Bool { dev.comparing?.id == comparison.id }
    private var isRunning: Bool { isLive && dev.compareSide == side.harness }
    private var isWaiting: Bool { isLive && !side.finished && !isRunning && !side.stopped }
    /// This side has the whole window.
    private var fills: Bool { dev.compareFills == side.harness }
    /// Whether a side filling the window zooms its page out to show all of it.
    @AppStorage("devCompareFit") private var fit = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if fills {
                    DevCompareSideSwitch()
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(comparison.request)
                        .font(.uiCaption)
                        .foregroundStyle(Forge.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(comparison.request)
                } else {
                    Text(side.harness ? "Harness on" : "Harness off")
                        .font(.uiHeadline)
                        .foregroundStyle(side.harness ? Palette.accent : Forge.ink)
                    Text(side.harness ? "plans, writes each file, tries it and fixes it" : "one reply, saved as it came")
                        .font(.uiCaption)
                        .foregroundStyle(Forge.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if side.page != nil, side.finished {
                    Button {
                        reload = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Forge.dim)
                    .help("Start the page again")
                }
                if side.finished, side.total > 0 {
                    Text("\(side.passed)/\(side.total)")
                        .font(.geistMono(15).weight(.semibold))
                        .foregroundStyle(side.passed == side.total ? Palette.good : side.passed * 2 >= side.total ? Palette.warning : Palette.critical)
                        .help(fills ? side.score.map { "\($0.passed == true ? "✓" : $0.passed == false ? "✗" : "–") \($0.name)" }.joined(separator: "\n") : "Checks passed")
                }
                if fills {
                    Button {
                        fit.toggle()
                    } label: {
                        Text("Fit")
                            .font(.uiCaption.weight(fit ? .semibold : .regular))
                            .foregroundStyle(fit ? Palette.onAccent : Forge.dim)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(fit ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.white.opacity(0.06))))
                            .overlay(Capsule().strokeBorder(fit ? Color.clear : Forge.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(fit ? "Showing all of the page, zoomed out to fit. Click for full size." : "Zoom the page out until all of it fits, for a screenshot")
                    .accessibilityLabel("Fit the page to the window")
                    .accessibilityValue(fit ? "On" : "Off")
                    DevCompareShotButton(comparison: comparison)
                }
                Button {
                    withAnimation(Motion.quick) { dev.compareFills = fills ? nil : side.harness }
                } label: {
                    Image(systemName: fills ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(fills ? Palette.accent : Forge.dim)
                .help(fills ? "Show both sides" : "Fill the window with this side")
                .accessibilityLabel(fills ? "Show both sides" : "Fill the window")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, fills ? 7 : 10)
            Forge.rule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !fills, side.finished || !side.score.isEmpty {
                Forge.rule()
                scorecard
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if isRunning {
            DevCompareLive(harness: side.harness)
        } else if isWaiting {
            VStack(spacing: 8) {
                Image(systemName: "hourglass").font(.system(size: 22, weight: .light)).foregroundStyle(Forge.faint)
                Text(dev.compareSide == nil ? (dev.compareStage ?? "Starting") : "Waiting for the other side to finish").font(.uiCaption).foregroundStyle(Forge.faint)
            }
        } else if side.stopped {
            Text("Stopped before it finished.").font(.uiCallout).foregroundStyle(Forge.faint)
        } else if let page = side.page {
            DevPreviewView(project: DevProject(root: URL(fileURLWithPath: side.folder)), path: page, loadID: reload, onMessage: { _ in }, onCrash: {},
                           fitsPage: fills && fit, handle: side.harness ? dev.comparePages.on : dev.comparePages.off)
                .id("\(comparison.id)-\(side.harness)")
        } else if side.finished {
            ScrollView {
                Text(side.text.isEmpty ? "Nothing to show." : side.text)
                    .font(.uiCallout)
                    .foregroundStyle(Forge.dim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            Text("Not built.").font(.uiCallout).foregroundStyle(Forge.faint)
        }
    }

    private var scorecard: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(side.score) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: line.passed == true ? "checkmark.circle.fill" : line.passed == false ? "xmark.circle.fill" : "minus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(line.passed == true ? Palette.good : line.passed == false ? Palette.critical : Forge.faint)
                    Text(line.name).font(.uiCaption).foregroundStyle(line.passed == nil ? Forge.faint : Forge.ink)
                    if let detail = line.detail, line.passed != true {
                        Text(detail).font(.uiCaption2).foregroundStyle(Forge.faint).lineLimit(1).truncationMode(.tail).help(detail)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(summary).font(.uiCaption2).foregroundStyle(Forge.faint).lineLimit(2).help(side.files.map { "\($0.path): \($0.lines) lines" }.joined(separator: "\n"))
                Spacer(minLength: 4)
                Button("Open as Project") { dev.openSide(side) }
                    .buttonStyle(.plain)
                    .font(.uiCaption)
                    .foregroundStyle(Palette.accent)
                    .disabled(isLive)
                    .help("Open this folder in Dev mode, to read its files or keep working on it")
            }
            .padding(.top, 3)
        }
    }

    private var summary: String {
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

/// The side being built right now: its steps, and what the model is writing.
private struct DevCompareLive: View {
    @Environment(DevSession.self) private var dev
    let harness: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // The step under way shows by the spinner, so it isn't listed twice.
                    ForEach(dev.compareSteps.filter { !($0.kind == .stage && $0.id == dev.compareSteps.last?.id && $0.text == dev.compareStage) }) { DevStepRow(step: $0) }
                    if !dev.compareWriting.isEmpty {
                        Text(dev.compareWriting.suffix(1_400).split(separator: "\n", omittingEmptySubsequences: false).suffix(14).joined(separator: "\n"))
                            .font(.geistMono(11))
                            .foregroundStyle(Forge.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(dev.compareStage ?? "Working").font(.uiCaption).foregroundStyle(Forge.dim)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .onChange(of: dev.compareWriting.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: dev.compareSteps.count) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

/// While one side fills the window, flips to the other one at the same size.
private struct DevCompareSideSwitch: View {
    @Environment(DevSession.self) private var dev

    var body: some View {
        HStack(spacing: 4) {
            Text("Harness").font(.uiCaption2).foregroundStyle(Forge.faint)
            HStack(spacing: 0) {
                segment("Off", on: false)
                segment("On", on: true)
            }
            .padding(2)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Forge.line, lineWidth: 1))
        }
        .help("Show the other side at the same size")
    }

    private func segment(_ title: String, on: Bool) -> some View {
        let selected = dev.compareFills == on
        return Button {
            withAnimation(Motion.quick) { dev.compareFills = on }
        } label: {
            Text(title)
                .font(.uiCaption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? (on ? Palette.onAccent : Forge.ink) : Forge.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(selected ? (on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.white.opacity(0.16))) : AnyShapeStyle(Color.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Harness \(title)")
    }
}

/// Takes one picture of both sides at full length, saves it with the comparison and copies it.
private struct DevCompareShotButton: View {
    @Environment(DevSession.self) private var dev
    @Environment(UIState.self) private var ui
    let comparison: DevComparison
    @State private var working = false

    private var isLive: Bool { dev.comparing?.id == comparison.id }

    var body: some View {
        Button {
            working = true
            Task {
                if await dev.screenshotComparison() != nil {
                    ui.showToast("Screenshot copied, and saved in the comparison's folder", symbol: "camera")
                }
                working = false
            }
        } label: {
            if working {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "camera")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Forge.dim)
        .disabled(working || isLive)
        .help(isLive ? "Wait for the comparison to finish" : "One picture of both apps at full length, nothing cut off: copied, and saved in the comparison's folder")
        .accessibilityLabel("Screenshot both apps")
    }
}

/// Both sides side by side, or one filling the space while the other waits out of sight at the same size.
/// Keeping both in place means neither page starts over when the view changes.
private struct CompareSplit: Layout {
    /// The side filling the space: false for the harness off, true for on. Nil for both.
    var fills: Bool?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let (off, rule, on) = (subviews[0], subviews[1], subviews[2])
        guard let side = fills else {
            let half = ((bounds.width - 1) / 2).rounded(.down)
            off.place(at: bounds.origin, proposal: ProposedViewSize(width: half, height: bounds.height))
            rule.place(at: CGPoint(x: bounds.minX + half, y: bounds.minY), proposal: ProposedViewSize(width: 1, height: bounds.height))
            on.place(at: CGPoint(x: bounds.minX + half + 1, y: bounds.minY), proposal: ProposedViewSize(width: bounds.width - half - 1, height: bounds.height))
            return
        }
        let full = ProposedViewSize(width: bounds.width, height: bounds.height)
        let away = CGPoint(x: bounds.maxX + bounds.width + 200, y: bounds.minY)
        (side ? on : off).place(at: bounds.origin, proposal: full)
        (side ? off : on).place(at: away, proposal: full)
        rule.place(at: away, proposal: ProposedViewSize(width: 1, height: bounds.height))
    }
}
