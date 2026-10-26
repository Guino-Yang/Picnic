import Foundation

enum Mode: String, CaseIterable { case off, auto, manual
    var title: String { switch self { case .off: return L10n.text(.modeOff); case .auto: return L10n.text(.modeAuto); case .manual: return L10n.text(.modeManual) } }
}

enum BoostLevel: Double {
    case off = 1, gentle = 1.5, strong = 2
    var label: String { self == .gentle ? "1.5×" : self == .strong ? "2×" : L10n.text(.boostOff) }
}

struct AutoThresholds: Equatable {
    static let range: ClosedRange<Double> = 500...5000
    static let step: Double = 250
    let gentle: Double
    let strong: Double
    init(gentle: Double = 1500, strong: Double = 3000) {
        self.gentle = Self.clamp(gentle, fallback: 1500, range: 500...4750)
        self.strong = Self.clamp(strong, fallback: 3000, range: (self.gentle + Self.step)...5000)
    }
    private static func clamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        let rounded = ((value.isFinite ? value : fallback) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, rounded))
    }
    var gentleRange: ClosedRange<Double> { 500...(strong - Self.step) }
    var strongRange: ClosedRange<Double> { (gentle + Self.step)...5000 }
    func settingGentle(_ value: Double) -> Self {
        Self(gentle: Self.clamp(value, fallback: gentle, range: gentleRange), strong: strong)
    }
    func settingStrong(_ value: Double) -> Self {
        Self(gentle: gentle, strong: Self.clamp(value, fallback: strong, range: strongRange))
    }
}

private struct LuxGate {
    private(set) var enabled = false
    private var pendingSince: TimeInterval?
    private var pendingTarget: Bool?
    mutating func cancelPending() { pendingSince = nil; pendingTarget = nil }
    mutating func update(lux: Double, threshold: Double, now: TimeInterval) -> Bool {
        let target = enabled ? lux > threshold * BoostPolicy.releaseRatio : lux >= threshold
        guard target != enabled else { cancelPending(); return enabled }
        if pendingTarget != target { pendingTarget = target; pendingSince = now }
        if now - (pendingSince ?? now) >= (target ? BoostPolicy.enableDelay : BoostPolicy.disableDelay) {
            enabled = target; cancelPending()
        }
        return enabled
    }
}

struct BoostPolicy {
    static let enableDelay: TimeInterval = 3
    static let disableDelay: TimeInterval = 5
    static let releaseRatio = 0.6
    private(set) var level: BoostLevel = .off
    private var gentleGate = LuxGate()
    private var strongGate = LuxGate()
    private var previousThresholds: AutoThresholds?
    mutating func reset() {
        level = .off; gentleGate = LuxGate(); strongGate = LuxGate(); previousThresholds = nil
    }
    mutating func update(mode: Mode, lux: Double?, thresholds: AutoThresholds, allowed: Bool, now: TimeInterval) -> BoostLevel {
        guard allowed, mode != .off else { reset(); return .off }
        if mode == .manual { reset(); level = .strong; return level }
        guard let lux, lux.isFinite, lux >= 0, lux <= 200000 else { reset(); return .off }
        if previousThresholds != thresholds {
            // A slider edit restarts dwell timers without momentarily removing
            // an already active boost. Each tier keeps its own hysteresis.
            gentleGate.cancelPending(); strongGate.cancelPending(); previousThresholds = thresholds
        }
        let gentle = gentleGate.update(lux: lux, threshold: thresholds.gentle, now: now)
        let strong = strongGate.update(lux: lux, threshold: thresholds.strong, now: now)
        level = strong ? .strong : gentle ? .gentle : .off
        return level
    }
}
