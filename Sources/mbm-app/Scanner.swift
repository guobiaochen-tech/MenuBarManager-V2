import CoreGraphics
import Foundation
import ApplicationServices
import AppKit

/// 动态获取实际菜单栏高度（有刘海的 MacBook 是 33pt，普通屏是 24pt）
func actualMenuBarHeight() -> CGFloat {
    guard let screen = NSScreen.screens.first else { return 24 }
    return screen.frame.maxY - screen.visibleFrame.maxY
}

// MARK: - 菜单栏图标数据

struct MenuBarIcon {
    let windowID: CGWindowID
    let frame: CGRect
    let ownerPID: pid_t           // 窗口服务器 PID（通常是控制中心 638）
    let ownerName: String         // 同上
    let isOnScreen: Bool

    // AX 解析出的真实归属
    let realAppPID: pid_t?        // 图标真实归属 app 的 PID
    let realAppName: String?      // 显示名（「微信」「Snipaste」）
    let realAppBundleURL: URL?    // .app 路径
    let label: String?            // AX 描述（系统图标如「Wi-Fi」）
    let axIdentifier: String?     // 系统图标的 identifier
    let axIcon: AXIconInfo?       // 用于点击时模拟按压

    var status: String { isOnScreen ? "✅ 显示" : "❌ 隐藏" }

    /// 用户看到的名字：优先 AX 描述（系统图标）→ app 名 → owner 名
    var displayName: String {
        if let l = label, !l.isEmpty { return l }
        if let n = realAppName, !n.isEmpty { return n }
        return ownerName
    }
}

// MARK: - 排除非图标窗口

private let excludedOwners: Set<String> = [
    "LinkedNotesUIService",
]

// MARK: - 核心扫描器

func scanMenuBarItems() -> (total: Int, visible: Int, hidden: Int, items: [MenuBarIcon]) {
    guard let rawList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return (0, 0, 0, [])
    }

    // 先收集所有 app 的菜单栏图标作为映射源
    let axIcons = AXIconResolver.collectAllIcons()

    var items: [MenuBarIcon] = []

    for dict in rawList {
        guard let layer = dict["kCGWindowLayer"] as? Int32, layer == 25 else { continue }
        guard let wid = dict[kCGWindowNumber as String] as? CGWindowID else { continue }
        let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
        let pid = (dict[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let isOnScreen = (dict["kCGWindowIsOnscreen"] as? Bool) ?? false

        if excludedOwners.contains(ownerName) { continue }

        let frame: CGRect
        if let cgFrame = gsGetWindowFrame(for: wid) {
            frame = cgFrame
        } else {
            guard let boundsDict = dict["kCGWindowBounds"] as? [String: Any],
                  let bx = boundsDict["X"] as? CGFloat,
                  let by = boundsDict["Y"] as? CGFloat,
                  let bw = boundsDict["Width"] as? CGFloat,
                  let bh = boundsDict["Height"] as? CGFloat else { continue }
            frame = CGRect(x: bx, y: by, width: bw, height: bh)
        }

        guard frame.width > 0, frame.width < 500 else { continue }

        // 用坐标找出真实归属
        let resolved = AXIconResolver.resolve(windowFrame: frame, in: axIcons)

        items.append(MenuBarIcon(
            windowID: wid,
            frame: frame,
            ownerPID: pid,
            ownerName: ownerName,
            isOnScreen: isOnScreen,
            realAppPID: resolved?.appPID,
            realAppName: resolved?.appName,
            realAppBundleURL: resolved?.bundleURL,
            label: resolved?.label,
            axIdentifier: resolved?.identifier,
            axIcon: resolved
        ))
    }

    // AX 匹配不上的窗口大概率是「幽灵窗口」（系统残留的 layer 25 空窗），过滤掉
    let cleaned = items.filter { $0.realAppPID != nil }

    let sorted = cleaned.sorted { $0.frame.origin.x > $1.frame.origin.x }
    let visible = sorted.filter { $0.isOnScreen }
    let hidden = sorted.filter { !$0.isOnScreen }

    return (total: sorted.count, visible: visible.count, hidden: hidden.count, items: sorted)
}
