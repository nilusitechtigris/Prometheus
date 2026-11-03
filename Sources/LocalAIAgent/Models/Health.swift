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
    static let good = Color(red: 0.20, green: 0.78, blue: 0.40)
    static let warning = Color(red: 1.00, green: 0.76, blue: 0.03)
    static let critical = Color(red: 1.00, green: 0.27, blue: 0.23)
    static let accent = Color(red: 0.36, green: 0.42, blue: 0.98)
    static let accent2 = Color(red: 0.12, green: 0.74, blue: 0.80)
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
