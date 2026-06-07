import AppKit
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

        let emailItem = NSMenuItem(title: "guobiao.chen@hotmail.com", action: nil, keyEquivalent: "")
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

    private func refresh() {
        let result = scanMenuBarItems()
        hiddenItems = result.items.filter { !$0.isOnScreen }
        let hiddenCount = hiddenItems.count

        if hiddenCount == 0 {
            if lastHiddenCount != 0 {
                iconDisplay.reset()
                imageCache.removeAll()
                lastHiddenCount = 0
                isShowing = false
                hideDeadline = nil
            }
            return
        }

        if hiddenCount == lastHiddenCount && !imageCache.isEmpty {
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
                self.lastHiddenCount = hiddenCount
                self.isCapturing = false
            }
        }
    }
}
