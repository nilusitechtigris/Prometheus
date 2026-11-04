import SwiftUI

/// The three tests. Their results share one page, one tab at a time.
enum TestTab: String, CaseIterable, Identifiable {
    case model, hardware, harness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: return "Model"
        case .hardware: return "Hardware"
        case .harness: return "Harness"
        }
    }

    var symbol: String {
        switch self {
        case .model: return "checkmark.seal.fill"
        case .hardware: return "cpu.fill"
        case .harness: return "shield.lefthalf.filled"
        }
    }
}

/// The one Tests page: choose which test's results to see, then read them in the same layout.
struct TestsPage: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            TestTabBar()
            switch ui.testTab {
            case .model: ModelTestDashboard()
            case .hardware: HardwareTestDashboard()
            case .harness: HarnessTestDashboard()
            }
        }
        .background(AmbientBackground())
    }
}

private struct TestTabBar: View {
    @Environment(UIState.self) private var ui
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TestTab.allCases) { tab(for: $0) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    private func tab(for tab: TestTab) -> some View {
        let selected = ui.testTab == tab
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            ui.testTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 28, height: 28)
                    .background(selected ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(tab.title)
                    .font(.uiCallout.weight(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer(minLength: 6)
                if isRunning(tab) {
                    ProgressView().controlSize(.mini)
                } else if let status = status(of: tab) {
                    Text(status).font(.uiCaption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? Palette.accent.opacity(0.12) : Color.primary.opacity(0.04), in: shape)
            .overlay(shape.strokeBorder(selected ? Palette.accent.opacity(0.55) : Color.primary.opacity(0.09), lineWidth: selected ? 1 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Show the \(tab.title.lowercased()) test results")
    }

    private func isRunning(_ tab: TestTab) -> Bool {
        switch tab {
        case .model: return lab.modelProgress != nil
        case .hardware: return lab.hardwareProgress != nil
        case .harness: return lab.harnessProgress != nil
        }
    }

    private func status(of tab: TestTab) -> String? {
        switch tab {
        case .model: return lab.selectedModelRun.map { "\(TestFormat.score($0.score))/100" }
        case .hardware: return lab.selectedHardwareRun?.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" }
        case .harness: return lab.harnessRun(for: lab.testModel(in: backends)?.id).map { "\(TestFormat.score($0.score))/100" }
        }
    }
}
