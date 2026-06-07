import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - AX 图标解析
// 思路：菜单栏图标的真实 owner 不是 layer 25 窗口的 ownerPID（那个总是控制中心），
// 而是把图标挂在自己 AXExtrasMenuBar 下的那个 app。
// 所以扫所有运行 app，把每个 app 的 extras 图标坐标收集起来，
// 然后按 X 坐标和 layer 25 窗口匹配。

struct AXIconInfo {
    let appName: String       // app 显示名（如「微信」）
    let appPID: pid_t         // 真正的 app PID（不是控制中心 638）
    let bundleURL: URL?       // .app 路径
    let label: String         // AX 给的描述（如「Wi-Fi」「专注模式」），第三方常为空
    let identifier: String    // 系统图标如 com.apple.menuextra.wifi
    let frame: CGRect         // 图标在屏幕上的坐标（AX 报告的）
    let element: AXUIElement  // AX 元素本身，用于 AXPress 模拟点击
}

enum AXIconResolver {

    /// 收集所有 app 的菜单栏图标
    static func collectAllIcons() -> [AXIconInfo] {
        var result: [AXIconInfo] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited else { continue }
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            // 跳过明显是子进程的 helper、XPC 服务，避免 AX 卡死
            let bundlePath = app.bundleURL?.path ?? ""
            if bundlePath.contains(".app/Contents/") { continue }
            if bundlePath.contains("XPCServices") { continue }
            let name = app.localizedName ?? ""
            if name.contains("Helper") || name.contains("Renderer")
                || name.contains("Networking") || name.contains("Web Content")
                || name.contains("Graphics") {
                continue
            }

            let axApp = AXUIElementCreateApplication(pid)
            // 防止某个 app 的 AX 调用卡死整个流程
            AXUIElementSetMessagingTimeout(axApp, 0.5)

            var extras: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extras)
            guard err == .success, let bar = extras else { continue }
            guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }

            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
            guard let kids = children as? [AXUIElement], !kids.isEmpty else { continue }

            for kid in kids {
                AXUIElementSetMessagingTimeout(kid, 0.5)
                guard let frame = axFrame(of: kid), frame.width > 0 else { continue }

                let desc = axString(kid, kAXDescriptionAttribute) ?? ""
                let title = axString(kid, kAXTitleAttribute) ?? ""
                let ident = axString(kid, kAXIdentifierAttribute) ?? ""
                let label = !desc.isEmpty ? desc : title

                result.append(AXIconInfo(
                    appName: name,
                    appPID: pid,
                    bundleURL: app.bundleURL,
                    label: label,
                    identifier: ident,
                    frame: frame,
                    element: kid
                ))
            }
        }
        return result
    }

    /// 按 X 坐标中心点匹配，找出 layer25 窗口对应的 app 图标
    static func resolve(windowFrame: CGRect, in icons: [AXIconInfo], tolerance: CGFloat = 30) -> AXIconInfo? {
        let cx = windowFrame.midX
        var best: AXIconInfo?
        var bestDiff: CGFloat = .infinity
        for ic in icons {
            let diff = abs(ic.frame.midX - cx)
            if diff < bestDiff {
                bestDiff = diff
                best = ic
            }
        }
        return bestDiff <= tolerance ? best : nil
    }

    /// 模拟点击菜单栏图标（用 AXPress）
    /// 等价于用户用鼠标点一下，由 app 自己决定弹窗或弹菜单
    @discardableResult
    static func press(_ icon: AXIconInfo) -> Bool {
        let err = AXUIElementPerformAction(icon.element, kAXPressAction as CFString)
        return err == .success
    }

    // MARK: - 工具

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func axFrame(of el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
}

// MARK: - 辅助功能权限

enum AXPermission {
    static func ensureGranted(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
