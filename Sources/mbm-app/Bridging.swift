import CoreGraphics

// MARK: - CGS 私有 API 声明
// 参考 Ice 项目: Shared/Bridging/Shims.swift

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: UnsafeMutablePointer<Int32>
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(_ cid: CGSConnectionID, _ windowID: CGWindowID, _ rect: UnsafeMutablePointer<CGRect>) -> CGError

// MARK: - CGS 辅助函数

func gsGetWindowCount() -> Int {
    var count: Int32 = 0
    guard CGSGetWindowCount(CGSMainConnectionID(), 0, &count) == .success else { return 0 }
    return Int(count)
}

func gsGetMenuBarWindowList() -> [CGWindowID] {
    let windowCount = gsGetWindowCount()
    guard windowCount > 0 else { return [] }
    var list = [CGWindowID](repeating: 0, count: windowCount)
    var realCount: Int32 = 0
    guard CGSGetProcessMenuBarWindowList(CGSMainConnectionID(), 0, Int32(windowCount), &list, &realCount) == .success else { return [] }
    return [CGWindowID](list[..<Int(realCount)])
}

func gsGetWindowFrame(for windowID: CGWindowID) -> CGRect? {
    var rect = CGRect.zero
    guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect) == .success else { return nil }
    return rect
}
