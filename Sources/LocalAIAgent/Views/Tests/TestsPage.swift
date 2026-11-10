import SwiftUI

/// The three tests, and sharing their results. They share one page, one tab at a time.
enum TestTab: String, CaseIterable, Identifiable {
    case model, hardware, harness, publish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: return "Model"
        case .hardware: return "Hardware"
        case .harness: return "Harness"
        case .publish: return "Publish"
        }
    }

    /// The Hardware Test is for everyone. The others measure models and the harness, and show with the Lab on.
    static func shown(lab: Bool) -> [TestTab] { lab ? allCases : [.hardware] }
}

/// The one Tests page: choose which test's results to see, then read them in the same layout.
struct TestsPage: View {
    @Environment(UIState.self) private var ui
    @Environment(AppSettings.self) private var settings

    /// With the Lab off there is only the Hardware Test to show, whatever tab was open last.
    private var tab: TestTab { settings.showLab ? ui.testTab : .hardware }

    var body: some View {
        VStack(spacing: 0) {
            TestTabBar()
            PageSwap(value: tab) {
                switch tab {
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
    @Environment(AppSettings.self) private var settings
    @Namespace private var underline

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 22) {
            ForEach(TestTab.shown(lab: settings.showLab)) { tab(for: $0) }
            Spacer()
            Toggle(isOn: $settings.showLab) {
                Text("Lab").font(.uiCallout).foregroundStyle(settings.showLab ? .primary : .secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(lab.isRunning)
            .help(settings.showLab
                  ? "Hide the Model Test, the Harness Test and Publish"
                  : "Measure a model and the harness yourself, and publish your runs")
        }
        .animation(Motion.page, value: ui.testTab)
        .animation(Motion.quick, value: settings.showLab)
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
                UnderlineTab(title: tab.title, selected: (settings.showLab ? ui.testTab : .hardware) == tab, bar: underline)
                if isRunning(tab) {
                    ProgressView().controlSize(.mini)
                } else if let status = status(of: tab) {
                    Text(status).font(.uiCaption.monospacedDigit()).foregroundStyle(Forge.faint).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab == .publish ? "Share your results on GitHub" : "Show the \(tab.title.lowercased()) test results")
    }

    private func isRunning(_ tab: TestTab) -> Bool {
        switch tab {
        case .model: return lab.modelProgress != nil
        case .hardware: return lab.hardwareProgress != nil
        case .harness: return lab.harnessProgress != nil
        case .publish: return false
        }
    }

    private func status(of tab: TestTab) -> String? {
        switch tab {
        case .model: return lab.selectedModelRun.map { "\(TestFormat.score($0.score))/100" }
        case .hardware: return lab.selectedHardwareRun?.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" }
        case .harness: return lab.harnessRun(for: lab.testModel(in: backends)?.id).map { "\(TestFormat.score($0.score))\($0.askedSet == nil ? "/100" : "%")" }
        case .publish: return nil
        }
    }
}
