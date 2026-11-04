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
    static let good = Color(red: 0.20, green: 0.78, blue: 0.40)
    static let warning = Color(red: 1.00, green: 0.76, blue: 0.03)
    static let critical = Color(red: 1.00, green: 0.27, blue: 0.23)

    // Brand colours follow the selected theme (reading them registers an Observation dependency).
    @MainActor static var accent: Color { ThemeStore.shared.theme.accent }
    @MainActor static var accent2: Color { ThemeStore.shared.theme.accent2 }
    @MainActor static var glow: Color { ThemeStore.shared.theme.glow }
    @MainActor static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case prometheus, aurora, ocean, ember, orchid, mint, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .prometheus: return "Prometheus"
        case .aurora: return "Aurora"
        case .ocean: return "Ocean"
        case .ember: return "Ember"
        case .orchid: return "Orchid"
        case .mint: return "Mint"
        case .graphite: return "Graphite"
        }
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var accent: Color {
        switch self {
        case .prometheus: return Self.hex(0x3B8BFF)
        case .aurora: return Self.hex(0x6366F1)
        case .ocean: return Self.hex(0x0A84FF)
        case .ember: return Self.hex(0xFF6B3D)
        case .orchid: return Self.hex(0xBF5AF2)
        case .mint: return Self.hex(0x00C7A3)
        case .graphite: return Self.hex(0x8E8E93)
        }
    }

    var accent2: Color {
        switch self {
        case .prometheus: return Self.hex(0x6AB8FF)
        case .aurora: return Self.hex(0x22D3EE)
        case .ocean: return Self.hex(0x5AC8FA)
        case .ember: return Self.hex(0xFF2D78)
        case .orchid: return Self.hex(0xFF6FB5)
        case .mint: return Self.hex(0x30B0FF)
        case .graphite: return Self.hex(0x5E5CE6)
        }
    }

    /// Third colour used only in the ambient background.
    var glow: Color {
        switch self {
        case .prometheus: return Self.hex(0x123A9C)
        case .aurora: return Self.hex(0xA855F7)
        case .ocean: return Self.hex(0x30D5C8)
        case .ember: return Self.hex(0xFFB340)
        case .orchid: return Self.hex(0x6E5BFF)
        case .mint: return Self.hex(0x7ED957)
        case .graphite: return Self.hex(0x636366)
        }
    }
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
        // Aurora was the default before this brand, so it moves over once. Any other pick is kept.
        if defaults.string(forKey: "theme") == AppTheme.aurora.rawValue, !defaults.bool(forKey: "movedToPrometheusTheme") {
            defaults.set(AppTheme.prometheus.rawValue, forKey: "theme")
        }
        defaults.set(true, forKey: "movedToPrometheusTheme")
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .prometheus
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
    static let contextUsage = Threshold(warning: 70, critical: 90, displayMax: 100)

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
