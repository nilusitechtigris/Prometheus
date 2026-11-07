import AppKit
import SwiftUI

/// Picks saved runs and turns them into one file to share. The app sends nothing itself: the file
/// only goes up when someone drops it on GitHub's upload page and submits it.
struct PublishPage: View {
    @Environment(TestLab.self) private var lab
    @Environment(SystemMonitor.self) private var monitor
    @State private var picked: Set<UUID> = []
    @State private var machine: PublishedResults.Machine?
    @State private var savedFiles: [URL] = []
    @State private var failure: String?

    var body: some View {
        TestPage(title: "Publish Results",
                 subtitle: "Add your runs to the project on GitHub, so people can compare them with their own Macs.",
                 caption: machine.map(summary), onStop: {}) {
            Button(action: publish) {
                Label("Publish", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(AccentButtonStyle(compact: true))
            .controlSize(.large)
            .opacity(canPublish ? 1 : 0.45)
            .disabled(!canPublish)
        } content: {
            if let failure {
                ErrorBanner(text: failure) { self.failure = nil }
            }
            if !savedFiles.isEmpty { nextSteps(savedFiles) }
            runList
            contents
        }
        .task {
            let (chip, gpuCores) = (monitor.chipName, monitor.gpuCoreCount)
            machine = await Task.detached { ResultsPublisher.machine(chip: chip, gpuCores: gpuCores) }.value
        }
    }

    private var harnessRuns: [ModelTestResult] { lab.modelResults.filter(\.usesHarness) }
    private var plainRuns: [ModelTestResult] { lab.modelResults.filter { !$0.usesHarness } }
    private var everyID: [UUID] { lab.modelResults.map(\.id) + lab.hardwareResults.map(\.id) }
    private var canPublish: Bool { machine != nil && !picked.isEmpty }

    private func summary(_ machine: PublishedResults.Machine) -> String {
        "\(machine.name) · \(machine.chip.replacingOccurrences(of: "Apple ", with: "")) · \(machine.memoryGB) GB · macOS \(machine.macOS)"
    }

    /// A harness run means little without the run it's compared with, so that comes along with it.
    private var chosenModelRuns: [ModelTestResult] {
        let baselines = Set(lab.modelResults.filter { picked.contains($0.id) }.compactMap(\.baselineRunID))
        return lab.modelResults.filter { picked.contains($0.id) || baselines.contains($0.id) }
    }

    private func publish() {
        guard let machine else { return }
        let results = PublishedResults(app: AppUpdater.commit, machine: machine, modelRuns: chosenModelRuns,
                                       hardwareRuns: lab.hardwareResults.filter { picked.contains($0.id) })
        do {
            let files = try ResultsPublisher.write(results)
            savedFiles = files
            failure = nil
            NSWorkspace.shared.activateFileViewerSelecting(files)
            NSWorkspace.shared.open(ResultsPublisher.uploadPage)
        } catch {
            failure = "Couldn't save the file: \(error.localizedDescription)"
        }
    }

    // MARK: Runs

    private var runList: some View {
        PanelWidget(title: "Runs on this Mac", symbol: "checklist") {
            HStack(spacing: 8) {
                Text("\(picked.count) chosen").font(.uiCaption).foregroundStyle(.secondary)
                Button("All") { picked = Set(everyID) }
                Button("None") { picked = [] }
            }
            .controlSize(.small)
            .disabled(everyID.isEmpty)
        } content: {
            if everyID.isEmpty {
                Text("Run a test first, and it will show up here.").font(.uiCallout).foregroundStyle(.secondary)
            }
            group("Harness Test", harnessRuns.map(row))
            group("Model Test", plainRuns.map(row))
            group("Hardware Test", lab.hardwareResults.map(row))
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [PublishRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 2)
                ForEach(rows) { $0 }
            }
            .padding(.bottom, 6)
        }
    }

    private func row(_ run: ModelTestResult) -> PublishRow {
        let setup = "\(run.displayName) · \(run.quant) · \(Format.tokens(run.contextLength))\(run.setupLabel)"
        return PublishRow(id: run.id, date: run.date, title: setup, tag: run.isCurrentSuite ? (run.isQuick ? "Normal" : nil) : "old test",
                          result: TestFormat.score(run.score), isOn: binding(run.id))
    }

    private func row(_ run: HardwareTestResult) -> PublishRow {
        PublishRow(id: run.id, date: run.date, title: "\(run.chip) · \(Format.gigabytes(run.memoryBytes))", tag: nil,
                   result: run.gpuBandwidth.map { "\(TestFormat.gbPerSecond($0)) GB/s" } ?? "—", isOn: binding(run.id))
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { picked.contains(id) },
                set: { on in
                    if on { picked.insert(id) } else { picked.remove(id) }
                })
    }

    // MARK: What happens

    private var contents: some View {
        PanelWidget(title: "What goes in the file", symbol: "doc.text.magnifyingglass") { EmptyView() } content: {
            VStack(alignment: .leading, spacing: 8) {
                Label("Each chosen run, task by task: the question, the reply, the end of the model's thinking, tokens for thinking and output, time, points and the harness's steps. A harness run brings the harness-off run it's compared with.",
                      systemImage: "checkmark.circle")
                Label("This Mac's kind, chip, core counts, memory and macOS version.", systemImage: "checkmark.circle")
                Label("Never your chats, your name, your computer's name or its serial number.", systemImage: "lock.shield")
                Text("Publish saves a JSON file and a readable report, then opens GitHub. Nothing leaves this Mac unless you upload them there, and what you upload is public.")
                    .foregroundStyle(.secondary)
            }
            .font(.uiCallout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextSteps(_ files: [URL]) -> some View {
        PanelWidget(title: "Saved. Now add it on GitHub", symbol: "checkmark.circle.fill") { EmptyView() } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(files, id: \.self) { Text($0.lastPathComponent).font(.geistMono(13)).textSelection(.enabled) }
                Text("1. Drag both files from Finder onto the GitHub page that just opened.")
                Text("2. Press **Propose changes**, then **Create pull request**.")
                HStack(spacing: 8) {
                    Button("Show Files") { NSWorkspace.shared.activateFileViewerSelecting(files) }
                    Button("Open GitHub") { NSWorkspace.shared.open(ResultsPublisher.uploadPage) }
                }
                .padding(.top, 4)
            }
            .font(.uiCallout)
        }
    }
}

/// One saved run, ready to tick.
private struct PublishRow: View, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let tag: String?
    let result: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.uiCallout.monospacedDigit())
                    .frame(width: 170, alignment: .leading)
                Text(title).font(.uiCallout).lineLimit(1)
                if let tag { Text(tag).font(.uiCaption).foregroundStyle(Forge.faint) }
                Spacer(minLength: 8)
                Text(result).font(.uiCallout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 3)
    }
}
