import AppKit
import MetalKit

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    var isInternal: Bool { CGDisplayIsBuiltin(displayID) != 0 }
    var supportsBoost: Bool { isInternal && (CGDisplayIsInMirrorSet(displayID) == 0) && maximumPotentialExtendedDynamicRangeColorComponentValue > 1.01 }
}

final class PassiveWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// A one-pixel HDR trigger keeps EDR available. Brightness is applied through
// the display table after window composition, including Mission Control.
final class BoostOverlay: NSObject, MTKViewDelegate {
    let window: NSWindow
    let view: MTKView
    private let queue: MTLCommandQueue
    private let displayGain: DisplayGain
    private var requestedGain: Float = 1
    private var nextIntegrityCheck: TimeInterval = 0
    private var closed = false
    var tableDiagnostics: [String: Any] { displayGain.diagnostics }
    private(set) var submittedFrames = 0
    private(set) var completedFrames = 0
    private(set) var failedFrames = 0
    private(set) var unavailableDrawables = 0
    private var lastCompletion: TimeInterval?
    var frameAge: TimeInterval? { lastCompletion.map { ProcessInfo.processInfo.systemUptime - $0 } }
    var onError: ((String) -> Void)?

    init?(screen: NSScreen) {
        guard screen.supportsBoost, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let io = InternalDisplayTableIO(display: screen.displayID), let displayGain = DisplayGain(io: io) else { return nil }
        self.queue = queue
        self.displayGain = displayGain
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
        window = PassiveWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
        view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        super.init()
        window.isReleasedWhenClosed = false
        // Keep the tiny trigger unobscured; no full-screen blending window.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.canHide = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // An ordinary EDR surface remains visible in Mission Control, unlike
        // the cross-window multiply filter used by the previous renderer.
        window.contentView = view
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        // Keep a steady rendering stream; a retained static surface alone
        // did not maintain EDR on this Mac.
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 1, height: 1)
        view.preferredFramesPerSecond = 5
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.delegate = self
        if let layer = view.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.colorspace = view.colorspace
            layer.isOpaque = false
        }
        window.animationBehavior = .none
        window.setFrame(frame, display: false)
        view.clearColor = MTLClearColor(red: 2, green: 2, blue: 2, alpha: 1)
        window.orderFrontRegardless()
    }

    func setGain(_ gain: Double) {
        requestedGain = Float(min(2, max(1, gain)))
        applyPendingGain()
    }
    private func applyPendingGain() {
        guard !closed, completedFrames >= 3 else { return }
        if !displayGain.setGain(requestedGain) { onError?(displayGain.error ?? "无法设置内屏增益") }
    }
    func maintain() {
        guard !closed, completedFrames >= 3 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextIntegrityCheck else { return }
        nextIntegrityCheck = now + 1
        if !displayGain.refresh() { onError?(displayGain.error ?? "内屏输出表验证失败") }
    }
    @discardableResult func close() -> Bool {
        guard !closed else { return true }
        closed = true
        let restored = displayGain.restore()
        view.isPaused = true; view.delegate = nil; window.orderOut(nil); window.close()
        return restored
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
            // Drawable unavailability can be transient (window movement/wake).
            // A later display callback retries without destroying the window.
            unavailableDrawables += 1
            return
        }
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            onError?("无法创建绘制任务，增强已停止")
            return
        }
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            let succeeded = buffer.status == .completed
            DispatchQueue.main.async {
                guard let self else { return }
                if succeeded {
                    self.completedFrames += 1
                    self.lastCompletion = ProcessInfo.processInfo.systemUptime
                    self.applyPendingGain()
                } else {
                    self.failedFrames += 1
                    self.onError?("GPU 渲染失败，增强已停止")
                }
            }
        }
        command.commit()
        submittedFrames += 1
    }
}
