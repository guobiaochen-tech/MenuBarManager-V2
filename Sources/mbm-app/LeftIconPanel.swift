import AppKit

class LeftIconDisplay {
    private var panels: [IconPanel] = []

    /// 点击图标时回调，参数是图标索引
    var onClick: ((Int) -> Void)?

    let menuBarHeight: CGFloat = actualMenuBarHeight()
    let spacing: CGFloat = 0
    let baseIconWidth: CGFloat = 28

    // 缓存最新一次 scan 出来的数据，是否真的显示由 setVisible 控制
    private var cachedCount: Int = 0
    private var cachedImages: [NSImage] = []
    private var isVisible: Bool = false

    var rightEdge: CGFloat {
        guard let screen = NSScreen.screens.first else { return 700 }
        return screen.frame.width / 2 - 130
    }

    /// 更新数据，但不一定立刻显示。是否显示由当前 isVisible 决定
    func updateData(count: Int, images: [NSImage]) {
        cachedCount = count
        cachedImages = images
        if isVisible {
            renderFromCache()
        }
    }

    /// 控制是否在屏幕上显示
    func setVisible(_ on: Bool) {
        if on == isVisible { return }
        isVisible = on
        if on {
            renderFromCache()
        } else {
            clear()
        }
    }

    private func renderFromCache() {
        showCount(cachedCount, andImages: cachedImages)
    }

    private func showCount(_ count: Int, andImages images: [NSImage] = []) {
        debugLog("showCount: count=\(count) images=\(images.count)")
        clear()
        if count == 0 { return }

        guard let screen = NSScreen.screens.first else { return }
        let screenMaxY = screen.frame.maxY

        let panelHeight = menuBarHeight
        let panelY = screenMaxY - menuBarHeight

        let iconWidths = images.map { image -> CGFloat in
            max(baseIconWidth, image.size.width)
        }

        for (i, image) in images.enumerated() {
            let w = iconWidths[i]
            var x = rightEdge
            for j in 0...i {
                x -= iconWidths[j]
                if j < i { x -= spacing }
            }

            let panel = makePanel(x: x, y: panelY, width: w, height: panelHeight)

            let clickView = ClickableIconView(frame: NSRect(x: 0, y: 0, width: w, height: panelHeight))
            clickView.image = image
            clickView.imageScaling = .scaleProportionallyDown
            clickView.imageAlignment = .alignCenter
            clickView.iconIndex = i
            clickView.onClick = { [weak self] idx in
                debugLog("点中 icon[\(idx)]")
                self?.onClick?(idx)
            }
            panel.contentView?.addSubview(clickView)

            panel.orderFrontRegardless()
            panels.append(panel)
        }

        // 数字面板（不可点）
        let text = "\(count)"
        let fontSize: CGFloat = 16
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width + 8

        let totalIconsWidth = iconWidths.reduce(0, +) + CGFloat(max(0, iconWidths.count - 1)) * spacing
        let numberX = rightEdge - totalIconsWidth - spacing - textWidth

        let numberPanel = makePanel(x: numberX, y: panelY, width: textWidth, height: panelHeight, clickable: false)

        let label = VCenterTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.alignment = .center
        // 数字垂直居中
        label.frame = NSRect(x: 0, y: 0, width: textWidth, height: panelHeight)
        numberPanel.contentView?.addSubview(label)

        numberPanel.orderFrontRegardless()
        panels.append(numberPanel)
    }

    private func clear() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    /// 强制清空（数据 + 显示），扫描结果为 0 时调用
    func reset() {
        cachedCount = 0
        cachedImages = []
        clear()
    }

    private func makePanel(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, clickable: Bool = true) -> IconPanel {
        let panel = IconPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = !clickable
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

fileprivate func debugLog(_ msg: String) {
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

class IconPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 可点击图标视图
/// 直接接收 mouseDown 事件而不让点击穿透到下方菜单栏
class ClickableIconView: NSImageView {
    var iconIndex: Int = 0
    var onClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?(iconIndex)
    }

    // 防止系统把点击当成图像拖拽
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 文字垂直居中的 label
/// NSTextField 默认按基线绘制，在窄高的容器里看着会偏上，这里用 cell 重写居中绘制
class VCenterTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VCenterTextFieldCell.self }
        set { _ = newValue }
    }
}

class VCenterTextFieldCell: NSTextFieldCell {
    private func adjustedFrame(for rect: NSRect) -> NSRect {
        let textSize = self.cellSize(forBounds: rect)
        let dy = (rect.height - textSize.height) / 2
        return rect.insetBy(dx: 0, dy: dy)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: adjustedFrame(for: rect))
    }
}
