import Foundation

/// Which edition this copy is. Everyone gets the standard one: one harness, on or off, with no versions to
/// choose. The lab keeps every version of the harness to use in chat and to test, for comparing them.
///
/// There's no control for it in the app. It's read once at launch from a setting that only someone running the
/// lab writes, `defaults write com.localaiagent.app edition lab`, or from `-edition lab` when the app is
/// started. Every copy is built the same way, by Update, from the same source, so a switch at build time would
/// be lost at the next update. This hides the versions. It doesn't lock them: the setting is here to read.
enum Edition: String {
    case standard, lab

    static let current: Edition = {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["LOCALAI_EDITION"].flatMap(Edition.init(rawValue:)) { return forced }
        #endif
        return Edition(rawValue: UserDefaults.standard.string(forKey: "edition") ?? "") ?? .standard
    }()

    var isLab: Bool { self == .lab }

    #if DEBUG
    /// What each edition offers, runs and calls a version. None of it needs a model.
    static func selfCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let usual = HarnessVersion.recommended
        expect("the standard edition offers one harness", HarnessVersion.offered(in: .standard) == [usual])
        expect("the lab offers every version", HarnessVersion.offered(in: .lab) == HarnessVersion.allCases)
        for version in HarnessVersion.allCases {
            expect("standard runs the harness in use when \(version.short) is stored", HarnessVersion.allowed(version, in: .standard) == usual)
            expect("the lab runs \(version.short) when it's stored", HarnessVersion.allowed(version, in: .lab) == version)
        }
        let other = HarnessVersion.allCases.first { $0 != usual } ?? usual
        expect("the harness in use is plain \"Harness\" in both", usual.label(in: .standard) == "Harness" && usual.label(in: .lab) == "Harness")
        expect("the lab names another version: \(other.label(in: .lab))", other.label(in: .lab) == "Harness \(other.short)")
        expect("standard only says it was an earlier one: \(other.label(in: .standard))", other.label(in: .standard) == "Harness (earlier version)")
        let named = [other.label(in: .standard), other.runTitle(in: .standard), other.runShort(in: .standard), other.runPhrase(in: .standard),
                     usual.runTitle(in: .standard), usual.runShort(in: .standard), usual.runPhrase(in: .standard)]
        expect("no standard label holds a version number: \(named)", !named.contains { $0.range(of: #"\bv\d"#, options: .regularExpression) != nil })
        expect("the lab's run labels are the old ones", other.runTitle(in: .lab) == other.title && other.runShort(in: .lab) == other.short && other.runPhrase(in: .lab) == other.title)
        expect("Dev: standard runs the agent in use when v2 is stored", DevHarnessVersion.allowed(.v2, in: .standard) == .recommended)
        expect("Dev: the lab runs v2 when it's stored", DevHarnessVersion.allowed(.v2, in: .lab) == .v2)
        expect("Dev: standard offers one, the lab both", DevHarnessVersion.offered(in: .standard) == [.recommended] && DevHarnessVersion.offered(in: .lab) == DevHarnessVersion.allCases)
        var side = DevCompareSide(folder: "/tmp/x/harness-on", harness: true, version: "v2")
        expect("a Dev comparison's side: \(side.title(in: .standard)) and \(side.title(in: .lab))", side.title(in: .standard) == "Harness on" && side.title(in: .lab) == "Harness v2")
        side.harness = false
        expect("the plain side is the same in both", side.title(in: .standard) == "Harness off" && side.title(in: .lab) == "Harness off")
        expect("an edition name that isn't one is the standard edition", (Edition(rawValue: "Lab") ?? .standard) == .standard && Edition(rawValue: "lab") == .lab)
        return lines
    }
    #endif
}
