import Observation
import SwiftUI

/// Traffic-light classification used by every metric in the app.
enum HealthLevel: Int, Comparable {
    case good, warning, critical, unknown

    static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .good: return Palette.good
        case .warning: return Palette.warning
        case .critical: return Palette.critical
        case .unknown: return .secondary
        }
    }

    var label: String {
        switch self {
        case .good: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "High"
        case .unknown: return "N/A"
        }
    }
}

enum Palette {
    // Status colours stay fixed so green / yellow / red always mean the same thing.
    static let good = Color(red: 0.55, green: 0.86, blue: 0.2)
    static let warning = Color(red: 1.00, green: 0.76, blue: 0.03)
    static let critical = Color(red: 1.00, green: 0.27, blue: 0.23)

    // Brand colours follow the selected theme (reading them registers an Observation dependency).
    @MainActor static var accent: Color { ThemeStore.shared.theme.accent }
    @MainActor static var accent2: Color { ThemeStore.shared.theme.accent2 }
    @MainActor static var glow: Color { ThemeStore.shared.theme.glow }
    @MainActor static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .top, endPoint: .bottom)
    }
    /// Text and icons on the accent colour.
    @MainActor static var onAccent: Color { ThemeStore.shared.theme.onAccent }
}

/// The two looks of the app. Both are dark: Ember is amber on blue-black, Rose is pink on plum-black.
/// Each has its own flame picture (see `Art.flame(for:)`).
enum AppTheme: String, CaseIterable, Identifiable {
    case ember, rose

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ember: return "Ember"
        case .rose: return "Rose"
        }
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var accent: Color { Self.hex(self == .ember ? 0xF5A25A : 0xFF8FBE) }
    var accent2: Color { Self.hex(self == .ember ? 0xE9873A : 0xF56FAA) }
    /// The flame's light on the window behind everything.
    var glow: Color { accent }
    /// Text and icons on the accent colour.
    var onAccent: Color { Self.hex(self == .ember ? 0x1D1003 : 0x2B0A18) }
    /// Behind the whole window.
    var canvas: Color { Self.hex(canvasHex) }
    var canvasHex: UInt32 { self == .ember ? 0x080B11 : 0x130A12 }
    /// Behind each page.
    var panel: Color { Self.hex(self == .ember ? 0x0D111A : 0x1A0E18) }
    /// Cards on a page.
    var card: Color { Self.hex(self == .ember ? 0x161B27 : 0x261522) }
    /// The file name of this theme's flame in assets/art.
    var flameArt: String { self == .ember ? "flame-ember" : "flame-rose" }
}

@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    private init() {
        let defaults = UserDefaults.standard
        // `AppSettings` reads this key to tell a copy that has run before from a new install.
        defaults.set(true, forKey: "movedToPrometheusTheme")
        // A theme saved by an older copy (lime, Aurora and the rest) no longer exists, so it becomes Ember.
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .ember
    }
}

/// A green → yellow → red band. When `higherIsWorse` is false (e.g. tokens/sec) the bands are flipped.
struct Threshold {
    let warning: Double
    let critical: Double
    var higherIsWorse = true
    /// Upper end of the visual range bar.
    let displayMax: Double
    var displayMin: Double = 0

    /// Where the yellow and red parts of the bar start, in words, for a tooltip.
    func scaleNote(unit: String) -> String {
        higherIsWorse ? "The bar turns yellow at \(Int(warning))\(unit) and red at \(Int(critical))\(unit)."
                      : "The bar turns yellow below \(Int(warning))\(unit) and red below \(Int(critical))\(unit)."
    }

    func level(_ value: Double?) -> HealthLevel {
        guard let value, value.isFinite else { return .unknown }
        if higherIsWorse {
            if value >= critical { return .critical }
            if value >= warning { return .warning }
            return .good
        } else {
            if value <= critical { return .critical }
            if value <= warning { return .warning }
            return .good
        }
    }
}

enum Thresholds {
    // Utilisation, percent
    static let cpuUsage = Threshold(warning: 60, critical: 85, displayMax: 100)
    static let gpuUsage = Threshold(warning: 60, critical: 85, displayMax: 100)
    static let memoryUsage = Threshold(warning: 70, critical: 85, displayMax: 100)

    // Temperatures, °C — Apple Silicon throttles around 100–105 °C junction temperature.
    static let cpuTemp = Threshold(warning: 70, critical: 90, displayMax: 110, displayMin: 20)
    static let gpuTemp = Threshold(warning: 70, critical: 90, displayMax: 110, displayMin: 20)
    static let memoryTemp = Threshold(warning: 60, critical: 80, displayMax: 100, displayMin: 20)

    // Generation speed
    static let timeToFirstToken = Threshold(warning: 1.0, critical: 3.0, displayMax: 6)
    static let tokensPerSecond = Threshold(warning: 15, critical: 7, higherIsWorse: false, displayMax: 60)

    static func describe(_ t: Threshold, unit: String, decimals: Int = 0) -> String {
        let w = String(format: "%.\(decimals)f", t.warning)
        let c = String(format: "%.\(decimals)f", t.critical)
        if t.higherIsWorse {
            return "Green < \(w)\(unit) · Yellow \(w)–\(c)\(unit) · Red ≥ \(c)\(unit)"
        }
        return "Green > \(w)\(unit) · Yellow \(c)–\(w)\(unit) · Red ≤ \(c)\(unit)"
    }
}
