import CoreGraphics
import Foundation
import ApplicationServices
import AppKit

// MARK: - 菜单栏图标数据

struct MenuBarIcon {
    let windowID: CGWindowID
    let frame: CGRect
    let ownerPID: pid_t
    let ownerName: String
    let isOnScreen: Bool

    var status: String { isOnScreen ? "✅ 显示" : "❌ 隐藏" }
}

// MARK: - 排除非图标窗口

private let excludedOwners: Set<String> = [
    "LinkedNotesUIService",
]

// MARK: - 核心扫描器
// 用 CGWindowListCopyWindowInfo（公开 API）扫描 layer=25 的窗口
// CGS 私有 API 只用来获取精确窗口坐标

func scanMenuBarItems() -> (total: Int, visible: Int, hidden: Int, items: [MenuBarIcon]) {
    guard let rawList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return (0, 0, 0, [])
    }

    var items: [MenuBarIcon] = []

    for dict in rawList {
        // 只取菜单栏窗口（layer 25）
        guard let layer = dict["kCGWindowLayer"] as? Int32, layer == 25 else { continue }

        guard let wid = dict[kCGWindowNumber as String] as? CGWindowID else { continue }
        let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
        let pid = (dict[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let isOnScreen = (dict["kCGWindowIsOnscreen"] as? Bool) ?? false

        if excludedOwners.contains(ownerName) { continue }

        // 用 CGS 获取精确坐标（比公开 API 的 bounds 更准）
        let frame: CGRect
        if let cgFrame = gsGetWindowFrame(for: wid) {
            frame = cgFrame
        } else {
            // 回退到公开 API 的 bounds
            guard let boundsDict = dict["kCGWindowBounds"] as? [String: Any],
                  let bx = boundsDict["X"] as? CGFloat,
                  let by = boundsDict["Y"] as? CGFloat,
                  let bw = boundsDict["Width"] as? CGFloat,
                  let bh = boundsDict["Height"] as? CGFloat else { continue }
            frame = CGRect(x: bx, y: by, width: bw, height: bh)
        }

        guard frame.width > 0, frame.width < 500 else { continue }

        items.append(MenuBarIcon(
            windowID: wid,
            frame: frame,
            ownerPID: pid,
            ownerName: ownerName,
            isOnScreen: isOnScreen
        ))
    }

    let sorted = items.sorted { $0.frame.origin.x > $1.frame.origin.x }
    let visible = sorted.filter { $0.isOnScreen }
    let hidden = sorted.filter { !$0.isOnScreen }

    return (total: sorted.count, visible: visible.count, hidden: hidden.count, items: sorted)
}
