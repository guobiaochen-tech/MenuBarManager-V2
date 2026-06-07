import CoreGraphics
import ApplicationServices
import AppKit
import ScreenCaptureKit

// MARK: - 用 ScreenCaptureKit 直接抓取离屏窗口图像，不移动窗口

@MainActor
class IconCapturer {

    static func captureHiddenItems(hiddenItems: [MenuBarIcon]) async -> [NSImage?] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let mbh = actualMenuBarHeight()

            var results: [NSImage?] = []
            for item in hiddenItems {
                guard let scWindow = content.windows.first(where: { $0.windowID == item.windowID }) else {
                    results.append(nil)
                    continue
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.showsCursor = false
                config.width = Int(item.frame.width * scale)
                config.height = Int(item.frame.height * scale)

                do {
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                    let fullHeight = CGFloat(cgImage.height)
                    let cropHeight = min(fullHeight, mbh * scale)
                    let cropY: CGFloat = 0  // 菜单栏窗口贴屏幕顶部，多出部分在底部，从顶部裁才对

                    if let cropped = cgImage.cropping(to: CGRect(x: 0, y: cropY, width: CGFloat(cgImage.width), height: cropHeight)) {
                        let pointSize = NSSize(width: CGFloat(cropped.width) / scale, height: CGFloat(cropped.height) / scale)
                        results.append(NSImage(cgImage: cropped, size: pointSize))
                    } else {
                        results.append(nil)
                    }
                } catch {
                    results.append(nil)
                }
            }
            return results
        } catch {
            return hiddenItems.map { _ in nil }
        }
    }
}
