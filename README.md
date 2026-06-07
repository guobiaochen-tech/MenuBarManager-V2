# MenuBarManager-V2 功能说明

## 概述

监测 macOS 菜单栏右侧图标，将**被隐藏/溢出的图标**截图显示到菜单栏左侧，同时在左侧显示隐藏数量数字。

## 核心功能

### 1. 菜单栏图标扫描（Scanner.swift）

- 使用 `CGWindowListCopyWindowInfo` 扫描 layer=25 的窗口（菜单栏图标）
- 使用 CGS 私有 API (`CGSGetScreenRectForWindow`) 获取精确窗口坐标
- 按 `isOnScreen` 区分显示/隐藏状态
- 排除不需要的进程（如 LinkedNotesUIService）

### 2. 隐藏图标截图（IconCapturer.swift）

- 使用 **ScreenCaptureKit** 的 `SCScreenshotManager.captureImage` 抓取离屏窗口
- 通过 `SCShareableContent` 用 windowID 匹配隐藏窗口
- 使用 `SCContentFilter(desktopIndependentWindow:)` 单窗口过滤，支持离屏/遮挡窗口
- **裁剪上下留白**：窗口高度 > 菜单栏高度，裁掉上下 padding，只保留中间 24pt（菜单栏高度）
- **不移动、不干扰右侧任何图标**

### 3. 左侧图标显示（LeftIconPanel.swift）

- 创建透明 NSPanel 浮动窗口，level = statusBar + 1
- 图标从 `rightEdge`（屏幕宽度/2 - 130）往左排列
- 每个图标宽度按图片比例自动计算（最小 28pt），高度 = 菜单栏高度 24pt
- 图标间距 4pt
- 隐藏数量数字紧贴在最左图标左侧，垂直居中

### 4. 主控逻辑（AppDelegate.swift）

- 启动后 1.5 秒首次扫描，之后每 3 秒定时扫描
- **防闪烁**：只在隐藏数量变化时才重新截图和刷新显示
- 截图期间先显示数字，截图完成后显示图标+数字
- 使用 `imageCache` 缓存，相同数量不重复截图

## 文件结构

```
Sources/mbm-app/
├── main.swift          # 入口，NSApplication 启动
├── AppDelegate.swift   # 主控：定时扫描、状态管理、显示刷新
├── Scanner.swift       # 扫描：CGWindowListCopyWindowInfo + CGS 获取菜单栏窗口
├── Bridging.swift      # CGS 私有 API 声明（窗口坐标、窗口列表）
├── IconCapturer.swift  # 截图：ScreenCaptureKit 抓取离标窗口并裁剪
└── LeftIconPanel.swift # 显示：透明浮动面板排列图标和数字
```

## 构建与运行

```bash
bash build-app.sh        # 编译 + 打包 .app + 签名
open MenuBarManager-V2.app
```

需要**屏幕录制权限**：系统设置 → 隐私与安全性 → 屏幕录制 → 启用本应用

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| menuBarHeight | 24pt | 菜单栏高度 |
| baseIconWidth | 28pt | 图标最小宽度 |
| spacing | 4pt | 图标间距 |
| rightEdge | 屏幕宽度/2 - 130 | 图标排列的右边界 |
| 扫描间隔 | 3秒 | 定时器刷新频率 |
