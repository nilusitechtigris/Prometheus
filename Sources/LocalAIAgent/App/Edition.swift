import Foundation

/// Which edition this copy is. Everyone gets the standard one: one harness, on or off, with no versions to
/// choose. The lab keeps every version of the harness to use in chat and to test, for comparing them.
///
/// There's no control for it in the app. There are two ways to be the lab:
///
/// - The private app, "Prometheus Lab", is the lab by the way it is built: `EDITION=lab scripts/build-app.sh`
///   gives it its own name, its own icon and the `PrometheusEdition` key this reads. It isn't updated by the
///   Update button, which builds the public app (see `isLabBuild`).
/// - A copy of the public app becomes the lab at launch from a setting that only someone who knows of it
///   writes, `defaults write com.localaiagent.app edition lab`, or from `-edition lab` when the app is started.
///   That survives Update, which builds every public copy the same way from the same source.
///
/// This hides the versions. It doesn't lock them: the setting is here to read.
enum Edition: String {
    case standard, lab

    /// Whether this copy was built as the private app. True only for "Prometheus Lab".
    static let isLabBuild = (Bundle.main.object(forInfoDictionaryKey: "PrometheusEdition") as? String) == Edition.lab.rawValue

    static let current: Edition = {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["LOCALAI_EDITION"].flatMap(Edition.init(rawValue:)) { return forced }
        #endif
        if isLabBuild { return .lab }
        return Edition(rawValue: UserDefaults.standard.string(forKey: "edition") ?? "") ?? .standard
    }()

    var isLab: Bool { self == .lab }

    #if DEBUG
    /// What each edition offers, runs and calls a version. None of it needs a model.
    @MainActor
    static func selfCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        expect("Publish is a tab in the lab only", TestTab.shown(in: .lab).contains(.publish) && !TestTab.shown(in: .standard).contains(.publish))
        expect("every test is a tab in both", [TestTab.overview, .model, .hardware, .harness].allSatisfy { TestTab.shown(in: .standard).contains($0) && TestTab.shown(in: .lab).contains($0) })
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
        expect("standard only says it was another one: \(other.label(in: .standard))", other.label(in: .standard) == "Harness (another version)")
        let named = [other.label(in: .standard), other.runTitle(in: .standard), other.runShort(in: .standard), other.runPhrase(in: .standard),
                     usual.runTitle(in: .standard), usual.runShort(in: .standard), usual.runPhrase(in: .standard)]
        expect("no standard label holds a version number: \(named)", !named.contains { $0.range(of: #"\bv\d"#, options: .regularExpression) != nil })
        expect("the lab's run labels are the old ones", other.runTitle(in: .lab) == other.title && other.runShort(in: .lab) == other.short && other.runPhrase(in: .lab) == other.title)
        expect("Dev: standard runs the agent in use when v2 is stored", DevHarnessVersion.allowed(.v2, in: .standard) == .recommended)
        expect("Dev: the lab runs v2 when it's stored", DevHarnessVersion.allowed(.v2, in: .lab) == .v2)
        expect("Dev: standard offers one, the lab both", DevHarnessVersion.offered(in: .standard) == [.recommended] && DevHarnessVersion.offered(in: .lab) == DevHarnessVersion.allCases)
        var side = DevCompareSide(folder: "/tmp/x/harness-on", harness: true, version: DevHarnessVersion.recommended.rawValue)
        expect("a Dev comparison built by the agent in use: \(side.title(in: .standard)) and \(side.title(in: .lab))",
               side.title(in: .standard) == "Harness on" && side.title(in: .lab) == "Harness \(DevHarnessVersion.recommended.rawValue)" && side.summary(in: .standard) == DevHarnessVersion.recommended.summary)
        side.version = nil
        expect("an older record that names no version is the agent in use", side.title(in: .standard) == "Harness on" && side.title(in: .lab) == "Harness on")
        if let another = DevHarnessVersion.allCases.first(where: { $0 != .recommended }) {
            side.version = another.rawValue
            expect("one built by another version only says so: \(side.title(in: .standard)), \(side.summary(in: .standard))",
                   side.title(in: .standard) == "Another harness" && side.summary(in: .standard).range(of: #"\bv\d"#, options: .regularExpression) == nil
                       && side.title(in: .lab) == "Harness \(another.rawValue)" && side.summary(in: .lab) == another.summary)
        }
        side.harness = false
        expect("the plain side is the same in both", side.title(in: .standard) == "Harness off" && side.title(in: .lab) == "Harness off" && side.summary(in: .standard) == side.summary(in: .lab))
        // A copy that had another version and more rounds stored by an earlier build: what runs follows the edition
        // this copy is, and the stored choice is still there afterwards.
        let defaults = UserDefaults.standard
        let kept = (defaults.object(forKey: "harnessVersion"), defaults.object(forKey: "harnessMaxRounds"))
        defaults.set(other.rawValue, forKey: "harnessVersion")
        defaults.set(5, forKey: "harnessMaxRounds")
        let settings = AppSettings()
        expect("a stored version and rounds are read as they were", settings.harnessVersion == other && settings.harnessMaxRounds == 5)
        expect("this copy (\(current.rawValue)) runs \(settings.activeHarness.short) for \(settings.activeRounds) rounds with \(other.short) and 5 stored",
               settings.activeHarness == (current.isLab ? other : usual) && settings.activeRounds == (current.isLab ? 5 : AppSettings.usualHarnessRounds))
        expect("reading them wrote nothing over the stored choice", defaults.string(forKey: "harnessVersion") == other.rawValue && defaults.integer(forKey: "harnessMaxRounds") == 5)
        for (key, value) in [("harnessVersion", kept.0), ("harnessMaxRounds", kept.1)] {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        expect("an edition name that isn't one is the standard edition", (Edition(rawValue: "Lab") ?? .standard) == .standard && Edition(rawValue: "lab") == .lab)
        return lines
    }
    #endif
}
