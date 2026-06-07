import ApplicationServices
import CoreGraphics
import Foundation

// 测试目标：
// 1. 用扫描器找到隐藏图标的 PID 和 windowID
// 2. 用 Accessibility API 找到对应的菜单栏图标
// 3. 调用 AXPress 看菜单弹在哪

// MARK: - CGS 私有 API（从项目复制）

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(_ cid: CGSConnectionID, _ windowID: CGWindowID, _ rect: UnsafeMutablePointer<CGRect>) -> CGError

func gsGetWindowFrame(for windowID: CGWindowID) -> CGRect? {
    var rect = CGRect.zero
    guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect) == .success else { return nil }
    return rect
}

// MARK: - 扫描菜单栏图标

struct MenuBarIcon {
    let windowID: CGWindowID
    let frame: CGRect
    let ownerPID: pid_t
    let ownerName: String
    let isOnScreen: Bool
}

func scanMenuBarItems() -> [MenuBarIcon] {
    guard let rawList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    var items: [MenuBarIcon] = []

    for dict in rawList {
        guard let layer = dict["kCGWindowLayer"] as? Int32, layer == 25 else { continue }
        guard let wid = dict[kCGWindowNumber as String] as? CGWindowID else { continue }
        let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
        let pid = (dict[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let isOnScreen = (dict["kCGWindowIsOnscreen"] as? Bool) ?? false

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

        items.append(MenuBarIcon(windowID: wid, frame: frame, ownerPID: pid, ownerName: ownerName, isOnScreen: isOnScreen))
    }

    return items.sorted { $0.frame.origin.x > $1.frame.origin.x }
}

// MARK: - Accessibility 辅助

func dumpAXTree(_ element: AXUIElement, indent: Int = 0) {
    let prefix = String(repeating: "  ", count: indent)

    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

    var title: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

    var position: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)

    var size: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)

    let roleStr = (role as? String) ?? "?"
    let titleStr = (title as? String) ?? ""
    var posStr = ""
    if let posVal = position {
        posStr = " pos=\(posVal)"
    }

    print("\(prefix)[\(roleStr)] \"\(titleStr)\"\(posStr)")

    // 只展开 3 层，避免太深
    if indent < 3 {
        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let childList = children as? [AXUIElement] {
            for child in childList {
                dumpAXTree(child, indent: indent + 1)
            }
        }
    }
}

func findMenuBarItems(for pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)

    var menuBar: AnyObject?
    let err = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar)
    guard err == .success, let bar = menuBar else {
        print("  ❌ 拿不到 \(pid) 的菜单栏, error=\(err.rawValue)")
        return []
    }

    var children: AnyObject?
    AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
    guard let items = children as? [AXUIElement] else {
        print("  ❌ 菜单栏没有子元素")
        return []
    }

    return items
}

func printAXInfo(_ element: AXUIElement, label: String) {
    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

    var title: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

    var desc: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescription as CFString, &desc)

    var position: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)

    var size: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)

    var identifier: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)

    print("  📌 \(label)")
    print("     role=\((role as? String) ?? "?")")
    print("     title=\((title as? String) ?? "")")
    print("     desc=\((desc as? String) ?? "")")
    print("     identifier=\((identifier as? String) ?? "")")
    print("     position=\(position.flatMap { String(describing: $0) } ?? "nil")")
    print("     size=\(size.flatMap { String(describing: $0) } ?? "nil")")

    // 列出所有可用的 action
    var actions: CFArray?
    AXUIElementCopyActionNames(element, &actions)
    if let actionList = actions as? [String] {
        print("     actions=\(actionList)")
    }
}

// MARK: - 主测试

print("=== 菜单栏图标扫描 ===")
let allItems = scanMenuBarItems()
let hiddenItems = allItems.filter { !$0.isOnScreen }

print("总数: \(allItems.count), 隐藏: \(hiddenItems.count)")
print()

if hiddenItems.isEmpty {
    print("没有隐藏图标，无法测试。请确保有菜单栏图标被隐藏。")
} else {
    print("=== 隐藏图标详情 + Accessibility API 测试 ===")
    for (i, item) in hiddenItems.enumerated() {
        print()
        print("🔹 图标[\(i)] \(item.ownerName) (PID=\(item.ownerPID), WID=\(item.windowID))")
        print("   frame=\(item.frame) isOnScreen=\(item.isOnScreen)")

        // 尝试用 Accessibility API 找到这个图标的菜单栏元素
        print("   --- Accessibility API ---")
        let axItems = findMenuBarItems(for: item.ownerPID)

        if axItems.isEmpty {
            print("   菜单栏上没有找到状态栏图标（可能不是标准 NSStatusItem）")
        } else {
            print("   菜单栏子元素数量: \(axItems.count)")
            for (j, axItem) in axItems.enumerated() {
                printAXInfo(axItem, label: "item[\(j)]")

                // 如果是状态栏图标（通常没有 title 但有 position），尝试匹配位置
                // 隐藏图标的位置通常是负数 x 或超出屏幕宽度
            }
        }
    }

    // 额外测试：对第一个隐藏图标尝试 AXPress
    if let firstHidden = hiddenItems.first {
        print()
        print("=== 尝试 AXPress 第一个隐藏图标: \(firstHidden.ownerName) ===")

        let axItems = findMenuBarItems(for: firstHidden.ownerPID)

        // 状态栏图标通常是菜单栏的最后一个子元素（Apple 菜单在左边，状态栏在右边）
        // 但实际上 NSStatusItem 不一定出现在 AXMenuBar 里
        // 有些应用的状态栏图标在 extrasMenuBar 上

        // 尝试另一种方式：用 extrasMenuBar
        let app = AXUIElementCreateApplication(firstHidden.ownerPID)

        // 检查有没有 kAXExtrasMenuBarAttribute
        var extrasBar: AnyObject?
        let extrasErr = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasBar)

        if extrasErr == .success, let eBar = extrasBar {
            print("✅ 找到 AXExtrasMenuBar!")
            var extrasChildren: AnyObject?
            AXUIElementCopyAttributeValue(eBar as! AXUIElement, kAXChildrenAttribute as CFString, &extrasChildren)
            if let exItems = extrasChildren as? [AXUIElement] {
                print("   extrasMenuBar 子元素: \(exItems.count)")
                for (j, exItem) in exItems.enumerated() {
                    printAXInfo(exItem, label: "extras[\(j)]")
                }
            }
        } else {
            print("❌ 没有 AXExtrasMenuBar, error=\(extrasErr.rawValue)")

            // 打印 app 的所有属性名
            var attrs: CFArray?
            AXUIElementCopyAttributeNames(app, &attrs)
            if let attrList = attrs as? [String] {
                print("   app 可用属性: \(attrList)")
            }
        }
    }
}
