import SwiftUI

/// The three tests, an overview of them, and sharing their results. They share one page, one tab at a time.
enum TestTab: String, CaseIterable, Identifiable {
    case overview, model, hardware, harness, publish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .model: return "Model"
        case .hardware: return "Hardware"
        case .harness: return "Harness"
        case .publish: return "Publish"
        }
    }

    /// The tabs this copy shows. Publish sends results to the project's page, which is the lab's work:
    /// the public app has every test, and nothing to publish them with.
    static func shown(in edition: Edition = .current) -> [TestTab] {
        edition.isLab ? allCases : allCases.filter { $0 != .publish }
    }
}

/// The one Tests page: choose which test's results to see, then read them in the same layout.
struct TestsPage: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            TestTabBar()
            // A tab this copy doesn't show (Publish, outside the lab) falls back to the overview.
            let tab = TestTab.shown().contains(ui.testTab) ? ui.testTab : .overview
            PageSwap(value: tab) {
                switch tab {
                case .overview: TestsOverview()
                case .model: ModelTestDashboard()
                case .hardware: HardwareTestDashboard()
                case .harness: HarnessTestDashboard()
                case .publish: PublishPage()
                }
            }
        }
    }
}

private struct TestTabBar: View {
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Namespace private var underline

    var body: some View {
        // Every test is here for everyone. There used to be a Lab switch that hid the Model Test, the
        // Harness Test and Publish; which harness versions a copy offers is the edition's business now.
        HStack(spacing: 22) {
            ForEach(TestTab.shown()) { tab(for: $0) }
            Spacer()
        }
        .animation(Motion.page, value: ui.testTab)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    private func tab(for tab: TestTab) -> some View {
        Button {
            ui.testTab = tab
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                UnderlineTab(title: tab.title, selected: ui.testTab == tab, bar: underline)
                if isRunning(tab) {
                    ProgressView().controlSize(.mini)
                } else if let status = status(of: tab) {
                    Text(status).font(.uiCaption.monospacedDigit()).foregroundStyle(Forge.faint).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.soft)
        .help(tab == .publish ? "Share your results on GitHub" : tab == .overview ? "The three tests side by side" : "Show the \(tab.title.lowercased()) test results")
    }

    private func isRunning(_ tab: TestTab) -> Bool {
        switch tab {
        case .overview: return false
        case .model: return lab.modelProgress != nil
        case .hardware: return lab.hardwareProgress != nil
        case .harness: return lab.harnessProgress != nil
        case .publish: return false
        }
    }

    private func status(of tab: TestTab) -> String? {
        switch tab {
        case .overview: return nil
        case .model: return lab.selectedModelRun.map { "\(TestFormat.score($0.score))/100" }
        case .hardware: return lab.selectedHardwareRun?.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" }
        case .harness: return lab.harnessRun(for: lab.testModel(in: backends)?.id).map { "\(TestFormat.score($0.score))\($0.askedSet == nil ? "/100" : "%")" }
        case .publish: return nil
        }
    }
}
