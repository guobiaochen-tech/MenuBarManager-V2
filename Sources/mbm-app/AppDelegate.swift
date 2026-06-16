import AppKit
import CoreGraphics
import ServiceManagement

private func appDelegateLog(_ msg: String) {
    let line = msg + "\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/mbm-debug.log"
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var iconDisplay: LeftIconDisplay!
    var timer: Timer?
    var hoverTimer: Timer?
    var imageCache: [NSImage] = []
    var lastHiddenCount: Int = -1
    var lastHiddenIdentities: [String] = []  // 隐藏图标的身份序列，用来判断要不要重新截图
    var isCapturing: Bool = false
    var hiddenItems: [MenuBarIcon] = []

    // 菜单栏状态图标
    var statusItem: NSStatusItem!
    var autoStartMenuItem: NSMenuItem!

    // 权限引导窗口
    var permissionWindow: PermissionWindow?

    // 鼠标 hover 状态
    var hideDeadline: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检测权限，未全部授权则弹出引导窗口
        if PermissionChecker.isAccessibilityGranted && PermissionChecker.isScreenRecordingGranted {
            setupStatusBar()
            startMainLogic()
        } else {
            showPermissionWindow()
        }
    }

    // MARK: - 权限引导

    private func showPermissionWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        permissionWindow = PermissionWindow()
        permissionWindow?.onAllGranted = { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            self?.permissionWindow = nil
            self?.setupStatusBar()
            self?.startMainLogic()
        }
        permissionWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 主业务启动

    private func startMainLogic() {
        iconDisplay = LeftIconDisplay()

        iconDisplay.onClick = { [weak self] index in
            self?.handleIconClick(at: index)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickHover()
        }
    }

    // MARK: - 菜单栏图标 & 下拉菜单

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "statusbar-icon", ofType: "png"),
               let image = NSImage(contentsOfFile: iconPath) {
                image.size = NSSize(width: 20, height: 20)
                image.isTemplate = true
                button.image = image
            }
        }

        let menu = NSMenu()

        let versionItem = NSMenuItem(title: "MenuBarManager V2.3", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let emailItem = NSMenuItem(title: "1915199181@qq.com", action: nil, keyEquivalent: "")
        emailItem.isEnabled = false
        menu.addItem(emailItem)

        menu.addItem(NSMenuItem.separator())

        autoStartMenuItem = NSMenuItem(title: "开机自启", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartMenuItem.target = self
        updateAutoStartMenuState()
        menu.addItem(autoStartMenuItem)

        let updateItem = NSMenuItem(title: "检查更新", action: #selector(checkForUpdate), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleAutoStart() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            appDelegateLog("开机自启设置失败: \(error)")
        }
        updateAutoStartMenuState()
    }

    private func updateAutoStartMenuState() {
        let enabled = SMAppService.mainApp.status == .enabled
        autoStartMenuItem.state = enabled ? .on : .off
    }

    @objc private func checkForUpdate() {
        if let url = URL(string: "https://github.com/placeholder/MenuBarManager-V2/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 隐藏图标显示逻辑

    private func tickHover() {
        guard let screen = NSScreen.screens.first else { return }
        let mouse = NSEvent.mouseLocation
        let menuBarTop = screen.frame.maxY
        let menuBarBottom = menuBarTop - actualMenuBarHeight()
        let inMenuBar = mouse.y >= menuBarBottom && mouse.y <= menuBarTop
        let inRightHalf = mouse.x >= screen.frame.midX

        if !inMenuBar {
            if iconDisplay != nil, hideDeadline == nil, isShowing {
                hideDeadline = Date(timeIntervalSinceNow: 2.0)
            }
            if let dl = hideDeadline, Date() >= dl {
                iconDisplay.setVisible(false)
                hideDeadline = nil
                isShowing = false
            }
            return
        }

        if !isShowing {
            if inRightHalf {
                iconDisplay.setVisible(true)
                isShowing = true
                hideDeadline = nil
            }
        } else {
            hideDeadline = nil
        }
    }

    var isShowing: Bool = false

    private func handleIconClick(at index: Int) {
        appDelegateLog("点击图标[\(index)]")
        guard index < hiddenItems.count else {
            appDelegateLog("索引越域，count=\(hiddenItems.count)")
            return
        }
        let item = hiddenItems[index]
        appDelegateLog("displayName=\(item.displayName) realAppPID=\(item.realAppPID ?? -1) realAppName=\(item.realAppName ?? "?")")

        let targetPID = item.realAppPID ?? item.ownerPID
        if let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate()
            appDelegateLog("已激活 \(app.localizedName ?? "?")，等 50ms 后 AXPress")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.performPress(item: item)
        }
    }

    private func performPress(item: MenuBarIcon) {
        if let axIcon = item.axIcon {
            // Flutter/Electron 类托盘的 kAXPressAction 会假成功（AX 返回 success 但底层不响应），
            // 对这类 app 改用 CGEvent 在真实坐标模拟点击；原生 app（微信等）继续用 AXPress，不波及。
            if isTrayStyleApp(item), clickAtCoordinate(axIcon: axIcon) {
                appDelegateLog("CGEvent 点击 @(\(Int(axIcon.frame.midX)),\(Int(axIcon.frame.midY)))")
                return
            }
            let ok = AXIconResolver.press(axIcon)
            appDelegateLog("AXPress \(ok ? "成功" : "失败")")
            if ok { return }
        }

        if let url = item.realAppBundleURL {
            appDelegateLog("回退打开 \(url.path)")
            NSWorkspace.shared.open(url)
            return
        }

        appDelegateLog("没有可用的激活方式")
    }

    /// 判断是否 Flutter/Electron/Chromium 类托盘 app（这类 kAXPressAction 会假成功）。
    /// 检查 Contents/Frameworks 下是否有对应框架。
    private func isTrayStyleApp(_ item: MenuBarIcon) -> Bool {
        guard let bundleURL = item.realAppBundleURL else { return false }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks").path
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks) else { return false }
        return names.contains { name in
            name.contains("Flutter") || name.contains("Electron") || name.contains("Chromium")
        }
    }

    /// 用 CGEvent 在 AX 图标坐标发一次真实左键点击。
    /// AX 报告的是 AppKit 坐标（左下原点），CGEvent 用全局坐标（左上原点），需翻转 Y。
    private func clickAtCoordinate(axIcon: AXIconInfo) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let frame = axIcon.frame
        // 只点屏幕可见区内的坐标，折叠到屏幕外的图标放弃（返回 false 让上层退回 AXPress）
        guard frame.midX >= 0, frame.midX <= screen.frame.width,
              frame.midY >= 0, frame.midY <= screen.frame.height else { return false }
        let pt = CGPoint(x: frame.midX, y: screen.frame.height - frame.midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func refresh() {
        let result = scanMenuBarItems()
        hiddenItems = result.items.filter { !$0.isOnScreen }
        let hiddenCount = hiddenItems.count
        // 当前隐藏图标的身份序列（Scanner 已按位置排好序）
        let currentIdentities = hiddenItems.compactMap { $0.identityKey }

        if hiddenCount == 0 {
            if lastHiddenCount != 0 {
                iconDisplay.reset()
                imageCache.removeAll()
                lastHiddenCount = 0
                lastHiddenIdentities = []
                isShowing = false
                hideDeadline = nil
            }
            return
        }

        // 缓存判断：身份序列没变就不重新截图。
        // 旧逻辑只比数量，导致「图标身份换了但数量没变」时不重画，左侧还显示旧图、
        // 和真实 hiddenItems 脱节——左右两边出现同一个图标、点击也点错对象。
        if currentIdentities == lastHiddenIdentities && !imageCache.isEmpty {
            return
        }

        if !isCapturing {
            isCapturing = true

            if imageCache.isEmpty {
                iconDisplay.updateData(count: hiddenCount, images: [])
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                NSLog("🔵 开始截图，hiddenItems=%d", hiddenItems.count)
                let images = await IconCapturer.captureHiddenItems(hiddenItems: hiddenItems)
                let validImages = images.compactMap { $0 }
                NSLog("🔵 截图完成，总数=%d 有效=%d", images.count, validImages.count)
                if !validImages.isEmpty {
                    self.imageCache = validImages
                    self.iconDisplay.updateData(count: hiddenCount, images: validImages)
                } else if self.imageCache.isEmpty {
                    self.iconDisplay.updateData(count: hiddenCount, images: [])
                }
                // 身份序列和 imageCache 同一轮同步更新，保证显示的图和 hiddenItems 严格对齐
                self.lastHiddenIdentities = currentIdentities
                self.lastHiddenCount = hiddenCount
                self.isCapturing = false
            }
        }
    }
}
