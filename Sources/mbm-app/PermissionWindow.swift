import AppKit
import CoreGraphics

// MARK: - 权限检测

enum PermissionChecker {
    static var isAccessibilityGranted: Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func openAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static func openScreenRecording() {
        CGRequestScreenCaptureAccess()
    }
}

// MARK: - 权限引导窗口（用 NSViewController 管理，可靠）

class PermissionWindow: NSWindow {
    private var timer: Timer?
    private var axBtn: NSButton!
    private var srBtn: NSButton!
    private var axStatus: NSTextField!
    private var srStatus: NSTextField!
    private var continueBtn: NSButton!

    var onAllGranted: (() -> Void)?

    init() {
        let W: CGFloat = 480
        let H: CGFloat = 460

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "MenuBarManager - 权限设置"
        isReleasedWhenClosed = false
        isRestorable = false
        center()

        let vc = PermissionViewController()
        vc.windowRef = self
        self.contentViewController = vc

        axBtn = vc.axBtn
        srBtn = vc.srBtn
        axStatus = vc.axStatus
        srStatus = vc.srStatus
        continueBtn = vc.continueBtn

        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func refresh() {
        let axOK = PermissionChecker.isAccessibilityGranted
        let srOK = PermissionChecker.isScreenRecordingGranted

        setStatus(axStatus, axBtn, axOK)
        setStatus(srStatus, srBtn, srOK)
        continueBtn.isEnabled = axOK && srOK
    }

    private func setStatus(_ label: NSTextField, _ btn: NSButton, _ ok: Bool) {
        if ok {
            btn.isEnabled = false
            btn.title = "✅ 已授权"
        } else {
            btn.isEnabled = true
            btn.title = "未授权，点击去系统设置"
        }
    }

    func doContinue() {
        timer?.invalidate()
        timer = nil
        orderOut(nil)
        onAllGranted?()
    }

    func doClose() {
        timer?.invalidate()
        timer = nil
        super.close()
        NSApp.terminate(nil)
    }
}

// MARK: - ViewController（管理所有 UI 和按钮事件）

class PermissionViewController: NSViewController {
    var axBtn: NSButton!
    var srBtn: NSButton!
    var axStatus: NSTextField!
    var srStatus: NSTextField!
    var continueBtn: NSButton!
    weak var windowRef: PermissionWindow?

    override func loadView() {
        let W: CGFloat = 480
        let H: CGFloat = 460
        view = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        // 标题
        addCenteredLabel("MenuBarManager", fontSize: 20, weight: .bold, color: .white, y: 405)
        addCenteredLabel("V2.3  ·  guobiao.chen@hotmail.com", fontSize: 12, weight: .regular, color: .gray, y: 382)

        // 分割线
        let line = NSView(frame: NSRect(x: 24, y: 368, width: W - 48, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        view.addSubview(line)

        // 辅助功能卡片
        let (axCard, axBtn_, axSt) = makeCard(
            y: 252,
            title: "辅助功能",
            desc: "用于识别和点击菜单栏中隐藏的图标，授权后才能定位并操作被挤掉的图标。",
            action: #selector(openAX)
        )
        view.addSubview(axCard)
        axBtn = axBtn_
        axStatus = axSt

        // 屏幕录制卡片
        let (srCard, srBtn_, srSt) = makeCard(
            y: 138,
            title: "屏幕录制",
            desc: "用于截取隐藏图标的画面并显示到菜单栏，授权后才能看到被隐藏图标的真实样子。",
            action: #selector(openSR)
        )
        view.addSubview(srCard)
        srBtn = srBtn_
        srStatus = srSt

        // 继续使用
        continueBtn = NSButton(frame: NSRect(x: 140, y: 50, width: 200, height: 40))
        continueBtn.title = "继续使用"
        continueBtn.bezelStyle = .rounded
        continueBtn.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        continueBtn.isEnabled = false
        continueBtn.target = self
        continueBtn.action = #selector(doContinue)
        view.addSubview(continueBtn)
    }

    @objc private func openAX() {
        PermissionChecker.openAccessibility()
    }

    @objc private func openSR() {
        PermissionChecker.openScreenRecording()
    }

    @objc private func doContinue() {
        windowRef?.doContinue()
    }

    // MARK: - UI 工具

    private func addCenteredLabel(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        l.textColor = color
        l.alignment = .center
        l.sizeToFit()
        l.frame = NSRect(x: 0, y: y, width: view.frame.width, height: l.frame.height)
        view.addSubview(l)
    }

    private func makeCard(y: CGFloat, title: String, desc: String, action: Selector) -> (NSView, NSButton, NSTextField) {
        let W = view.frame.width
        let cardW = W - 48
        let cardH: CGFloat = 104

        let card = NSView(frame: NSRect(x: 24, y: y, width: cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = NSColor(white: 0.3, alpha: 1).cgColor
        card.layer?.borderWidth = 1

        let t = NSTextField(labelWithString: title)
        t.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        t.textColor = .white
        t.frame = NSRect(x: 16, y: 76, width: 300, height: 22)
        card.addSubview(t)

        let d = NSTextField(wrappingLabelWithString: desc)
        d.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        d.textColor = NSColor(white: 0.7, alpha: 1)
        d.frame = NSRect(x: 16, y: 38, width: cardW - 32, height: 38)
        card.addSubview(d)

        // 底部大按钮，占满卡片宽度
        let btn = NSButton(frame: NSRect(x: 12, y: 6, width: cardW - 24, height: 30))
        btn.title = "去授权"
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        btn.target = self
        btn.action = action
        card.addSubview(btn)

        // status 不再显示在卡片上，用一个隐藏的 label 保持兼容
        let status = NSTextField(labelWithString: "")
        status.isHidden = true

        return (card, btn, status)
    }
}
