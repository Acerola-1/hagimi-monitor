#!/usr/bin/env swift
import ApplicationServices
import Cocoa
import Foundation

// MARK: - HagimiMonitor Accessibility UI Automation Engine
// 基于 macOS 原生 Accessibility (AXUIElement) 与 CoreGraphics 的无障碍自动化测试工具。
// 零外部依赖，100% 避免视觉坐标猜想、Retina 缩放偏移与超时失焦问题。

final class HagimiA11yEngine {
    let pid: pid_t
    let app: AXUIElement

    init?(bundleId: String = "com.acerola.hagimi-monitor.direct") {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleId
        }
        guard let target = apps.first else {
            print("❌ 未找到运行中的 \(bundleId) 进程。请先启动应用。")
            return nil
        }
        self.pid = target.processIdentifier
        self.app = AXUIElementCreateApplication(pid)
        print("✅ 已连接到应用 [\(target.bundleIdentifier ?? bundleId)]，PID: \(pid)")
    }

    init?(pid: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: pid) else {
            print("❌ 进程 \(pid) 不存在或已退出。")
            return nil
        }
        self.pid = pid
        self.app = AXUIElementCreateApplication(pid)
        print("✅ 已连接到指定实例 [\(running.bundleIdentifier ?? "unknown")]，PID: \(pid)")
    }

    // MARK: - Menu Bar Item Operations

    func getMenuBarItem() -> (element: AXUIElement, frame: CGRect)? {
        var extrasBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasBarRef) == .success,
              let extrasBar = extrasBarRef else {
            return nil
        }
        let barElement = extrasBar as! AXUIElement
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              let item = children.first else {
            return nil
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef)

        var point = CGPoint.zero
        var size = CGSize.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &point) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }

        return (item, CGRect(origin: point, size: size))
    }

    func clickMenuBarItem() -> Bool {
        guard let info = getMenuBarItem() else {
            print("❌ 无法在 AXExtrasMenuBar 中找到菜单栏状态项")
            return false
        }
        let center = CGPoint(x: info.frame.midX, y: info.frame.midY)
        print("🖱️ 发送硬件级左键点击至菜单栏项中心：(\(center.x), \(center.y))")
        postClick(at: center, button: .left)
        return true
    }

    func rightClickMenuBarItem() -> Bool {
        guard let info = getMenuBarItem() else {
            print("❌ 无法在 AXExtrasMenuBar 中找到菜单栏状态项")
            return false
        }
        let center = CGPoint(x: info.frame.midX, y: info.frame.midY)
        print("🖱️ 发送硬件级右键点击至菜单栏项中心：(\(center.x), \(center.y))")
        postClick(at: center, button: .right)
        return true
    }

    // MARK: - Window & Hierarchy Dump

    func getWindows() -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        return windows
    }

    func dumpTree(element: AXUIElement? = nil, depth: Int = 0, maxDepth: Int = 5) {
        let target = element ?? app
        let indent = String(repeating: "  ", count: depth)

        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        var valueRef: CFTypeRef?
        var enabledRef: CFTypeRef?

        AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(target, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(target, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(target, kAXValueAttribute as CFString, &valueRef)
        AXUIElementCopyAttributeValue(target, kAXEnabledAttribute as CFString, &enabledRef)

        let role = roleRef as? String ?? "Unknown"
        let title = titleRef as? String ?? ""
        let desc = descRef as? String ?? ""
        let value = valueRef != nil ? "\(valueRef!)" : ""
        let isEnabled = (enabledRef as? Bool) ?? true

        var line = "\(indent)[\(role)]"
        if !title.isEmpty { line += " title:\"\(title)\"" }
        if !desc.isEmpty { line += " desc:\"\(desc)\"" }
        if !value.isEmpty { line += " value:\"\(value)\"" }
        if !isEnabled { line += " (DISABLED)" }

        print(line)

        guard depth < maxDepth else { return }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(target, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                dumpTree(element: child, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }

    // MARK: - Find & Action

    func findElements(matching predicate: (AXUIElement, String, String, String) -> Bool, in root: AXUIElement? = nil) -> [AXUIElement] {
        let current = root ?? app
        var matches: [AXUIElement] = []

        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(current, kAXDescriptionAttribute as CFString, &descRef)

        let role = roleRef as? String ?? ""
        let title = titleRef as? String ?? ""
        let desc = descRef as? String ?? ""

        if predicate(current, role, title, desc) {
            matches.append(current)
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                matches.append(contentsOf: findElements(matching: predicate, in: child))
            }
        }
        return matches
    }

    func clickElement(_ element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        AXUIElementCopyActionNames(element, &actionsRef)
        let actions = (actionsRef as? [String]) ?? []

        if actions.contains("AXPress") {
            let res = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if res == .success {
                return true
            }
        }

        // Fallback: 硬件点击元素中心
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var point = CGPoint.zero
        var size = CGSize.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &point) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }
        let center = CGPoint(x: point.x + size.width / 2.0, y: point.y + size.height / 2.0)
        postClick(at: center, button: .left)
        return true
    }

    // MARK: - Native CGEvent

    private func postClick(at point: CGPoint, button: CGMouseButton) {
        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp

        let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button)
        let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)

        down?.post(tap: .cghidEventTap)
        usleep(40000) // 40ms
        up?.post(tap: .cghidEventTap)
        usleep(40000)
    }

    /// 在指定位置滚动。dy 为滚轮像素增量：负值向下翻看下方内容。
    /// 先把光标移过去，滚轮事件才会落在目标滚动视图上；再拆成多步，
    /// 单次超大 delta 会被部分视图丢弃。
    func postScroll(dy: Int32, at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(120_000)

        let steps: Int32 = 6
        for _ in 0..<steps {
            if let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: dy / steps,
                wheel2: 0,
                wheel3: 0
            ) {
                scroll.location = point
                scroll.post(tap: .cghidEventTap)
            }
            usleep(40_000)
        }
    }
}

// MARK: - CLI Dispatcher

/// 按标题/描述子串查找并点击可点控件（按钮、单选、复选）。
/// 优先 AXPress，失败时回退到硬件点击（SwiftUI 部分控件不响应 AXPress）。
func clickButton(named name: String, in engine: HagimiA11yEngine) -> Bool {
    let clickableRoles: Set<String> = ["AXButton", "AXRadioButton", "AXCheckBox", "AXMenuButton"]
    let matches = engine.findElements(matching: { _, role, title, desc in
        clickableRoles.contains(role) && (title.contains(name) || desc.contains(name))
    })
    guard let target = matches.first else { return false }
    _ = engine.clickElement(target)
    return true
}

let rawArgs = CommandLine.arguments

// 工作机可同时常驻多个实例（App Store 版、Direct 常驻版、本次测试实例），
// 三者 bundleIdentifier 相同，仅按 bundleId 取 first 会连到别人的进程。
// 因此支持 --pid 精确定位被测实例；未指定时回退到 bundleId 匹配。
var targetPid: pid_t?
var args = [rawArgs[0]]
var argIndex = 1
while argIndex < rawArgs.count {
    if rawArgs[argIndex] == "--pid" {
        guard argIndex + 1 < rawArgs.count, let parsed = pid_t(rawArgs[argIndex + 1]) else {
            print("❌ --pid 需要一个合法的进程号")
            exit(2)
        }
        targetPid = parsed
        argIndex += 2
        continue
    }
    args.append(rawArgs[argIndex])
    argIndex += 1
}

guard args.count > 1 else {
    print("""
    HagimiMonitor 原生无障碍自动化测试工具 (CLI)
    
    用法:
      swift scripts/hagimi-ui.swift <command> [options] [--pid <进程号>]

    可用命令:
      status           查看当前被测进程与菜单栏图标无障碍信息
      click-menubar    通过真实事件精准点击菜单栏图标（呼出/收起主面板）
      right-click      右键点击菜单栏图标打开上下文菜单
      dump             完整导出当前应用的 Accessibility DOM 树
      expand-card <名> 展开/收起主面板卡片（例如: CPU, GPU, 内存, 网络）
      click-button <名> 按标题子串点击任意按钮（例如: 设置, 监视器, 工具）
      click-menu-item <名> 按标题子串点击 App 主菜单条目（例如: 报表）
      open-settings    触发 Cmd+, 打开偏好设置窗口
      run-test-flow    一键执行完整的无障碍回归测试流程
      windows          列出该实例的窗口归属与矩形（判断面板/设置窗是否由该 PID 打开）
      scroll <dy>      在窗口中心滚动（dy 为像素增量，负值向下），用于长列表

    提示: 传入 --pid 可精确定位某个实例，避免多实例下连错进程。
    """)
    exit(0)
}

let command = args[1]
let engine: HagimiA11yEngine
if let targetPid {
    guard let target = HagimiA11yEngine(pid: targetPid) else { exit(1) }
    engine = target
} else {
    guard let matched = HagimiA11yEngine() else { exit(1) }
    engine = matched
}

switch command {
case "status":
    if let item = engine.getMenuBarItem() {
        print("🎯 菜单栏无障碍元素已定位: Frame = \(item.frame)")
    } else {
        print("❌ 未在菜单栏找到状态项")
    }
    let windows = engine.getWindows()
    print("🪟 当前可见窗口数: \(windows.count)")

case "click-menubar":
    _ = engine.clickMenuBarItem()
    usleep(300000)
    let windows = engine.getWindows()
    print("窗口状态: 当前共有 \(windows.count) 个可见窗口")

case "right-click":
    _ = engine.rightClickMenuBarItem()

case "dump":
    // 可选深度参数：设置页等长列表需要更深的树才能看到指标行。
    let depth = args.count > 2 ? (Int(args[2]) ?? 4) : 4
    print("--- 正在导出无障碍元素树 (maxDepth=\(depth)) ---")
    engine.dumpTree(maxDepth: depth)

case "scroll":
    // 用法: scroll <dy> [x] [y]；省略坐标时取该实例最前面窗口的中心。
    guard args.count > 2, let dy = Int32(args[2]) else {
        print("❌ 用法: swift scripts/hagimi-ui.swift scroll <dy> [x] [y] [--pid N]")
        exit(2)
    }
    guard let window = engine.getWindows().first else {
        print("❌ 该实例没有可滚动的窗口")
        exit(1)
    }
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &origin) }
    if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }
    let point = CGPoint(
        x: args.count > 4 ? (Double(args[3]) ?? origin.x + size.width / 2) : origin.x + size.width / 2,
        y: args.count > 4 ? (Double(args[4]) ?? origin.y + size.height / 2) : origin.y + size.height / 2
    )
    print("🖱️ 在 (\(Int(point.x)), \(Int(point.y))) 滚动 dy=\(dy)")
    engine.postScroll(dy: dy, at: point)

case "windows":
    let windows = engine.getWindows()
    print("🪟 PID \(engine.pid) 归属窗口数: \(windows.count)")
    for (index, window) in windows.enumerated() {
        var titleRef: CFTypeRef?
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)

        var point = CGPoint.zero
        var size = CGSize.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &point) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }

        let title = titleRef as? String ?? ""
        let subrole = subroleRef as? String ?? ""
        print("  [\(index)] subrole=\(subrole) frame=\(Int(point.x)),\(Int(point.y)),\(Int(size.width))x\(Int(size.height)) title:\"\(title)\"")
    }

case "click-menu-item":
    // 点击 App 主菜单条目（如「打开数据报表…」）。菜单项不在 AXButton 角色下，
    // 故单列一条命令；按标题子串匹配，命中后 AXPress。
    let menuTitle = args.count > 2 ? args[2] : ""
    guard !menuTitle.isEmpty else {
        print("❌ 用法: swift scripts/hagimi-ui.swift click-menu-item <标题子串> [--pid N]")
        exit(2)
    }
    let menuItems = engine.findElements(matching: { _, role, title, desc in
        (role == "AXMenuItem" || role == "AXMenuBarItem")
            && (title.contains(menuTitle) || desc.contains(menuTitle))
    })
    guard let menuItem = menuItems.first else {
        print("❌ 未找到标题包含「\(menuTitle)」的菜单项")
        exit(1)
    }
    print("✅ 命中菜单项，执行 AXPress")
    _ = engine.clickElement(menuItem)

case "expand-card":
    let targetName = args.count > 2 ? args[2] : "CPU"
    print("正在查找卡片: \(targetName)...")
    if clickButton(named: targetName, in: engine) {
        print("✅ 已点击卡片: \(targetName)")
    } else {
        print("❌ 未在面板中找到包含 \(targetName) 的按钮，请先通过 click-menubar 打开面板")
    }

case "click-button":
    // 通用按钮点击：面板底部「监视器 / 工具 / 设置」等非卡片按钮走这里。
    // 相比 Cmd+, 更可靠——同 bundleId 多实例并存时无需先激活到具体进程。
    let targetName = args.count > 2 ? args[2] : ""
    guard !targetName.isEmpty else {
        print("❌ 用法: swift scripts/hagimi-ui.swift click-button <按钮标题子串> [--pid N]")
        exit(2)
    }
    print("正在查找按钮: \(targetName)...")
    if clickButton(named: targetName, in: engine) {
        print("✅ 已点击按钮: \(targetName)")
    } else {
        print("❌ 未找到包含 \(targetName) 的按钮")
        exit(1)
    }

case "open-settings":
    print("正在激活应用并发送 Cmd+, ...")
    let src = CGEventSource(stateID: .hidSystemState)
    let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
    let commaDown = CGEvent(keyboardEventSource: src, virtualKey: 43, keyDown: true)
    let commaUp = CGEvent(keyboardEventSource: src, virtualKey: 43, keyDown: false)
    let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

    cmdDown?.flags = .maskCommand
    commaDown?.flags = .maskCommand
    commaUp?.flags = .maskCommand

    cmdDown?.post(tap: .cghidEventTap)
    commaDown?.post(tap: .cghidEventTap)
    usleep(50000)
    commaUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)
    print("✅ 已发送快捷键")

case "run-test-flow":
    print("🚀 开始全套自动化回归测试 (基于原生无障碍)...")
    
    // 确保初始状态收起
    if !engine.getWindows().isEmpty {
        print("  初始状态面板已开启，先执行收起...")
        _ = engine.clickMenuBarItem()
        usleep(400000)
    }

    // 1. 开合面板测试
    print("Step 1: 点击菜单栏呼出面板")
    _ = engine.clickMenuBarItem()
    usleep(400000)
    let win1 = engine.getWindows().count
    print("  面板可见窗口数: \(win1) (期望 >= 1)")
    guard win1 >= 1 else {
        print("❌ 呼出面板失败")
        exit(1)
    }
    
    // 2. 卡片展开测试
    print("Step 2: 展开 CPU 明细卡片")
    let cpuButtons = engine.findElements(matching: { _, role, title, desc in
        role == "AXButton" && (title.contains("CPU") || desc.contains("CPU"))
    })
    if let cpuBtn = cpuButtons.first {
        _ = engine.clickElement(cpuBtn)
        usleep(300000)
        print("  ✅ CPU 卡片已点击展开")
    } else {
        print("⚠️ 未找到 CPU 按钮")
    }
    
    // 3. 收起面板
    print("Step 3: 再次点击菜单栏收起面板")
    _ = engine.clickMenuBarItem()
    usleep(400000)
    let win2 = engine.getWindows().count
    print("  收起后面板窗口数: \(win2) (期望 0)")
    
    print("🎉 全套核心无障碍回归测试流程执行完毕！")

default:
    print("未知命令: \(command)")
}
