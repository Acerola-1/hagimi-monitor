# macOS 27.0 (Golden Gate) & Xcode 27.0 技术调研与 HagimiMonitor 落地评估报告

- **报告日期**：2026-09-15
- **环境基准**：macOS 27.0 (Build 26A428), Xcode 27.0 (Build 27A266a), Swift 6.4 (swiftlang-6.4.0.34.1)
- **工程约束**：最低支持目标 macOS 15.0，双渠道（App Store 沙盒 / Direct 增强发行），经典毛玻璃视觉基线

---

## 目录
1. [背景与平台级核心变化](#一背景与平台级核心变化)
2. [P1 核心特性评估与官方依据](#二p1-核心特性评估与官方依据)
   - [P1.1 菜单栏架构现代化：NSStatusItemExpandedInterfaceDelegate](#p11-菜单栏架构现代化-nsstatusitemexpandedinterfacedelegate)
   - [P1.2 菜单项图标默认可见性变更：NSMenuItem.preferredImageVisibility](#p12-菜单项图标默认可见性变更-nsmenuitempreferredimagevisibility)
3. [P2 核心特性评估与官方依据](#三p2-核心特性评估与官方依据)
   - [P2.1 设置项指标重排：SwiftUI reorderContainer](#p21-设置项指标重排-swiftui-reordercontainer)
   - [P2.2 面板卡片拖拽重排架构评估与否决依据](#p22-面板卡片拖拽重排架构评估与否决依据)
   - [P2.3 硬件采样与纯 Apple Silicon 架构演化](#p23-硬件采样与纯-apple-silicon-架构演化)
4. [P3 核心特性评估与官方依据](#四p3-核心特性评估与官方依据)
   - [P3.1 状态上报框架：StateReporting.framework](#p31-状态上报框架-statereportingframework)
   - [P3.2 现代化诊断：MetricKit 重构与并发链路](#p32-现代化诊断-metrickit-重构与并发链路)
5. [综合评估决策矩阵（P1 至 P3）](#五综合评估决策矩阵p1-至-p3)
6. [落地路线图与工程实施建议](#六落地路线图与工程实施建议)
7. [官方依据与 SDK 头文件速查](#七官方依据与-sdk-头文件速查)

---

## 一、背景与平台级核心变化

随着 **macOS 27.0 (Golden Gate)** 与 **Xcode 27.0** 的正式发布，Apple 平台完成了多项历史性演进：

1. **全面纯 Apple Silicon 化**：
   - macOS 27 是首个**完全不再支持 Intel 架构 Mac** 的操作系统，官方正式结束对 x86_64 物理机型的系统支持；
   - Xcode 27 仅发布 Apple Silicon 版本，当 Target 部署目标设为 macOS 27.0+ 时，构建系统默认不再生成 x86_64 二进制切片；
   - Rosetta 2 仍作为过渡层内置在 macOS 27 中，但已确定将于后续主版本（macOS 28）彻底废弃。
2. **Xcode 27 与 Swift 6.4 编译工具链**：
   - 默认采用 Swift 6 严格并发检查（`Sendable` 传递闭包、Actor 隔离、跨并发域排他性验证）；
   - 经典链接器 `ld64` 被彻底移除，`-ld_classic` 标志正式作废；
   - 弃用 `PreviewProvider` 协议，全面推行 `#Preview` 宏；
   - 弃用 `NSBundleResourceRequest`（ODR），统一推进 Background Assets。
3. **安全与容器边界收紧**：
   - App Group 跨 Team 共享容器的访问权限默认拒绝，需在系统“隐私与安全性”中由用户明确授权。

官方参考链接：
- [Apple Developer macOS Overview](https://developer.apple.com/macos/)
- [macOS 27 Golden Gate Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)

---

## 二、P1 核心特性评估与官方依据

### P1.1 菜单栏架构现代化：`NSStatusItemExpandedInterfaceDelegate`

#### 1. 官方依据与 SDK 头文件
- **SDK 头文件来源**：
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSStatusItem.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSStatusItemExpandedInterfaceSession.h`
- **官方头文件接口与注释原文**：
  ```objc
  API_AVAILABLE(macos(27.0))
  @protocol NSStatusItemExpandedInterfaceDelegate <NSObject>
  @required
  /* Status items which do not use an NSMenu but instead position other windows
     ("expanded interface") relative to the item should begin showing their expanded
     interface upon receipt of this message. This method should be used instead of
     manually toggling your interface by target/action handling on the button or item.
     The expanded interface should be closed upon receipt of
     -statusItemDidEndExpandedInterfaceSession:animated:. This allows the status item
     to participate in keyboard navigation and menu tracking behaviors. If the expanded
     interface is closed through other user action, -cancel should be invoked on
     statusItem.expandedInterfaceSession. Other user action could be the user clicking
     an action which should dismiss the interface, or the app detecting a click in
     another window (see NSEvent.addLocalMonitorForEventsMatchingMask:handler:).
   */
  - (void)statusItem:(NSStatusItem *)statusItem didBeginExpandedInterfaceSession:(NSStatusItemExpandedInterfaceSession *)expandedInterfaceSession;
  - (void)statusItemDidEndExpandedInterfaceSession:(NSStatusItem *)statusItem animated:(BOOL)animated;
  @end

  @interface NSStatusItem : NSObject
  ...
  @property (nullable, weak) id<NSStatusItemExpandedInterfaceDelegate> expandedInterfaceDelegate API_AVAILABLE(macos(27.0));
  @property (nullable, readonly, strong) NSStatusItemExpandedInterfaceSession *expandedInterfaceSession API_AVAILABLE(macos(27.0));
  @end

  API_AVAILABLE(macos(27.0))
  @interface NSStatusItemExpandedInterfaceSession : NSObject
  - (void)cancel;
  @end
  ```

#### 2. HagimiMonitor 现状剖析与痛点
在 [HagimiMonitor/Views/Panel/FluidPanelController.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/FluidPanelController.swift) 中：
- **私有通知依赖**：为防止在全屏应用下呼出面板时菜单栏自动隐藏，目前通过广播未公开私有通知强行阻止菜单栏淡出（`FluidPanelController.swift#L435, L460, L911-L913`）：
  ```swift
  DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
  // static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
  ```
  这存在潜在的 App Store 审核风险及跨版本失效隐患。
- **系统全键盘访问与焦点缺失**：自建面板无法参与系统的 Control+F8 菜单栏全键盘巡航及左右方向键切换。
- **复杂的事件拦截**：通过 `NSEvent.addLocalMonitorForEvents` 监听按钮点击（`L302-L326`），还需特判 `event.modifierFlags.contains(.command)` 避免破坏系统状态栏的 Cmd+拖拽重排。

#### 3. 落地实施方案与双轨兼容伪代码
由于项目最低支持 macOS 15.0，必须在保持低版本现有机制的基础上，在 macOS 27 上分流启用官方会话代理：

```swift
final class FluidPanelController: NSObject {
    private let statusItem: NSStatusItem
    ...

    private func configureStatusItem() {
        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceDelegate = self
            // 在 macOS 27 下：localEventMonitor 仅拦截 .rightMouseDown（用于右键菜单）
            // 左键完全放行给 AppKit，由系统驱动 expandedInterfaceSession
            installContextMenuOnlyMonitor()
        } else {
            // macOS 15~26：维持原有的左键拦截、手动高亮与私有通知
            installLegacyEventMonitors()
        }
    }
}

@available(macOS 27.0, *)
extension FluidPanelController: NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        // 由系统发起展开（点击状态栏按钮或全键盘导航按下空格/回车）
        // 系统会自动管理全屏防隐和状态栏按钮高亮，无需手动调用 beginMenuTrackingNotification 与 button.highlight
        showPanelInternal()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        // 系统要求关闭（点击外部、按 Escape、切换桌面 Space 或切到其他状态项）
        if animated {
            dismissPanelWithFade()
        } else {
            panel.orderOut(nil)
            reclaimHiddenPanelResources()
        }
    }
}
```
- **评估结论**：**极高 ROI（强烈推荐实施）**。彻底合规化并拔除私有通知，大幅提升无障碍与系统协同体验。

---

### P1.2 菜单项图标默认可见性变更：`NSMenuItem.preferredImageVisibility`

#### 1. 官方依据与 SDK 头文件
- **SDK 头文件来源**：
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSMenuItem.h`
- **官方注释与声明原文**：
  ```objc
  typedef NS_ENUM(NSInteger, NSMenuItemImageVisibility) {
      NSMenuItemImageVisibilityAutomatic = 0,
      NSMenuItemImageVisibilityVisible   = 1,
      NSMenuItemImageVisibilityHidden    = 2
  } API_AVAILABLE(macos(27.0)) NS_SWIFT_NAME(NSMenuItem.ImageVisibility);

  /* Note that in macOS 27 and later, AppKit determines the visibility of menu item images,
     and will typically hide images. Use the preferredImageVisibility property with the
     .visible constant to specify that an image should always be visible. */
  @property (nullable, strong) NSImage *image;

  @property NSMenuItemImageVisibility preferredImageVisibility API_AVAILABLE(macos(27.0));
  ```

#### 2. HagimiMonitor 现状审计与已发生的视觉退化
在链接到 macOS 27 SDK 后，AppKit 默认对所有菜单项图标采取隐藏策略。全仓排查发现：
- **【严重 - 真实视觉退化】统计报表导出菜单**（[HagimiMonitor/Views/Report/ReportDetailsTableView.swift#L171-L189](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Report/ReportDetailsTableView.swift#L171-L189)）：
  ```swift
  Menu {
      Button { exportData(format: .csv) } label: {
          Label(ReportExportFormat.csv.label, systemImage: "doc.text")
      }
      Button { exportData(format: .html) } label: {
          Label(ReportExportFormat.html.label, systemImage: "chevron.left.forwardslash.chevron.right")
      }
      Button { exportData(format: .markdown) } label: {
          Label(ReportExportFormat.markdown.label, systemImage: "text.alignleft")
      }
  }
  ```
  在 macOS 27 下，上述 `Menu` 中的 SF Symbol 全部被隐藏，退化为纯文本菜单，损害了表格导出界面的精致度与辨识度。
- **状态栏右键菜单**（[FluidPanelController.swift#L347-L365](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/FluidPanelController.swift#L347-L365)）：目前“设置”与“退出”项为纯文本，当前不受影响，但未来若追加图标需防御。

#### 3. 落地实施方案
- **SwiftUI 修复（即时生效，全版本通用）**：
  在 `ReportDetailsTableView.swift` 的导出 `Menu` 上直接追加 `.labelStyle(.titleAndIcon)`：
  ```swift
  Menu {
      ...
  } label: { ... }
  .labelStyle(.titleAndIcon)
  ```
  此修饰符在 macOS 15~27 均原生支持，零版本分支开销。
- **AppKit 扩展封装**：
  ```swift
  extension NSMenuItem {
      func setSymbolImageVisible() {
          if #available(macOS 27.0, *) {
              self.preferredImageVisibility = .visible
          }
      }
  }
  ```
- **评估结论**：**零风险极高收益（立即修复）**。

---

## 三、P2 核心特性评估与官方依据

### P2.1 设置项指标重排：SwiftUI `reorderContainer`

#### 1. 官方依据与 Swift 接口定义
- **SDK 模块来源**：
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
- **声明签名**：
  ```swift
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  extension SwiftUICore.View {
      nonisolated public func reorderContainer<Item, ItemID>(
          for item: Item.Type,
          itemID: Swift.KeyPath<Item, ItemID>,
          isEnabled: Swift.Bool = true,
          move: @escaping (_ difference: SwiftUI.ReorderDifference<ItemID, SwiftUI.ReorderableSingleCollectionIdentifier>) -> Void
      ) -> some SwiftUICore.View where ItemID : Swift.Hashable, ItemID : Swift.Sendable
  }
  ```

#### 2. 设置页菜单栏指标重排（[GeneralSettingsView.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/GeneralSettingsView.swift)）改造评估
- **现状**：
  原常规设置中菜单栏指标列表将“已选项”和“未选项”混排在一个 `VStack` 内，通过行末上下微调按钮调整次序。历史实现包含固定项数上限。
- **改造方案**：
  必须将界面重构成两层容器，不可在全局混排列表上盲目启用拖拽：
  1. **“已选指标”容器（支持拖拽）**：
     至少保留 1 项。在 macOS 27 下使用 `.reorderContainer`，提供丝滑的原生手柄拖拽；macOS 15~26 维持上下微调箭头；
  2. **“备选指标池”容器（不可拖拽）**：
     点击即可加入已选池（得益于 `MenuBarMetricWidthEngine` 动态宽度解算契约，解除历史项数硬上限，至少保留 1 项）。备选池全选后整段自动折叠。

---

### P2.2 面板卡片拖拽重排架构评估与否决依据

#### 1. 否决原因深度剖析
针对是否在下拉监控主面板（[MonitorPanelView.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift)）中引入卡片实时拖拽重排，经架构审计后**坚决否决**：
1. **数据源每秒全量刷新重建**：
   [MonitorModels.swift#L1263-L1265](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorModels.swift#L1263-L1265) 中，`modules` 数组随着每秒的采样定时器全量生成与更新，顺序直接映射自静态枚举。如果在瞬态卡片上手动拖动，数据发布通道与手势状态发生重入竞争，极易导致悬停位点撕裂；
2. **破坏单宿主弹簧与严格尺寸契约**：
   根据项目规范（[AGENTS.md](file:///Users/acerola/Dev/Swift/hagimi-monitor/AGENTS.md) 与 [MetricCellSizing.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/MetricCellSizing.swift)），面板展开动画严格绑定统一几何提交链路（`SingleHostMotionCoordinator` / `PanelExpansionDriver`）。卡片位置动态拖动会产生不可控的高度形变，导致窗口弹簧震荡与严重掉帧；
3. **交互手势歧义**：
   主面板卡片的核心交互为“单击展开/折叠硬件明细”，狭窄卡片上叠加长按拖拽会导致点击响应延迟或频繁误触。
- **评估结论**：**禁止在下拉面板内实现手势拖拽重排**。如需自定义模块展示顺序，统一收敛在独立设置窗口中完成。

---

### P2.3 硬件采样与纯 Apple Silicon 架构演化

#### 1. 架构事实确认
查验 [hagimi-monitor.xcodeproj/project.pbxproj](file:///Users/acerola/Dev/Swift/hagimi-monitor/hagimi-monitor.xcodeproj/project.pbxproj#L462)：
```pbxproj
ARCHS = arm64;
MACOSX_DEPLOYMENT_TARGET = 15.0;
```
**HagimiMonitor 自立项起就是 100% 纯 `arm64` 原生架构**，工程本身没有 Intel 目标切片，因此 macOS 27 移除 Intel 物理机支持对 HagimiMonitor 的可执行文件二进制体积与编译架构零影响。

#### 2. Rosetta 2 遥测体系的存续价值
- 现状：
  [TopCPUProcess.swift#L246-L260](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/TopCPUProcess.swift#L246-L260) 使用 `sysctl.proc_translated` 实时探测第三方进程是否运行在转译环境；[MonitorPanelView.swift#L2686-L2720](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift#L2686-L2720) 展示 `RosettaBadge` 与横幅提醒。
- 策略：
  虽然 macOS 27 本身仅限 Apple Silicon，但用户仍可能通过 Rosetta 2 运行部分遗留应用。实测证明 `sysctl.proc_translated` 在 macOS 27 上完全正常有效。该遥测功能精准契合系统演进步伐，应**原样保留至 macOS 28 系统彻底移除 Rosetta 2 时再执行下线**。

---

## 四、P3 核心特性评估与官方依据

### P3.1 状态上报框架：`StateReporting.framework`

#### 1. 官方依据与 SDK 头文件
- **SDK 头文件来源**：
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/StateReporting.framework/Modules/StateReporting.swiftmodule/arm64e-apple-macos.swiftinterface`
- **声明签名**：
  ```swift
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  @attached(member, names: named(metadataDictionary))
  @attached(extension, conformances: StateReporting.ReportableMetadata)
  public macro ReportableMetadata()

  @available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
  final public class StateReporter<StableMetadata, VolatileMetadata> : @unchecked Swift.Sendable
      where StableMetadata : StateReporting.ReportableMetadata, VolatileMetadata : StateReporting.ReportableMetadata {
      public static func reporter(for domain: String, ...) -> StateReporter<StableMetadata, VolatileMetadata>
      public func reportTransition(to stateLabel: String?, stableMetadata: StableMetadata?, volatileMetadata: VolatileMetadata?)
  }
  ```

---

### P3.2 现代化诊断：`MetricKit` 重构与并发链路

#### 1. 官方依据与接口弃用事实
- **旧接口正式弃用**（查验 `MXMetricManager.h`）：
  ```objc
  @interface MXMetricManager : NSObject
  /* API_DEPRECATED("Use MetricManager.diagnosticReports instead.", macos(12.0, 27.0)) */
  - (void)addSubscriber:(id<MXMetricManagerSubscriber>)subscriber;
  @end
  ```
- **全新 Swift 并发接口与 StateReporting 深度绑定**（查验 `MetricKit.swiftmodule`）：
  ```swift
  @available(iOS 27.0, macOS 27.0, *)
  final public class MetricManager : @unchecked Swift.Sendable {
      public init(enabledStateReportingDomains: Set<StateReportingDomain> = [])
      public var diagnosticReports: some AsyncSequence<DiagnosticReport, Never> { get }
  }
  ```
  在 macOS 27 中，`MetricManager` 捕获的 `HangDiagnostic` 或 `CrashDiagnostic` 会**直接把应用在 `StateReporter` 中登记的上下文打包进 `ReportedState`**。

#### 2. 补齐 HagimiMonitor 现有诊断盲区
目前 [HagimiMonitor/Diagnostics/AppDiagnostics.swift](file:///Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Diagnostics/AppDiagnostics.swift) 存在两大痛点：
1. **崩溃无调用栈**：受限于 POSIX 信号安全要求，现有的 `CrashHandler` 捕获崩溃时只能写入固定字符串（如 `Caught signal: SIGSEGV`），无法抓取并符号化 Swift 调用栈；
2. **主线程卡顿无现场**：`HealthMonitor` 超时只能记录主线程无响应，无法获知停滞的代码行。

#### 3. 落地设计与实施伪代码
```swift
@available(macOS 27.0, *)
actor ModernDiagnosticsService {
    static let shared = ModernDiagnosticsService()

    func startMonitoring() {
        Task {
            let manager = MetricManager(enabledStateReportingDomains: [
                StateReportingDomain("com.acerola.hagimi-monitor.sampling"),
                StateReportingDomain("com.acerola.hagimi-monitor.panel")
            ])
            for await report in manager.diagnosticReports {
                switch report.result {
                case .hang(let hang):
                    self.recordDiagnostic("Hang", callStack: hang.callStackTree, state: report.reportedState)
                case .crash(let crash):
                    self.recordDiagnostic("Crash", callStack: crash.callStackTree, state: report.reportedState)
                @unknown default:
                    break
                }
            }
        }
    }

    private func recordDiagnostic(_ type: String, callStack: CallStackTree, state: ReportedState?) {
        // Direct Target: 将包含原始地址的 CallStackTree JSON 存入 Logs/Diagnostics/，供用户导出 Zip
        // App Store Target: 系统自动上传至 App Store Connect，由 Apple 服务器全自动符号化
        AppLogExporter.shared.persistDiagnosticPayload(type: type, callStack: callStack, state: state)
    }
}
```
- **评估结论**：**高价值基础设施升级（推荐落地）**。

---

## 五、综合评估决策矩阵（P1 至 P3）

| 级别 | 项目 | 核心收益 | 实施复杂度 | 风险评估 | 最终决策 |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **P1** | **菜单栏原生扩展会话** (`NSStatusItemExpandedInterfaceDelegate`) | 拔除私有通知；支持系统全键盘巡航与无障碍焦点 | 中 | 低（注意左键放行） | **强烈推荐实施 (Phase 1)** |
| **P1** | **菜单图标可见性防御** (`preferredImageVisibility` / `.labelStyle`) | 修复报表导出菜单 SF Symbol 图标丢失的现实退化 | 极低 | 零风险 | **立即实施 (Phase 1)** |
| **P2** | **设置项指标拖拽重排** (`reorderContainer`) | 拆分已选与备选池，结合原生手柄提供流畅重排体验 | 中 | 低（已选与备选解耦） | **推荐实施 (Phase 2)** |
| **P2** | **监控面板卡片拖拽重排** | 无（反而引入跳帧、尺寸漂移与手势歧义） | 极高 | 极高（破坏单宿主弹簧动画） | **坚决否决 (禁止实施)** |
| **P2** | **硬件采样架构整合** | 纯 arm64 架构维持现状；保留 Rosetta 2 转译监测 | 极低 | 零风险 | **维持现状至 macOS 28 (Phase 2)** |
| **P3** | **状态报告与现代 MetricKit 诊断** | 彻底攻克崩溃与卡顿缺乏堆栈与业务现场的盲区 | 中 | 低（零运行时损耗） | **推荐实施 (Phase 2)** |

---

## 六、落地路线图与工程实施建议

```
Phase 1：即时修复与合规化改造（建议立即开展）
  ├─ [UI 修复] 在 ReportDetailsTableView.swift 补充 .labelStyle(.titleAndIcon)，恢复导出菜单图标
  └─ [架构升级] 在 FluidPanelController.swift 接入 NSStatusItemExpandedInterfaceDelegate：
        ├─ localEventMonitor 仅拦截 .rightMouseDown，放行 .leftMouseDown 供系统接管
        ├─ 接管 didBeginExpandedInterfaceSession / didEndExpandedInterfaceSession 回调
        └─ macOS 27 环境彻底移除 beginMenuTrackingNotification 私有通知与手动 highlight

Phase 2：配置交互重构与诊断闭环（中短期迭代）
  ├─ [设置重构] 重构 GeneralSettingsView.swift：拆分“已选指标卡片”与“备选池”，接入 reorderContainer
  └─ [现代诊断] 在 AppDiagnostics 接入 MetricManager 异步序列，打通 StateReporting 业务状态

Phase 3：长线架构维护（跟踪观测）
  └─ 关注 macOS 28 周期，待系统完全废除 Rosetta 2 时，同步下线相关转译指示横幅与角标
```

---

## 七、官方依据与 SDK 头文件速查

1. **AppKit 菜单栏与状态项扩展**：
   - 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSStatusItem.h`
   - 关键符号：`NSStatusItemExpandedInterfaceDelegate`, `NSStatusItemExpandedInterfaceSession`
2. **AppKit 菜单项图片可见性**：
   - 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSMenuItem.h`
   - 关键符号：`NSMenuItemImageVisibility`, `preferredImageVisibility`
3. **SwiftUI 容器级原生拖拽重排**：
   - 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
   - 关键符号：`reorderContainer(for:itemID:isEnabled:move:)`, `reorderDestination`, `ReorderDifference`
4. **状态上报宏与领域服务**：
   - 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/StateReporting.framework/Modules/StateReporting.swiftmodule/arm64e-apple-macos.swiftinterface`
   - 关键符号：`@ReportableMetadata`, `StateReporter`, `StateReportingDomain`
5. **现代系统度量与诊断管道**：
   - 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/MetricKit.framework/Modules/MetricKit.swiftmodule/arm64e-apple-macos.swiftinterface`
   - 关键符号：`MetricManager`, `DiagnosticReport`, `CallStackTree`, `ReportedState`
