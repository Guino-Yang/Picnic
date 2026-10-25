import Foundation
var checks = 0
func expect(_ ok: @autoclosure () -> Bool, _ message: String) {
    guard ok() else { fatalError(message) }; checks += 1
}
var p = BoostPolicy()
func sample(_ time: Double, _ lux: Double?, _ mode: Mode = .auto, _ allowed: Bool = true) -> Bool {
    p.update(mode: mode, lux: lux, thresholds: AutoThresholds(gentle: 2500, strong: 5000), allowed: allowed, now: time) != .off
}
expect(!sample(0, 3000), "No instant activation")
expect(!sample(2.99, 3000), "Do not enable before three seconds")
expect(sample(3, 3000), "Enable exactly at three seconds")
expect(sample(4, 2000), "Hysteresis keeps boost")
expect(sample(5, 1000), "No instant deactivation")
expect(sample(9.99, 1000), "Do not disable before five seconds")
expect(!sample(10, 1000), "Disable exactly at five seconds")
expect(!sample(11, 5000), "Start pending")
expect(!sample(12, 1000), "Transient bright event cancelled")
expect(!sample(13, 5000), "New dwell required")
expect(!sample(15.99, 5000), "Old dwell not reused")
expect(sample(16, 5000), "New dwell complete")
expect(!sample(17, nil), "Missing sensor fails closed")
expect(!sample(18, .nan), "NaN fails closed")
expect(!sample(19, -.infinity), "Invalid data fails closed")
expect(!sample(20, 300000), "Implausible data fails closed")
expect(sample(21, nil, .manual), "Manual does not need ALS or dwell")
expect(!sample(22, 5000, .manual, false), "Manual requires an eligible display")
expect(!sample(23, 5000, .off), "Off is unconditional")
expect(!sample(24, 5000, .auto, false), "No built-in display blocks auto")
expect(!sample(25, 5000), "Recovery requires fresh dwell")
expect(sample(28, 5000), "Recover after three seconds")
p.reset()
expect(!sample(29, 5000), "Reset clears dwell")
expect(!sample(30, 0), "Zero is darkness, not invalid")
p.reset()
expect(!sample(31, 2500), "Exact high threshold starts dwell")
expect(sample(34, 2500), "Exact high threshold enables")
expect(sample(35, 1500), "Exact low threshold starts dwell")
expect(!sample(40, 1500), "Exact low threshold disables")
print("PASS: \(checks) automatic-switching and display-availability checks")

let defaults = AutoThresholds()
expect(defaults.gentle == 1500 && defaults.strong == 3000, "User-selected two-tier defaults")
expect(AutoThresholds(gentle: .nan, strong: .infinity) == defaults, "Corrupt saved values use finite defaults")
expect(AutoThresholds(gentle: -100, strong: 9999) == AutoThresholds(gentle: 500, strong: 5000), "Clamp saved values to supported range")
expect(AutoThresholds(gentle: 5000, strong: 500) == AutoThresholds(gentle: 4750, strong: 5000), "Repair inverted thresholds with one-step separation")
expect(defaults.settingGentle(7000) == AutoThresholds(gentle: 2750, strong: 3000), "First slider cannot overtake second or change it")
expect(defaults.settingStrong(500) == AutoThresholds(gentle: 1500, strong: 1750), "Second slider cannot fall below first or change it")
expect(defaults.settingGentle(1750).gentle == 1750 && defaults.settingStrong(3250).strong == 3250, "Both sliders accept quarter-kilolux increments")
expect(defaults.settingGentle(1670).gentle == 1750, "Off-step inputs normalize to a valid step")

var tiers = BoostPolicy()
func tier(_ time: Double, _ lux: Double?, mode: Mode = .auto, thresholds: AutoThresholds = AutoThresholds(), allowed: Bool = true) -> BoostLevel {
    tiers.update(mode: mode, lux: lux, thresholds: thresholds, allowed: allowed, now: time)
}
expect(tier(0, 1500) == .off, "Gentle tier starts its own dwell")
expect(tier(2.99, 1500) == .off, "No early gentle activation")
expect(tier(3, 1500) == .gentle, "Exact first threshold enables 1.5x after three seconds")
expect(tier(4, 3000) == .gentle, "Keep gentle gain while strong tier is pending")
expect(tier(6.99, 3000) == .gentle, "No early strong activation")
expect(tier(7, 3000) == .strong, "Exact second threshold enables 2x after three seconds")
expect(tier(8, 2000) == .strong, "Strong tier hysteresis prevents brightness chatter")
expect(tier(9, 1800) == .strong, "Start downgrade at exact 60 percent boundary")
expect(tier(13.99, 1800) == .strong, "No early downgrade")
expect(tier(14, 1800) == .gentle, "Downgrade to 1.5x after five seconds")
expect(tier(15, 900) == .gentle, "Start disable at first release boundary")
expect(tier(19.99, 900) == .gentle, "No early removal of gentle boost")
expect(tier(20, 900) == .off, "Disable after five seconds below first release boundary")
tiers.reset()
expect(tier(30, 1600) == .off, "Begin gentle dwell")
expect(tier(31, 3100) == .off, "Strong dwell begins later")
expect(tier(33, 3100) == .gentle, "Do not reuse gentle dwell to turn on strong gain early")
expect(tier(34, 3100) == .strong, "Independent strong dwell finishes")
expect(tier(35, 0) == .strong, "Sudden darkness starts both release timers")
expect(tier(39.99, 0) == .strong, "Hold until darkness dwell completes")
expect(tier(40, 0) == .off, "Direct strong-to-off takes five seconds, not ten")
tiers.reset()
expect(tier(50, 6000) == .off && tier(53, 6000) == .strong, "Very bright environment can activate strong directly; 5000 is only the slider limit")
expect(tier(54, 1799) == .strong && tier(58, 1801) == .strong, "Brief shadow cancels downgrade")
expect(tier(60, 1799) == .strong && tier(64.99, 1799) == .strong, "A new shadow needs fresh dwell")
expect(tier(65, 1799) == .gentle, "Sustained shadow eventually downgrades")
expect(tier(66, 3100) == .gentle && tier(69, 3100) == .strong, "Strong gain can return after a downgrade")
let adjusted = AutoThresholds(gentle: 1500, strong: 4000)
expect(tier(70, 3500, thresholds: adjusted) == .strong, "Editing a slider does not momentarily drop an active boost")
expect(tier(71, 2000, thresholds: adjusted) == .strong, "Use the new release threshold")
let adjustedAgain = AutoThresholds(gentle: 1500, strong: 4250)
expect(tier(75, 2000, thresholds: adjustedAgain) == .strong, "A second edit cancels an obsolete pending timer")
expect(tier(79.99, 2000, thresholds: adjustedAgain) == .strong, "New settings get a full dwell")
expect(tier(80, 2000, thresholds: adjustedAgain) == .gentle, "New settings eventually apply")
for invalidLux: Double? in [nil, .nan, -.infinity, -1, 200001] {
    expect(tier(90, invalidLux) == .off, "Invalid sensors clear both tiers")
}
expect(tier(91, nil, mode: .manual) == .strong, "Manual remains fixed 2x independent of sensor")
expect(tier(92, 3500) == .off && tier(95, 3500) == .strong, "Returning to auto requires fresh dwell")
expect(tier(96, 3500, allowed: false) == .off, "Ineligible display clears both tiers")
expect(tier(97, 3500, mode: .off) == .off, "Explicit off is immediate")
print("PASS: \(checks) policy and threshold checks")

final class FakeTableIO: DisplayTableIO {
    var current: DisplayTable?
    var writes = 0
    var rejectWrites = false
    init(_ table: DisplayTable) { current = table }
    func read() -> DisplayTable? { current }
    func write(_ table: DisplayTable) -> Bool {
        guard !rejectWrites else { return false }
        current = table; writes += 1; return true
    }
}
let ramp = (0..<256).map { Float($0) / 255 }
let neutral = DisplayTable(red: ramp, green: ramp, blue: ramp)!
expect(DisplayTable(red: Array(repeating: 1, count: 1024), green: ramp, blue: ramp) == nil, "Never substitute advertised 1024 capacity for the working 256 entry format")
var invalid = ramp; invalid[70] = .nan
expect(DisplayTable(red: invalid, green: ramp, blue: ramp) == nil, "Reject corrupt table data")
expect(neutral.scaled(by: .infinity) == nil && neutral.scaled(by: 2.01) == nil, "Reject nonfinite or excessive gain")
let io = FakeTableIO(neutral)
let lease = DisplayGain(io: io)!
expect(lease.setGain(2) && io.current!.maximum == 2, "Keep values above SDR white")
expect(lease.setGain(2) && io.writes == 1, "Stable gain does not rewrite output")
expect(lease.refresh() && io.writes == 1, "Read-only integrity checks do not cause periodic writes")
expect(lease.setGain(1.5) && abs(io.current!.red[128] - ramp[128] * 1.5) < 0.0001, "Always scale original table, never compound previous gain")
expect(lease.restore() && io.current!.matches(neutral), "Disable restores the captured table")
expect(lease.restore() && io.writes == 3, "Restore is idempotent")
expect(!lease.setGain(2), "Closed lease cannot reapply boost")
let profile = DisplayTable(red: ramp, green: ramp.map {$0 * 0.8}, blue: ramp.map {$0 * 0.6})!
let changedIO = FakeTableIO(neutral)
let changed = DisplayGain(io: changedIO)!
_ = changed.setGain(2)
changedIO.current = profile
expect(changed.refresh() && changedIO.current!.matches(profile.scaled(by: 2)!), "Adopt a fresh system color table without losing its channel balance")
expect(changed.restore() && changedIO.current!.matches(profile), "Restore the newer system profile after a rebase")
let foreignIO = FakeTableIO(neutral)
let foreign = DisplayGain(io: foreignIO)!
_ = foreign.setGain(2)
let foreignTable = neutral.scaled(by: 1.4)!
foreignIO.current = foreignTable
expect(!foreign.refresh() && foreignIO.writes == 1, "Do not fight an unrecognized boosted table")
expect(!foreign.restore() && foreignIO.current!.matches(foreignTable), "Do not overwrite another utility's table during cleanup")
let failingIO = FakeTableIO(neutral)
let failing = DisplayGain(io: failingIO)!
failingIO.rejectWrites = true
expect(!failing.setGain(2) && failing.error != nil, "Surface write failure")
expect(failing.restore() && failingIO.current!.matches(neutral), "No successful write means no restore is needed")
let resetIO = FakeTableIO(neutral)
let resetLease = DisplayGain(io: resetIO)!
_ = resetLease.setGain(2)
for _ in 0..<3 { resetIO.current = neutral; expect(resetLease.refresh(), "Recover a limited number of system resets") }
resetIO.current = neutral
expect(!resetLease.refresh(), "Bound repeated write conflicts")
expect(resetLease.restore() && resetIO.current!.matches(neutral), "Leave a system-restored SDR table intact")
expect(DisplayGain(io: FakeTableIO(neutral.scaled(by: 2)!)) == nil, "Refuse to stack over another boost")
print("PASS: \(checks) total policy and output-table checks")
