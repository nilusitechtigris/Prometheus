import Foundation

/// The file people publish: the runs they chose and the Mac they ran on. A saved model run doesn't
/// say which machine it came from, so that goes at the top. Described in results/README.md.
struct PublishedResults: Encodable {
    struct Machine: Encodable, Equatable {
        /// The kind of Mac, such as "Mac mini". Never the name someone gave their computer.
        var name: String
        /// Apple's model code, such as "Mac16,11".
        var identifier: String
        var chip: String
        var cpuCores: Int
        var gpuCores: Int?
        var memoryGB: Int
        var macOS: String
    }

    /// Bump when the layout of this file changes.
    var format = 1
    /// The commit of the app that wrote the file.
    var app: String?
    var createdAt = Date()
    var machine: Machine
    var modelRuns: [ModelTestResult]
    var hardwareRuns: [HardwareTestResult]
}

/// Writes the file. Nothing here goes online: it only reaches GitHub if someone uploads it there.
enum ResultsPublisher {
    /// GitHub makes the fork, branch and pull request itself, so the app needs no account or token.
    static let uploadPage = URL(string: "https://github.com/nilusitechtigris/Prometheus/upload/main/results")!

    static var folder: URL { ConversationStore.directory.appendingPathComponent("Published", isDirectory: true) }

    /// Asks the system for this Mac's details. Slow enough to keep off the main thread.
    static func machine(chip: String, gpuCores: Int?) -> PublishedResults.Machine {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .init(name: machineName() ?? "Mac", identifier: modelIdentifier() ?? "unknown", chip: chip,
                     cpuCores: ProcessInfo.processInfo.activeProcessorCount, gpuCores: gpuCores,
                     memoryGB: Int(ProcessInfo.processInfo.physicalMemory / (1 << 30)),
                     macOS: "\(version.majorVersion).\(version.minorVersion)")
    }

    /// Machine, chip, memory and time, as in mac-mini-m4-pro-48gb-2026-11-06-1523.json.
    static func fileName(for machine: PublishedResults.Machine, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let details = "\(machine.name) \(machine.chip.replacingOccurrences(of: "Apple ", with: "")) \(machine.memoryGB)gb"
        let words = details.lowercased().split { !$0.isLetter && !$0.isNumber }
        return (words + [Substring(formatter.string(from: date))]).joined(separator: "-") + ".json"
    }

    /// Writes the JSON and the readable report beside it, and returns both.
    static func write(_ results: PublishedResults) throws -> [URL] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let details = try withTotals(encoder.encode(results), results: results)
        let json = String(decoding: details, as: UTF8.self)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(fileName(for: results.machine, date: results.createdAt))
        let report = file.deletingPathExtension().appendingPathExtension("md")
        // Nothing saved today has a path in it, but a tool's log could one day.
        try clean(json).write(to: file, atomically: true, encoding: .utf8)
        try clean(ResultsReport.markdown(for: results)).write(to: report, atomically: true, encoding: .utf8)
        return [file, report]
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Adds what a reader would otherwise have to work out from each run and task.
    private static func withTotals(_ data: Data, results: PublishedResults) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var runs = root["modelRuns"] as? [[String: Any]] else { return data }
        for (index, run) in results.modelRuns.enumerated() where index < runs.count {
            runs[index]["score"] = run.score
            runs[index]["points"] = run.points
            runs[index]["maxPoints"] = run.maxPoints
            runs[index]["passedTasks"] = run.passed
            guard var items = runs[index]["items"] as? [[String: Any]] else { continue }
            for (position, item) in run.items.enumerated() where position < items.count {
                items[position]["points"] = item.passed ? item.weight : 0
                items[position]["maxPoints"] = item.weight
                items[position]["totalTokens"] = (item.outputTokens ?? 0) + (item.thinkingTokens ?? 0)
                items[position]["ranOutOfTokens"] = item.ranOutOfTokens
                items[position]["finalAnswer"] = ModelTestSuite.finalAnswer(item.answer)
            }
            runs[index]["items"] = items
        }
        root["modelRuns"] = runs
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The report also holds the serial number, so only this one field is read from it.
    private static func machineName() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: [[String: Any]]]
        return report?["SPHardwareDataType"]?.first?["machine_name"] as? String
    }

    private static func modelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
