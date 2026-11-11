import Foundation

/// The readable side of a publish: a Markdown page GitHub shows as tables, with one row for each task and
/// every reply folded away below. The JSON beside it holds the same runs for tools.
enum ResultsReport {
    static func markdown(for results: PublishedResults) -> String {
        let machine = results.machine
        var lines = ["# \(machine.name) · \(machine.chip) · \(machine.memoryGB) GB", ""]
        lines.append("macOS \(machine.macOS) · \(machine.cpuCores) CPU cores\(machine.gpuCores.map { " · \($0) GPU cores" } ?? "")")
        lines.append("Published with Prometheus\(results.app.map { " `\($0.prefix(7))`" } ?? "") on \(day(results.createdAt)).")
        lines.append("")
        if results.modelRuns.count > 1 { lines += overview(results.modelRuns) }
        for run in results.modelRuns { lines += section(run) }
        for run in results.hardwareRuns { lines += section(run) }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func title(_ run: ModelTestResult) -> String {
        var parts = ["\(run.displayName) \(run.quant)", run.backend, "\(run.contextLength / 1_024)K context"]
        parts.append(run.thinking ? "thinking on" : "thinking off")
        parts.append(run.version.map { "harness \($0.short)" } ?? (run.usesHarness ? "harness, a version this copy doesn't know" : "harness off"))
        if run.size != .max { parts.append(run.askedSet.map { "\(run.size.title) (\($0))" } ?? run.size.title) }
        if let index = run.repeatIndex { parts.append("round \(index)") }
        return parts.joined(separator: " · ")
    }

    private static func overview(_ runs: [ModelTestResult]) -> [String] {
        var lines = ["## Runs", "", "| Run | Test version | Score | Points | Time |", "| --- | --- | --- | --- | --- |"]
        for run in runs {
            // On a public set the score is a share, so one decimal says more than a rounded number.
            let score = run.askedSet == nil ? "\(Int(run.score))" : String(format: "%.1f%%", run.score)
            lines.append("| \(cell(title(run))) | \(run.suiteVersion.map(String.init) ?? "old") | \(score) | \(run.points)/\(run.maxPoints) | \(Format.seconds(run.duration)) |")
        }
        return lines + [""]
    }

    private static func section(_ run: ModelTestResult) -> [String] {
        var lines = ["## \(title(run))", ""]
        let publicSet = run.askedSet != nil
        var summary = publicSet
            ? [String(format: "**%d of %d right** (%.1f%%)", run.passed, run.items.count, run.score)]
            : ["Score **\(Int(run.score))**", "\(run.points) of \(run.maxPoints) points", "\(run.passed) of \(run.items.count) tasks"]
        summary.append(Format.seconds(run.duration))
        if let speed = run.tokensPerSecond { summary.append(String(format: "%.1f tokens/s", speed)) }
        if let python = run.pythonVersion { summary.append("code graded on Python \(python)") }
        if run.errorCount > 0 { summary.append("\(run.errorCount) with no reply because of an error, counted as wrong") }
        lines += [summary.joined(separator: " · "), ""]
        if publicSet {
            lines += ["| Source | Right |", "| --- | --- |"]
            for source in HeldOut.sources {
                let items = run.items.filter { $0.id.hasPrefix(source.prefix) }
                if !items.isEmpty { lines.append("| \(source.name) | \(items.filter(\.passed).count) of \(items.count) |") }
            }
            lines.append("")
        }
        // The held-out questions and replies stay out of the page people read, so nobody tunes the harness on
        // them by accident. The JSON beside this file has every reply, for anyone who wants to check the grading.
        if run.size == .heldOut {
            return lines + ["The replies aren't printed here. They are in the `.json` file with the same name, for checking the grading. If you work on the harness, don't read them: see `benchmarks/heldout/README.md`.", ""]
        }
        lines.append("| Task | Level | Result | Points | Seconds | Thinking tokens | Output tokens | Stopped | Expected | Answer |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for item in run.items {
            let row: [String] = [
                item.title, item.level?.name ?? "—", item.passed ? "✅" : "❌", "\(item.passed ? item.weight : 0)/\(item.weight)",
                String(format: "%.1f", item.seconds), item.thinkingTokens.map(String.init) ?? "0", item.outputTokens.map(String.init) ?? "—",
                item.ranOutOfTokens ? "ran out of tokens" : (item.stopReason ?? "—"), item.expected, short(ModelTestSuite.finalAnswer(item.answer)),
            ]
            lines.append("| " + row.map(cell).joined(separator: " | ") + " |")
        }
        lines.append("")
        lines += pages(run)
        lines += ["<details>", "<summary>Every reply</summary>", ""]
        for item in run.items {
            lines += ["### \(item.title)", ""]
            if let log = item.toolLog, !log.isEmpty { lines += ["Harness steps:", ""] + log.map { "- \($0)" } + [""] }
            if let thinking = item.thinking, !thinking.isEmpty { lines += ["Thinking, the end of it:", "", fence(thinking), ""] }
            lines += ["Reply:", "", fence(item.answer.isEmpty ? "(no reply)" : item.answer), ""]
        }
        return lines + ["</details>", ""]
    }

    private static func pages(_ run: ModelTestResult) -> [String] {
        guard let with = run.injectionWith, !with.isEmpty else { return [] }
        let without = run.injectionWithout ?? []
        var lines = ["Poisoned pages:", "", "| Page | Harness off | Harness on |", "| --- | --- | --- |"]
        for page in with {
            let off = without.first { $0.id == page.id }
            lines.append("| \(cell(page.title)) | \(off.map { $0.passed ? "✅" : "❌" } ?? "—") | \(page.passed ? "✅" : "❌") |")
        }
        return lines + [""]
    }

    private static func section(_ run: HardwareTestResult) -> [String] {
        func value(_ number: Double?, _ unit: String) -> String { number.map { String(format: "%.1f %@", $0, unit) } ?? "—" }
        return ["## Hardware Test, \(day(run.date))", "", "| Measure | Result |", "| --- | --- |",
                "| CPU, one core | \(value(run.cpuSingle, "M iterations/s")) |", "| CPU, all cores | \(value(run.cpuMulti, "M iterations/s")) |",
                "| GPU | \(value(run.gpuTFLOPS, "TFLOPS")) |", "| Memory, CPU | \(value(run.cpuBandwidth, "GB/s")) |",
                "| Memory, GPU | \(value(run.gpuBandwidth, "GB/s")) |", "| Disk read | \(value(run.diskRead, "GB/s")) |",
                "| Disk write | \(value(run.diskWrite, "GB/s")) |", "| Sustained GPU | \(value(run.sustainedPercent, "%")) |", ""]
    }

    private static func short(_ text: String) -> String {
        text.count > 80 ? String(text.prefix(79)) + "…" : text
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// A code block long enough that nothing in a reply can close it early.
    private static func fence(_ text: String) -> String {
        var ticks = "```"
        while text.contains(ticks) { ticks += "`" }
        return "\(ticks)text\n\(text)\n\(ticks)"
    }
}
