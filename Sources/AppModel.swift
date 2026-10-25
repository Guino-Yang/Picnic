import AppKit
import SwiftUI

final class AppModel: ObservableObject {
    static let thresholdsKey = "autoThresholdsV2"
    @Published var mode: Mode = .off { didSet { policy.reset(); renderError = nil; tick() } }
    @Published private(set) var thresholds: AutoThresholds
    @Published private(set) var boostLevel: BoostLevel = .off
    var gain: Double { boostLevel.rawValue }
    @Published private(set) var lux: Double?
    @Published private(set) var active = false
    @Published private(set) var status = "正在检查内屏…"
    @Published private(set) var screenName = "未检测到 MacBook 内屏"
    @Published private(set) var headroom: Double = 1
    @Published private(set) var hasInternalScreen = false
    var onChange: (() -> Void)?
    private var policy = BoostPolicy()
    private var overlay: BoostOverlay?
    private var screenID: CGDirectDisplayID?
    private var timer: Timer?
    private var ramp: Timer?
    private var currentGain = 1.0
    private var rampTarget = 1.0
    private let readLux: () -> Double
    private var displaySignature = ""
    private var overlayCreations = 0
    private var renderError: String?
    private var lastRestoreSucceeded: Bool?
    private var ticking = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(initialMode: Mode = .auto, readLux: @escaping () -> Double = { sunlift_read_lux() }) {
        self.readLux = readLux
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: Self.thresholdsKey) {
            thresholds = AutoThresholds(gentle: saved["gentle"] as? Double ?? 1500, strong: saved["strong"] as? Double ?? 3000)
        } else {
            // Start the two-tier configuration at 1500/3000. Preserve later
            // adjustments as one atomic pair, separate from legacy settings.
            thresholds = AutoThresholds()
        }
        if initialMode != .off { saveThresholds() }
        // Ordinary launches start in automatic mode using the saved threshold.
        // Read-only diagnostics and smoke tests explicitly request .off.
        displaySignature = currentDisplaySignature()
        mode = initialMode
        tick()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.025
        RunLoop.main.add(t, forMode: .common); timer = t
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.displayChanged() }
        let nc = NSWorkspace.shared.notificationCenter
        // No thermal, power, lock or sleep inhibition. Recreate compositor
        // resources after wake/unlock while keeping the requested mode.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(nc, name) { [weak self] in self?.rebuild() }
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.rebuild() }
    }
    private func saveThresholds() {
        UserDefaults.standard.set(["gentle": thresholds.gentle, "strong": thresholds.strong], forKey: Self.thresholdsKey)
    }
    func setGentleThreshold(_ value: Double) { updateThresholds(thresholds.settingGentle(value)) }
    func setStrongThreshold(_ value: Double) { updateThresholds(thresholds.settingStrong(value)) }
    private func updateThresholds(_ next: AutoThresholds) {
        guard next != thresholds else { return }
        thresholds = next; saveThresholds(); tick()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }
    private func rebuild() { stop(); renderError = nil; tick() }

    private func currentDisplaySignature() -> String {
        // Only a changed target or geometry requires a new window. EDR headroom
        // and unrelated external-display notifications are not topology changes.
        NSScreen.screens.filter { $0.isInternal }.map { "\($0.displayID):\($0.frame):\($0.backingScaleFactor)" }.joined(separator: ";")
    }
    private func displayChanged() {
        let signature = currentDisplaySignature()
        if signature != displaySignature { displaySignature = signature; rebuild() }
        else { tick() }
    }
    func tick() {
        guard !ticking else { return }; ticking = true
        defer { ticking = false }
        let sensor = readLux()
        lux = sensor.isFinite ? sensor : nil
        let screen = NSScreen.screens.first(where: { $0.isInternal })
        hasInternalScreen = screen != nil
        screenName = screen?.localizedName ?? "未检测到 MacBook 内屏"
        headroom = screen.map { Double($0.maximumExtendedDynamicRangeColorComponentValue) } ?? 1
        var reason: String?
        if screen == nil { reason = "请打开 MacBook 内屏；外接屏不会被增强" }
        else if screen?.supportsBoost != true { reason = "内屏 EDR 不可用，或当前正在镜像显示" }
        else if let renderError { reason = renderError }
        let requestedLevel = policy.update(mode: mode, lux: lux, thresholds: thresholds, allowed: reason == nil, now: ProcessInfo.processInfo.systemUptime)
        if requestedLevel != .off, let screen {
            if overlay == nil || screenID != screen.displayID {
                stop()
                overlay = BoostOverlay(screen: screen)
                if overlay != nil { overlayCreations += 1 }
                screenID = screen.displayID
                overlay?.onError = { [weak self] message in
                    DispatchQueue.main.async { self?.renderError = message; self?.policy.reset(); self?.stop(); self?.status = message; self?.onChange?() }
                }
            }
            if overlay != nil {
                active = true
                boostLevel = requestedLevel
                overlay?.maintain()
                let target = requestedLevel.rawValue
                if rampTarget != target || (ramp == nil && abs(currentGain-target) > 0.01) { startRamp(to: target) }
                // Sensor polling changes no drawables; MTKView independently maintains EDR at 5 fps.
                status = "\(mode == .auto ? "自动" : "手动") · \(requestedLevel.label) 增强中"
            } else { status = "无法初始化内屏增强，请先关闭其他调光工具"; active = false }
        } else {
            stop()
            if mode == .off { status = "增强已关闭" }
            else if let reason { status = reason }
            else if lux == nil { status = "环境光读数不可用，自动增强已暂停" }
            else { status = "自动待命 · 等待持续明亮环境" }
        }
        onChange?()
    }
    private func startRamp(to target: Double) {
        ramp?.invalidate()
        rampTarget = target
        let start = currentGain, began = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = min(1, (ProcessInfo.processInfo.systemUptime-began)/2)
            self.currentGain = start + (target-start)*p
            self.overlay?.setGain(self.currentGain)
            if p >= 1 { self.ramp?.invalidate(); self.ramp = nil }
        }
        RunLoop.main.add(t, forMode: .common); ramp = t
    }
    private func stop() {
        ramp?.invalidate(); ramp = nil
        if let overlay { lastRestoreSucceeded = overlay.close() }
        overlay = nil; screenID = nil; currentGain = 1; rampTarget = 1; active = false; boostLevel = .off
    }
    func shutdown() {
        mode = .off; timer?.invalidate(); timer = nil; stop()
        for (center, token) in observers { center.removeObserver(token) }; observers.removeAll()
    }
    func diagnostics() -> [String: Any] {
        ["version": "2.0.0", "os": ProcessInfo.processInfo.operatingSystemVersionString,
         "mode": mode.rawValue, "active": active, "status": status,
         "gentleThresholdLux": thresholds.gentle, "strongThresholdLux": thresholds.strong,
         "disableThresholdLux": thresholds.gentle * BoostPolicy.releaseRatio,
         "downgradeThresholdLux": thresholds.strong * BoostPolicy.releaseRatio,
         "thresholdMinimumLux": AutoThresholds.range.lowerBound, "thresholdMaximumLux": AutoThresholds.range.upperBound,
         "thresholdStepLux": AutoThresholds.step, "currentGain": currentGain,
         "ambientLux": lux.map { $0 as Any } ?? NSNull(), "boostGain": gain,
         "metalAvailable": MTLCreateSystemDefaultDevice() != nil,
         "submittedFrames": overlay?.submittedFrames ?? 0,
         "completedFrames": overlay?.completedFrames ?? 0,
         "failedFrames": overlay?.failedFrames ?? 0,
         "unavailableDrawables": overlay?.unavailableDrawables ?? 0,
         "lastCompletedFrameAgeSeconds": overlay?.frameAge.map { $0 as Any } ?? NSNull(),
         "renderFPS": 5, "renderTexturePixels": 1,
         "backend": "display-table-256-with-edr-pin",
         "transfer": overlay?.tableDiagnostics ?? [:],
         "lastRestoreSucceeded": lastRestoreSucceeded.map { $0 as Any } ?? NSNull(),
         "triggerWidth": overlay.map { $0.window.frame.width as Any } ?? NSNull(),
         "triggerHeight": overlay.map { $0.window.frame.height as Any } ?? NSNull(),
         "overlayCreations": overlayCreations,
         "overlayWindowLevel": overlay.map { $0.window.level.rawValue as Any } ?? NSNull(),
         "systemShieldingLevel": Int(CGShieldingWindowLevel()),
         "popupMenuLevel": Int(CGWindowLevelForKey(.popUpMenuWindow)),
         "overlayVisible": overlay?.window.isVisible ?? false,
         "overlayMousePassthrough": overlay?.window.ignoresMouseEvents ?? false,
         "overlayCanBecomeKey": overlay?.window.canBecomeKey ?? false,
         "overlayStationary": overlay?.window.collectionBehavior.contains(.stationary) ?? false,
         "overlayAllApplications": overlay?.window.collectionBehavior.contains(.canJoinAllApplications) ?? false,
         "enableDelaySeconds": BoostPolicy.enableDelay, "disableDelaySeconds": BoostPolicy.disableDelay,
         "screens": NSScreen.screens.map { ["name": $0.localizedName, "builtIn": $0.isInternal, "eligible": $0.supportsBoost,
            "currentEDR": $0.maximumExtendedDynamicRangeColorComponentValue,
            "potentialEDR": $0.maximumPotentialExtendedDynamicRangeColorComponentValue] as [String: Any] }]
    }
}
