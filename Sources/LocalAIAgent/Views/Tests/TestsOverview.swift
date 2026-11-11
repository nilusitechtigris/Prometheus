import SwiftUI

/// The first thing on the Tests page: the three tests side by side, each with its last result on this Mac
/// and the way in. Nothing here is a sample. A test that hasn't been run says so.
struct TestsOverview: View {
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tests").font(Brand.display(28)).foregroundStyle(Forge.ink)
                    Text("Three things to measure here: a model, this Mac, and what the harness adds.")
                        .font(.uiBody)
                        .foregroundStyle(Forge.dim)
                }
                // One row of three, each the same height. The window can't get narrower than three cards need.
                HStack(alignment: .top, spacing: 16) { cards }
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var cards: some View {
        modelCard
        macCard
        harnessCard
    }

    // MARK: - A model

    private var modelCard: some View {
        let model = lab.testModel(in: backends)
        let result = lab.latestModelResult(for: model?.id)
        return TestCard(tag: "Any model you have", title: "Model test",
                        text: "How well a model answers by itself: knowledge, instructions and code, out of 100.",
                        button: result == nil ? "Test a model" : "Open the model test") {
            ui.testTab = .model
        } content: {
            if let model {
                ResultRow(title: model.displayName, value: result.map { "\(TestFormat.score($0.score)) / 100" })
            } else {
                ResultRow(title: "No model chosen yet", value: nil)
            }
        }
    }

    // MARK: - This Mac

    private var macCard: some View {
        let memory = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let gpu = Double(monitor.gpuBudgetBytes) / 1_073_741_824
        let run = lab.selectedHardwareRun
        return TestCard(tag: "Only you can run this", title: "This Mac",
                        text: "\(monitor.chipName) · \(memory) GB memory · about \(TestFormat.number(gpu, decimals: 1)) GB usable by the GPU.",
                        button: run == nil ? "Test this Mac" : "Open the hardware test", primary: run == nil) {
            ui.testTab = .hardware
        } content: {
            ResultRow(title: "Memory bandwidth", value: run?.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" },
                      note: "How fast this Mac feeds the GPU, which sets how quickly a model writes.")
        }
    }

    // MARK: - The harness

    private var harnessCard: some View {
        let model = lab.testModel(in: backends)
        let run = lab.harnessRun(for: model?.id)
        let plain = run.flatMap { lab.baseline(of: $0) }
        return TestCard(tag: "With it and without", title: "Harness test",
                        text: "The same tasks asked twice on one model: once plain, once with the harness.",
                        button: run == nil ? "Run the harness test" : "Open the harness test") {
            ui.testTab = .harness
        } content: {
            if let run {
                VStack(alignment: .leading, spacing: 10) {
                    if let plain { ScoreBar(title: "Without the harness", score: plain.score, tint: Color.white.opacity(0.72)) }
                    // The label names the version in the lab and only says "Harness" everywhere else.
                    ScoreBar(title: run.version?.label ?? "With the harness", score: run.score, tint: Palette.accent)
                    if let model {
                        Text("\(model.displayName) · \(run.askedSet == nil ? "out of 100" : "per cent right")")
                            .font(.uiCaption)
                            .foregroundStyle(Forge.dim)
                            .lineLimit(1)
                    }
                }
            } else {
                ResultRow(title: model?.displayName ?? "No model chosen yet", value: nil)
            }
        }
    }
}

/// One of the three cards: what the test is, its last result, and the way in.
private struct TestCard<Content: View>: View {
    let tag: String
    let title: String
    let text: String
    let button: String
    var primary = false
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tag)
                .font(.uiCaption.weight(.medium))
                .foregroundStyle(Forge.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.geist(20, weight: .semibold)).foregroundStyle(Forge.ink)
            Text(text)
                .font(.uiCallout)
                .foregroundStyle(Forge.dim)
                .fixedSize(horizontal: false, vertical: true)
            content
            Spacer(minLength: 6)
            if primary {
                Button(action: action) { Text(button).frame(maxWidth: .infinity) }.buttonStyle(AccentButtonStyle())
            } else {
                Button(action: action) { Text(button).frame(maxWidth: .infinity) }.buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The same light on all three. The middle one used to have more, and the others none.
        .panelSurface()
    }
}

/// A name and its number, or "Not tested yet" in the number's place.
private struct ResultRow: View {
    let title: String
    let value: String?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.uiCallout).foregroundStyle(Forge.dim).lineLimit(1)
                Spacer(minLength: 0)
                Text(value ?? "Not tested yet")
                    .font(.geist(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Forge.dim : Forge.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let note {
                Text(note).font(.uiCaption).foregroundStyle(Forge.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface()
    }
}

/// A score out of 100 as a bar with its number. The two bars differ in lightness as well as colour.
private struct ScoreBar: View {
    let title: String
    let score: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.uiCallout).foregroundStyle(Forge.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(TestFormat.score(score)).font(.geist(15, weight: .semibold)).monospacedDigit().foregroundStyle(Forge.ink)
            }
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule(style: .circular).fill(Color.white.opacity(0.13))
                    Capsule(style: .circular).fill(tint).frame(width: max(4, box.size.width * min(1, max(0, score / 100))))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(TestFormat.score(score))")
    }
}
