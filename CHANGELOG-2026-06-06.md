# 技术变更记录 — 2026-06-06

本次迭代主要完成「隐藏图标真实归属识别 + 点击激活 + 视觉对齐 + 鼠标 hover 触发显示」四大功能。

---

## 一、隐藏图标真实归属识别（核心难点）

### 问题背景

`CGWindowListCopyWindowInfo(layer=25)` 拿到的所有菜单栏图标窗口，其 `kCGWindowOwnerPID` 均指向系统进程 `ControlCenter`（PID=638），无法直接得知图标所属的真实 app；`kCGWindowName` 全部为空；尝试过 AX 私有 API `_AXUIElementGetWindow` 反查 windowID 失败（返回 -25201）。

### 解决思路

第三方 app 的菜单栏图标实际上挂在它**自己进程**的 AX 树下（`AXExtrasMenuBar`）。因此采用：

1. 遍历 `NSWorkspace.shared.runningApplications`，对每个 app 创建 `AXUIElementCreateApplication(pid)`
2. 读取 `AXExtrasMenuBar` 的 children，拿到每个图标的 `AXPosition` / `AXSize`
3. 用图标在屏幕上的 X 坐标，匹配 layer=25 窗口的 X 坐标（取中心点最近且差值 ≤ 30pt）

### 防卡死与防崩溃

之前有 exit 139 崩溃，是因为某些 helper / XPC 进程的 AX 调用挂起。措施：

- `AXUIElementSetMessagingTimeout(axApp, 0.5)`：单次 AX 调用最多 0.5s 超时
- 跳过路径含 `.app/Contents/`（嵌套子进程）和 `XPCServices` 的 app
- 跳过名字含 `Helper` / `Renderer` / `Networking` / `Web Content` / `Graphics` 的进程
- `CFGetTypeID(bar) == AXUIElementGetTypeID()` 类型校验，防止伪元素崩溃

### 幽灵窗口过滤

layer=25 中存在大量「系统残留空窗口」，AX 上找不到对应 app。规则：`AX 匹配不上 → 直接丢弃`。

```swift
let cleaned = items.filter { $0.realAppPID != nil }
```

### 涉及文件

- `Sources/mbm-app/AXIconResolver.swift`（新建）
- `Sources/mbm-app/Scanner.swift`（接入解析结果）

---

## 二、点击图标激活对应 app

### 实现方式

使用 AX `kAXPressAction` 模拟用户真实点击：

```swift
AXUIElementPerformAction(icon.element, kAXPressAction as CFString)
```

相比 `NSRunningApplication.activate()`，AXPress 等价于真实鼠标点击该图标，由 app 自己决定弹窗或弹菜单，可靠性高。

### 回退策略

AXPress 失败时退回 `NSWorkspace.shared.open(bundleURL)`。

### 涉及文件

- `AXIconResolver.swift`：`press(_ icon:)` 方法
- `AppDelegate.swift`：`handleIconClick` / `performPress`

---

## 三、首次点击菜单 1 秒消失 bug

### 现象

点击隐藏图标后，目标 app 的下拉菜单出现 1 秒就消失。第二次点击正常。如果中途切换过其他窗口，第一次又会重现。

### 根因

AXPress 触发后，目标 app 立刻成为 frontmost。**这个 frontmost 切换过程**会向系统发出窗口焦点变更事件，刚弹出的菜单被切换过程误关。

### 修复

「先激活再点击」并隔 50ms：

```swift
NSRunningApplication(processIdentifier: targetPID)?.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { performPress(item) }
```

让 frontmost 状态在 AXPress 之前稳定下来。

### 顺带修的另一个穿透 bug

之前用全局事件监听 + `panel.ignoresMouseEvents = true` 实现点击，导致点击事件穿透到下面菜单栏。改为：

- panel 不设 `ignoresMouseEvents`
- 自定义 `ClickableIconView : NSImageView`，重写 `mouseDown` 直接处理点击，不穿透

---

## 四、视觉对齐细节

> ⚠️ 本节为旧方案，已被「第十节 图标偏小偏上根因修复」覆盖。保留作为历史记录。


### 图标垂直居中

之前用 `.scaleAxesIndependently` 拉伸严重。改为 `.scaleProportionallyDown` + 上下不对称 inset：

```swift
let iconTopInset: CGFloat = 6     // 顶部留白
let iconBottomInset: CGFloat = 1  // 底部留白
```

整体把图标往下挪约 1/5 菜单栏高度。

### 间距与右侧对齐

把图标间距从 `4pt` 改为 `0pt`，与系统菜单栏右侧图标间距保持一致。

### 数字垂直居中

`NSTextField` 默认按基线绘制，在窄高容器里看起来偏上。新增 `VCenterTextField + VCenterTextFieldCell`，在 `drawingRect(forBounds:)` 里根据 `cellSize` 动态计算 dy 居中：

```swift
override func drawingRect(forBounds rect: NSRect) -> NSRect {
    super.drawingRect(forBounds: adjustedFrame(for: rect))
}
```

字号从 14 改为 16，加粗。

---

## 五、鼠标 hover 才显示左边图标

### 需求

避免和当前 app 的「文件 / 编辑 / 视图」菜单重叠：默认隐藏左边图标，鼠标移到右上角菜单栏才显示。

### 触发与保持规则

| 状态 | 条件 |
|------|------|
| 触发显示 | 鼠标进入「右半屏 + 顶部 24px」 |
| 保持显示 | 显示中且鼠标在「整条菜单栏顶部 24px」内 |
| 启动倒计时 | 鼠标 y 离开菜单栏 |
| 真正隐藏 | 倒计时 2 秒未回到菜单栏 |

### 实现方式

`Timer` 每 100ms 轮询 `NSEvent.mouseLocation`（不用全局事件监听，避免高频 mouseMoved 耗 CPU）。

### LeftIconDisplay 重构

把「数据」与「显示」分离：

- `updateData(count:images:)`：更新缓存，仅当当前可见时立刻渲染
- `setVisible(_ on:)`：控制 panel 是否上屏
- `reset()`：清缓存 + 隐藏（用于扫描结果为 0）

### 涉及文件

- `LeftIconPanel.swift`：拆出 `cachedCount` / `cachedImages` / `isVisible`
- `AppDelegate.swift`：`hoverTimer` + `tickHover` 状态机 + `isShowing` / `hideDeadline`

---

## 六、权限要求汇总

| 权限 | 用途 | 何时申请 |
|------|------|----------|
| 辅助功能（Accessibility） | 读取其他 app 的 AX 树、AXPress 模拟点击 | 启动时 `AXIsProcessTrustedWithOptions(prompt:true)` |
| 屏幕录制（Screen Recording） | ScreenCaptureKit 截图隐藏图标 | 首次截图时系统弹窗 |
| App 管理（App Management） | macOS 13+ `NSRunningApplication.activate()` 需要 | 首次激活其他 app 时系统弹窗 |

---

## 七、关键参数（最新值）

| 参数 | 值 | 说明 |
|------|-----|------|
| menuBarHeight | 24pt | 菜单栏高度 |
| baseIconWidth | 28pt | 图标最小宽度 |
| spacing | 0pt | 图标间距（与系统右侧一致） |
| iconTopInset | 6pt | 图标顶部留白（下移用） |
| iconBottomInset | 1pt | 图标底部留白 |
| 数字字号 | 16pt 粗体 | |
| rightEdge | 屏幕宽度/2 - 130 | 图标排列的右边界 |
| 扫描间隔 | 3 秒 | 定时器刷新频率 |
| hover 轮询间隔 | 100ms | 鼠标位置检查频率 |
| hover 隐藏延时 | 2 秒 | 离开菜单栏后多久真正隐藏 |
| AX 调用超时 | 0.5 秒 | 单次 AX 调用上限，防卡死 |
| AX 匹配容差 | 30pt | windowFrame 中心 vs AX 图标中心 X 差值 |
| 激活后 AXPress 延迟 | 50ms | 等 frontmost 状态稳定 |

---

## 八、文件清单

```
Sources/mbm-app/
├── main.swift          # 入口
├── AppDelegate.swift   # 主控：扫描、点击分发、hover 状态机
├── Scanner.swift       # 扫描 layer=25 窗口 + 调用 AX 解析
├── AXIconResolver.swift  # 跨进程收集 AXExtrasMenuBar，按坐标匹配
├── Bridging.swift      # CGS 私有 API 声明
├── IconCapturer.swift  # ScreenCaptureKit 截图
└── LeftIconPanel.swift # 透明 panel 显示（数据/显示分离）
```

---

## 九、已知限制 / 待跟进

- AX 坐标匹配容差 30pt 是经验值，多显示器或缩放比例变化时可能需要调整
- hover 状态机使用 100ms 轮询，存在最多 100ms 显隐延迟，体验上可接受
- 极少数 app（如部分 Electron 应用）不在自己的 AXExtrasMenuBar 中暴露图标，会被当作幽灵窗口过滤掉，目前无解

---

## 十、图标偏小偏上根因修复（2026-06-06 晚）

### 现象

刘海屏（MBP 14/16）上左侧隐藏图标显示尺寸明显偏小，且垂直方向不居中（偏上）。在 24pt 菜单栏的外接屏上不太明显，但 33pt 刘海屏上极其突出。第四节用 `iconTopInset/iconBottomInset` 这种"经验偏移量"凑出来的居中，本质上是在掩盖根因。

### 根因（两层错误叠加）

**根因 A：`IconCapturer.swift` 给 NSImage 报了假尺寸**

```swift
// 旧代码
let pointSize = NSSize(width: CGFloat(cropped.width) / scale, height: mbh)
```

不管 `cropped` 实际像素高度是多少，pointSize 强行写成 `mbh`（33pt）。但菜单栏图标的窗口 frame.height 经常是 22pt，CGImage 是 44 像素 = 22pt 高的内容。强行声明这是 33pt 高的 NSImage，等于让下游所有按 `image.size` 算比例的代码都拿到错误数据。

**根因 B：`LeftIconPanel.swift` 的"放大 1.5 倍 + clip"方案**

```swift
// 旧代码
let displayScale: CGFloat = 1.5
let scaledH = panelHeight * displayScale
let scaledW = w * displayScale
let yOffset = -(scaledH - panelHeight) / 2
let clickView = ClickableIconView(frame: NSRect(x: xOffset, y: yOffset, ...))
clickView.imageScaling = .scaleProportionallyUpOrDown
panel.contentView?.clipsToBounds = true
```

作者本意是让图标看着大点：把 imageView 放大 1.5 倍，超出部分让 panel clip 掉。但 `.scaleProportionallyUpOrDown` 是按 **image.size**（来自根因 A 的撒谎尺寸）做 fit，再被 panel clip 一刀。两层错误叠加，最终视觉就偏小偏上。

### 修复

**修复 A：`IconCapturer.swift:38`** — pointSize 用真实裁后像素 ÷ scale：

```swift
let pointSize = NSSize(
    width: CGFloat(cropped.width) / scale,
    height: CGFloat(cropped.height) / scale
)
```

让 NSImage 报告真实尺寸，下游所有按 `image.size` 计算的逻辑就都对了。

**修复 B：`LeftIconPanel.swift`** — 删除 `displayScale=1.5` + clip 那套，改为：

```swift
let clickView = ClickableIconView(frame: NSRect(x: 0, y: 0, width: w, height: panelHeight))
clickView.imageScaling = .scaleProportionallyDown
clickView.imageAlignment = .alignCenter
```

imageView 与 panel 同尺寸，由 AppKit 按图像真实比例做 fit 并居中绘制，模仿系统菜单栏原生行为，不需要任何 inset 微调。

**修复 C：`iconWidths` 计算简化**

```swift
// 旧
let imgRatio = image.size.width / image.size.height
return max(baseIconWidth, panelHeight * imgRatio)

// 新
return max(baseIconWidth, image.size.width)
```

截图本身就含原生菜单栏的左右内边距，直接用 image.size.width 当 panel 宽度即可，不需要再乘 panelHeight 反推。

### 教训

1. **不要让 NSImage 谎报尺寸**。NSImage 的 `size` 是它对外宣称的 point 尺寸，下游的所有 fit/aspect/scale 计算都基于它。一旦这里撒谎，后面所有视觉代码都会被污染。
2. **不要用 inset 凑居中**。如果"居中"需要不对称的 top/bottom inset 来达成，说明数据源就错了——这是症状，不是修复。
3. **`.scaleProportionallyDown` + 同尺寸容器** 是显示菜单栏图标的正确范式。系统级 NSStatusItem 内部也是这套，自己复刻时不要画蛇添足搞 1.5 倍放大。
4. **刘海屏 33pt vs 普通屏 24pt** 是一个特殊放大器：根因 A 的 11pt 偏差在 24pt 屏上还能勉强对付，到 33pt 屏上立刻翻车。开发时只在一种屏上测，很容易漏掉这类比例失真。

### 涉及文件

- `Sources/mbm-app/IconCapturer.swift`（38 行附近）
- `Sources/mbm-app/LeftIconPanel.swift`（删除 displayScale 字段、重写 showCount 中图标视图构建）

### 关键参数更新

| 参数 | 旧值 | 新值 | 说明 |
|------|------|------|------|
| menuBarHeight | 24pt | actualMenuBarHeight() | 动态读取，刘海屏会得到 33pt |
| displayScale | 1.5 | 删除 | 放大方案废弃 |
| iconTopInset | 6pt | 删除 | 不再需要 inset 微调 |
| iconBottomInset | 1pt | 删除 | 同上 |
| imageScaling | scaleProportionallyUpOrDown | scaleProportionallyDown | 不再向上拉伸 |
| imageAlignment | 默认 | alignCenter | 显式声明居中 |

