import AppKit
import SwiftUI

struct MenuSummary: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("🧺 Picnic").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.boostLevel.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Text(model.lux.map { String(format: "环境光 %.0f lx · 仅内屏", $0) } ?? "环境光不可用 · 仅内屏")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).frame(width: 286, height: 70)
    }
}

struct ThresholdControl: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("1.5× 轻增强")
                Spacer()
                Text("\(Int(model.thresholds.gentle)) lx").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 12))
            Slider(value: Binding(get: { model.thresholds.gentle }, set: model.setGentleThreshold), in: model.thresholds.gentleRange, step: AutoThresholds.step)
                .controlSize(.small).accessibilityLabel("1.5倍增强开启阈值")
            HStack {
                Text("2× 强增强")
                Spacer()
                Text("\(Int(model.thresholds.strong)) lx").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.top, 6)
            Slider(value: Binding(get: { model.thresholds.strong }, set: model.setStrongThreshold), in: model.thresholds.strongRange, step: AutoThresholds.step)
                .controlSize(.small).accessibilityLabel("2倍增强开启阈值")
            Text("升档持续 3 秒 · 降档持续 5 秒")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("≤\(Int(model.thresholds.gentle * 0.6)) lx 关闭 · ≤\(Int(model.thresholds.strong * 0.6)) lx 降为 1.5×")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.horizontal, 14).frame(width: 286, height: 154)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var model: AppModel!
    let loginItems = LoginItems()
    var item: NSStatusItem!
    let menu = NSMenu()
    var modeItems: [NSMenuItem] = []
    var loginItem: NSMenuItem!
    var approvalItem: NSMenuItem!
    var loginErrorItem: NSMenuItem!
    var summaryView: NSView!
    var signalSources: [DispatchSourceSignal] = []
    private var testLux = 0.0
    private static let outlineBasket = basketIcon("basket")
    private static let filledBasket = basketIcon("basket.fill")
    private static func basketIcon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Picnic 亮度增强")?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        image?.size = NSSize(width: 20, height: 17)
        image?.isTemplate = true
        return image
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let tierTest = CommandLine.arguments.contains("--test-auto-tiers")
        let testing = tierTest || CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--test-boost") || CommandLine.arguments.contains("--test-system-ui")
        model = tierTest ? AppModel(initialMode: .off, readLux: { [weak self] in self?.testLux ?? .nan }) : AppModel(initialMode: testing ? .off : .auto)
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume(); signalSources.append(source)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureMenu()
        // Keep the timed integration fixture stable while still showing both
        // icon states. Ordinary launches retain the interactive native menu.
        item.menu = tierTest ? nil : menu
        model.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
        if tierTest {
            runTierTest()
        } else if CommandLine.arguments.contains("--test-boost") || CommandLine.arguments.contains("--test-system-ui") {
            guard model.hasInternalScreen else { print("No internal display: boost test refused"); NSApp.terminate(nil); return }
            let testDuration = CommandLine.arguments.contains("--test-system-ui") ? 75.0 : 45.0
            model.mode = .manual
            var baseline: [String: Any]?
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                baseline = self?.model.diagnostics()
                print("Stability baseline after ramp:")
                self?.printDiagnostics()
            }
            for seconds in [15.0, 30.0, 60.0].filter({ $0 < testDuration }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                    print("Continuous-rendering checkpoint at \(Int(seconds)) seconds:")
                    self?.printDiagnostics()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + testDuration) { [weak self] in
                guard let self else { return }
                self.printDiagnostics()
                let end = self.model.diagnostics()
                let stable = (baseline?["active"] as? Bool == true) && (end["active"] as? Bool == true)
                    && ((end["completedFrames"] as? Int ?? 0) - (baseline?["completedFrames"] as? Int ?? 0) >= 100)
                    && (end["failedFrames"] as? Int == 0)
                    && (end["lastCompletedFrameAgeSeconds"] as? Double ?? 999) < 1
                    && (baseline?["overlayCreations"] as? Int == end["overlayCreations"] as? Int)
                    && (end["overlayMousePassthrough"] as? Bool == true)
                    && (end["overlayCanBecomeKey"] as? Bool == false)
                    && (end["overlayStationary"] as? Bool == true)
                    && (end["overlayAllApplications"] as? Bool == true)
                    && (end["overlayWindowLevel"] as? Int ?? 0) > (end["popupMenuLevel"] as? Int ?? 0)
                let transfer = end["transfer"] as? [String: Any]
                let tableValid = transfer?["tableSamples"] as? Int == 256
                    && (transfer?["tableMaximum"] as? Float ?? 0) > 1.9
                    && (transfer?["tableMaximum"] as? Float ?? 99) < 2.01
                self.model.mode = .off
                let restored = self.model.diagnostics()["lastRestoreSucceeded"] as? Bool == true
                print("Output table valid=\(tableValid), original table restored=\(restored)")
                print(stable && tableValid && restored ? "PASS: \(Int(testDuration))-second test maintained rendering, HDR trigger, 2x output table and stable window; original table restored" : "FAIL: missing frames, render errors, rebuilt window or inactive boost; overlay removed")
                NSApp.terminate(nil)
            }
        } else if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.printDiagnostics(); NSApp.terminate(nil)
            }
        } else {
            let event = NSAppleEventManager.shared().currentAppleEvent
            let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
                || event?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue == true
            if !loginLaunch { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.item.button?.performClick(nil) } }
        }
    }
    private func runTierTest() {
        guard model.hasInternalScreen else { print("No internal display: tier test refused"); NSApp.terminate(nil); return }
        let thresholds = model.thresholds
        var passed = true
        func later(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
        }
        func check(_ expected: BoostLevel) {
            let d = model.diagnostics()
            let transfer = d["transfer"] as? [String: Any] ?? [:]
            let tableGain = (transfer["tableGain"] as? NSNumber)?.doubleValue ?? 1
            let tableMaximum = (transfer["tableMaximum"] as? NSNumber)?.doubleValue ?? 0
            let ok = model.boostLevel == expected && abs(tableGain - expected.rawValue) < 0.01
                && abs(tableMaximum - expected.rawValue) < 0.02
                && d["overlayCreations"] as? Int == 1 && d["failedFrames"] as? Int == 0
                && (d["lastCompletedFrameAgeSeconds"] as? Double ?? 999) < 1
            passed = passed && ok
            print("Tier checkpoint \(expected.label): \(ok ? "PASS" : "FAIL")")
            printDiagnostics()
        }
        testLux = (thresholds.gentle + thresholds.strong) / 2
        model.mode = .auto
        later(7) { check(.gentle) }
        later(9) { self.testLux = thresholds.strong + 500 }
        later(16) { check(.strong) }
        later(18) { self.testLux = (thresholds.gentle + thresholds.strong) * 0.3 }
        later(26) { check(.gentle) }
        later(28) { self.testLux = 0 }
        later(35) {
            let d = self.model.diagnostics()
            let restored = !self.model.active && d["lastRestoreSucceeded"] as? Bool == true
            print(passed && restored ? "PASS: auto 1.5x -> 2x -> 1.5x -> off, one window, output restored" : "FAIL: automatic tier or restore check")
            self.printDiagnostics()
            self.model.mode = .off
            print("Final cleanup restored=\(self.model.diagnostics()["lastRestoreSucceeded"] as? Bool == true)")
            NSApp.terminate(nil)
        }
    }
    func refreshIcon() {
        let image = model.active ? Self.filledBasket : Self.outlineBasket
        if item.button?.image !== image { item.button?.image = image }
        item.button?.toolTip = "Picnic · \(model.status)"
    }
    private func configureMenu() {
        menu.autoenablesItems = false
        menu.minimumWidth = 286
        menu.delegate = self
        let summary = NSMenuItem()
        summaryView = NSHostingView(rootView: MenuSummary(model: model))
        summaryView.frame = NSRect(x: 0, y: 0, width: 286, height: 70)
        summary.view = summaryView
        menu.addItem(summary)
        menu.addItem(.separator())
        for mode in Mode.allCases {
            let option = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            option.representedObject = mode.rawValue
            option.target = self
            modeItems.append(option)
            menu.addItem(option)
        }
        menu.addItem(.separator())
        let threshold = NSMenuItem()
        let slider = NSHostingView(rootView: ThresholdControl(model: model))
        slider.frame = NSRect(x: 0, y: 0, width: 286, height: 154)
        threshold.view = slider
        menu.addItem(threshold)
        menu.addItem(.separator())
        loginItem = actionItem("登录时启动", #selector(toggleLoginItem))
        approvalItem = actionItem("在系统设置中允许登录启动…", #selector(openLoginSettings))
        loginErrorItem = NSMenuItem(title: "登录项设置失败", action: nil, keyEquivalent: "")
        loginErrorItem.isEnabled = false
        menu.addItem(loginErrorItem)
        menu.addItem(.separator())
        _ = actionItem("使用说明…", #selector(showHelp))
        _ = actionItem("退出 Picnic", #selector(quit))
    }
    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }
    func menuWillOpen(_ menu: NSMenu) {
        loginItems.refresh()
        for option in modeItems {
            option.state = option.representedObject as? String == model.mode.rawValue ? .on : .off
        }
        loginItem.state = loginItems.enabled ? .on : .off
        approvalItem.isHidden = !loginItems.needsApproval
        loginErrorItem.isHidden = loginItems.error == nil
        loginErrorItem.toolTip = loginItems.error
        if CommandLine.arguments.contains("--test-menu-layout") {
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in self?.printMenuGeometry() }
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    private func printMenuGeometry() {
        guard let button = item.button, let barWindow = button.window,
              let menuWindow = summaryView.window else { return }
        let anchor = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = menuWindow.frame
        let screen = barWindow.screen
        let result: [String: Any] = [
            "menuFrame": NSStringFromRect(frame), "statusButtonFrame": NSStringFromRect(anchor),
            "screenFrame": screen.map { NSStringFromRect($0.frame) } ?? "unknown",
            "belowMenuBar": frame.maxY <= anchor.minY + 1,
            "insideScreen": screen?.frame.contains(frame) ?? false,
            "mode": model.mode.rawValue, "gentleThresholdLux": model.thresholds.gentle,
            "strongThresholdLux": model.thresholds.strong,
            "iconIsTemplate": item.button?.image?.isTemplate ?? false,
            "iconSize": NSStringFromSize(item.button?.image?.size ?? .zero)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: data, encoding: .utf8)!); fflush(stdout)
        }
    }
    @objc private func selectMode(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let mode = Mode(rawValue: value) { model.mode = mode }
    }
    @objc private func toggleLoginItem() { loginItems.setEnabled(!loginItems.enabled) }
    @objc private func openLoginSettings() { loginItems.openSettings() }
    @objc private func showHelp() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func printDiagnostics() {
        if let data = try? JSONSerialization.data(withJSONObject: model.diagnostics(), options: [.prettyPrinted, .sortedKeys]), let str = String(data: data, encoding: .utf8) { print(str); fflush(stdout) }
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if CommandLine.arguments.contains("--login-item-status") {
    let data = try JSONSerialization.data(withJSONObject: LoginItems.diagnostics, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
} else if CommandLine.arguments.contains("--diagnose") {
    let model = AppModel(initialMode: .off)
    let data = try JSONSerialization.data(withJSONObject: model.diagnostics(), options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    model.shutdown()
} else {
    // Prevent two boost controllers from competing when the app is opened twice.
    let bundleID = Bundle.main.bundleIdentifier ?? "local.damao.SunLift"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let running = others.first { running.activate(); exit(0) }
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
