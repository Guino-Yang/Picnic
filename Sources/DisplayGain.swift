import CoreGraphics
import Foundation

// Use 256 entries deliberately. On the tested M1 Pro/macOS 27, a 1024-entry
// upload (the advertised capacity) read back clamped, while 256 retained 2x.
struct DisplayTable {
    static let sampleCount = 256
    let red: [Float]
    let green: [Float]
    let blue: [Float]

    init?(red: [Float], green: [Float], blue: [Float]) {
        guard [red, green, blue].allSatisfy({ $0.count == Self.sampleCount && $0.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 16 } }) else { return nil }
        self.red = red; self.green = green; self.blue = blue
    }
    var maximum: Float { max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0) }
    var isSDR: Bool { maximum > 0 && maximum <= 1.003 }
    func scaled(by gain: Float) -> DisplayTable? {
        guard gain.isFinite, (1...2).contains(gain) else { return nil }
        return DisplayTable(red: red.map { $0 * gain }, green: green.map { $0 * gain }, blue: blue.map { $0 * gain })
    }
    func matches(_ other: DisplayTable) -> Bool {
        zip(red, other.red).allSatisfy { abs($0 - $1) <= 0.003 }
            && zip(green, other.green).allSatisfy { abs($0 - $1) <= 0.003 }
            && zip(blue, other.blue).allSatisfy { abs($0 - $1) <= 0.003 }
    }
}

protocol DisplayTableIO {
    func read() -> DisplayTable?
    func write(_ table: DisplayTable) -> Bool
}

final class InternalDisplayTableIO: DisplayTableIO {
    private let display: CGDirectDisplayID
    init?(display: CGDirectDisplayID) {
        guard CGDisplayIsBuiltin(display) != 0, CGDisplayIsInMirrorSet(display) == 0 else { return nil }
        self.display = display
    }
    func read() -> DisplayTable? {
        var red = [Float](repeating: 0, count: DisplayTable.sampleCount), green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, UInt32(DisplayTable.sampleCount), &red, &green, &blue, &count) == .success,
              count == DisplayTable.sampleCount else { return nil }
        return DisplayTable(red: red, green: green, blue: blue)
    }
    func write(_ table: DisplayTable) -> Bool {
        var red = table.red, green = table.green, blue = table.blue
        return CGSetDisplayTransferByTable(display, UInt32(DisplayTable.sampleCount), &red, &green, &blue) == .success
    }
}

// Own only the selected display's temporary table; never reset other displays.
final class DisplayGain {
    private let io: DisplayTableIO
    private var baseline: DisplayTable
    private var applied: DisplayTable?
    private var ended = false
    private var consecutiveRecoveries = 0
    private(set) var gain: Float = 1
    private(set) var writeCount = 0
    private(set) var recoveryCount = 0
    private(set) var error: String?

    init?(io: DisplayTableIO) {
        guard let original = io.read(), original.isSDR else { return nil }
        self.io = io; baseline = original
    }
    @discardableResult func setGain(_ value: Float) -> Bool {
        guard !ended, let target = baseline.scaled(by: value) else { return false }
        if let applied, applied.matches(target) { gain = value; return true }
        guard io.write(target) else { error = "无法写入内屏输出表，增强已停止"; return false }
        gain = value; applied = target; writeCount += 1
        return true
    }
    func refresh() -> Bool {
        guard !ended else { return false }
        guard let expected = applied else { return true }
        guard let current = io.read() else { error = "无法读取内屏输出表，增强已停止"; return false }
        if current.matches(expected) { consecutiveRecoveries = 0; return true }
        // A fresh SDR table can be supplied by ColorSync (e.g. a display-setting
        // change). Rebase once, never multiply our previous 2x table by 2 again.
        guard current.isSDR, consecutiveRecoveries < 3 else {
            error = "内屏输出表持续被改写，增强已停止"; return false
        }
        baseline = current
        applied = nil
        consecutiveRecoveries += 1; recoveryCount += 1
        return setGain(gain)
    }
    @discardableResult func restore() -> Bool {
        guard !ended else { return true }
        ended = true
        guard let expected = applied else { return true }
        guard let current = io.read() else { return false }
        if current.matches(baseline) { return true }
        // Respect a newer table owned by macOS or another utility.
        guard current.matches(expected) else { return current.isSDR }
        guard io.write(baseline), let restored = io.read() else { return false }
        return restored.matches(baseline)
    }
    var diagnostics: [String: Any] {
        ["tableSamples": DisplayTable.sampleCount, "tableGain": gain,
         "tableMaximum": io.read().map { $0.maximum as Any } ?? NSNull(),
         "tableWrites": writeCount, "tableRecoveries": recoveryCount]
    }
    deinit { restore() }
}
