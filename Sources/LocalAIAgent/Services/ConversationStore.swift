import Foundation

/// Persists conversations as JSON in ~/Library/Application Support/LocalAIAgent.
struct ConversationStore {
    let fileURL: URL

    /// The app's data folder (also holds test results).
    static let directory: URL = {
        var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAIAgent", isDirectory: true)
        #if DEBUG
        // Keeps automated UI test runs away from the user's real chats.
        if let dir = ProcessInfo.processInfo.environment["LOCALAI_DATA_DIR"] {
            base = URL(fileURLWithPath: dir, isDirectory: true)
        }
        #endif
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    init() {
        fileURL = Self.directory.appendingPathComponent("conversations.json")
    }

    func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let conversations = try? decoder.decode([Conversation].self, from: data) else {
            Self.setAside(fileURL)
            return []
        }
        return conversations
    }

    /// Keeps a copy of a file that couldn't be read, because the next save would replace the only one.
    static func setAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: url, to: copy)
    }

    func save(_ conversations: [Conversation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Splits `<think>…</think>` blocks out of streamed text, even when tags are split across chunks.
struct ThinkTagParser {
    private var inThink = false
    private var pending = ""
    private static let open = "<think>", close = "</think>"

    var isThinking: Bool { inThink }

    mutating func feed(_ chunk: String) -> (thinking: String, answer: String) {
        pending += chunk
        var thinking = "", answer = ""
        while true {
            let tag = inThink ? Self.close : Self.open
            if let range = pending.range(of: tag) {
                let before = String(pending[..<range.lowerBound])
                if inThink { thinking += before } else { answer += before }
                pending = String(pending[range.upperBound...])
                inThink.toggle()
                continue
            }
            // Hold back a trailing partial tag such as "<thi".
            var keep = 0
            for n in stride(from: min(tag.count - 1, pending.count), through: 1, by: -1) where tag.hasPrefix(pending.suffix(n)) {
                keep = n
                break
            }
            let emit = String(pending.dropLast(keep))
            if inThink { thinking += emit } else { answer += emit }
            pending = String(pending.suffix(keep))
            return (thinking, answer)
        }
    }

    mutating func flush() -> (thinking: String, answer: String) {
        defer { pending = "" }
        return inThink ? (pending, "") : ("", pending)
    }
}
