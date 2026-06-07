import Foundation

let result = scanMenuBarItems()

print("=== 菜单栏图标扫描 ===")
print()
print("总图标: \(result.total) 个")
print("显示中: \(result.visible) 个")
print("被隐藏: \(result.hidden) 个")
print()

for (i, item) in result.items.enumerated() {
    let onScreenStr = item.isOnScreen ? "true " : "false"
    print("[\(String(format: "%2d", i + 1))]  x=\(String(format: "%6.0f", item.frame.origin.x))  w=\(String(format: "%4.0f", item.frame.width))  onScreen=\(onScreenStr)  \(item.ownerName)  \(item.status)")
}
