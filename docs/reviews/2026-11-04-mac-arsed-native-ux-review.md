# Hagimi Monitor：macOS 原生交互体验独立审查

审查日期：2026-11-04（Asia/Shanghai）

审查依据：已安装的 [Mac-Arsed Mac App Skill](/Users/acerola/.agents/skills/mac-arsed-mac-app/SKILL.md) 及其四份 reference 文件；Apple 当前官方 HIG / API 文档。

源码基线：`d855b7d337c251b8a524bacfb15de469e08c4b2f`。审查开始时工作区干净。

## 结论

Hagimi Monitor 已具备成熟的 Mac 菜单栏工具基础：原生状态项、临时面板与钉住面板分工明确，设置与统计报表使用独立原生窗口，设置侧栏可用方向键导航，⌘, 可以打开设置，报表对数据不足与覆盖缺口有明确解释。现有经典毛玻璃、紧凑指标卡和配色体系值得保留。

本轮列出 **9 项有具体证据的发现**：2 项 P1、6 项 P2、1 项 P3；没有发现 P0。其中 4 项包含运行观察，5 项主要由源码支持。**源码风险的优先级是复核与修复排序，不表示运行缺陷已经确认。** 最值得优先投入的是设置控件的可访问名称、核心展开操作的键盘可达性、全局快捷键录制的冲突保护，以及临时面板与子浮层的关闭边界。

这是一份有边界的专项审查：主菜单栏面板的真实点击、跨显示器、全屏 Spaces、完整 Tab 遍历和 VoiceOver 工作流尚未可靠完成，不能据此宣布整款应用已经通过原生交互验收。

## 方法、环境与证据边界

- 完整读取所用 Skill 主文件，并读取 `detailed-rules.md`、`review-and-qa.md`、`design-outputs.md`、`swiftui-appkit.md`。没有阅读其他 Skill 的审查报告，也没有委派其他审查代理。
- 根目录存在 `.codegraph/`，源码定位先使用 CodeGraph，再读取被省略的相关源码片段和执行定向文本核对。没有用历史审查结论作为问题来源。
- 产品分类为 **菜单栏 utility + 独立统计 viewer**。核心对象是实时模块、可展开明细、可排序指标、显示器档案、统计报表与用户偏好。文件导入、多文档、Finder 拖入、广泛 Undo 不作为这类工具的必备项。
- 环境：macOS 27.2（26B123）、Xcode 27.2（27B52）；项目最低部署版本为 macOS 15。运行结果不外推到 macOS 15 / 26。
- 两个渠道均用本次源码完成 Debug 构建：`HagimiMonitorDirect` 和 `HagimiMonitor`，各自使用独立 DerivedData，均为 `BUILD SUCCEEDED`。本轮没有运行单元测试、UI 测试或性能基准；构建只证明可编译。
- 本机已有多个同名运行实例。最初连接普通构建产物得到的观察不计入正式问题实测证据。随后复制本次 Direct 构建到 `tmp/native-ux-runtime/HagimiNativeUXAudit.app`，仅调整**临时产物**的 Bundle ID / 显示名称并重新临时签名，以避免误操作其他实例。没有改动工程配置、源资源或产品源码。
- 正式运行观察来自上述隔离实例，使用原生界面工具的 AX 树和窗口截图。隔离实例采用独立偏好域；签名、权限、自动更新、登录项与真实硬件控制行为不代表正式安装包。未通过切换系统设置来验证外观和辅助功能，也未执行显示器控制、键盘锁定或数据清理。
- 界面工具在无普通窗口时存在连接超时 / 再次打开设置的情况；快捷面板未取得可归属的窗口观察。因而不把“工具未显示面板”当作应用缺陷，不把自动重新打开设置误判为关闭失效。
- 构建日志：[Direct](/Users/acerola/Dev/Swift/hagimi-monitor/tmp/native-ux-runtime/direct-build.log)、[App Store](/Users/acerola/Dev/Swift/hagimi-monitor/tmp/native-ux-runtime/appstore-build.log)。临时日志和测试产物不是长期归档证据；下文记录了可供后续复核的源码位置与运行步骤。

验证标记：**R**＝运行观察与源码相互支持；**S**＝源码支持的潜在体验问题，待运行确认；**M**＝人工验证项，不计入缺陷数量。优先级：P0＝重大故障；P1＝核心任务或辅助操作存在明显障碍；P2＝可绕过但影响正常操作的行为缺口；P3＝低风险的效率与细节问题。

## 当前原生交互结构

- **菜单栏入口**：`NSStatusItem` 标准按钮图像；macOS 27 使用 expanded-interface delegate，旧版本使用本地鼠标事件路径。左键打开监控，右键提供设置和退出。
- **实时监控 / 快捷面板**：自定义 `NSPanel` + 多个 `NSHostingView` + 原生滚动容器；行头负责展开，明细内保留各自操作；排序同时提供长按拖动、上下文移动命令和辅助功能动作。
- **小工具**：`NSPopover` 锚定实际入口，使用系统开关；激活中的功能保留入口，权限状态有刷新路径。
- **设置**：原生 `NSWindow`、SwiftUI sidebar `List(selection:)`、分组控件；保存窗口几何和用户偏好。
- **统计报表**：独立可缩放窗口，原生 SwiftUI 内容；HTML 导出使用 `NSSavePanel`，打印按需建立临时 WebKit 会话。
- **复制 / 互操作**：显示器档案已有完整纯文本复制及短暂成功反馈。没有因为应用不支持无关文件拖入而扣分。

## 发现

### N01 · P1 · 多个设置开关没有可访问的用途名称【R】

**模块：** 常规设置、CPU / GPU 等模块设置、数据统计设置。

**问题与证据：** 隔离实例的 AX 树将“开机自启”显示为独立文本，开关仅为 `开关按钮 off`；CPU 设置中“在面板中显示”“默认展开”“显示 CPU 占用排行”等也表现为独立文本与无名称开关。统计页同样出现 `文本 记录数据统计` 后接 `开关按钮 on`。源码使用 `Toggle("", isOn: ...)`，外层 `SettingsRow` 只把标题与 accessory 放在 `HStack`，没有建立标签配对。参见 [常规开关](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/GeneralSettingsView.swift:23)、[模块开关](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/ModuleSettingsView.swift:28)、[SettingsRow](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/SettingsLayout.swift:147)。

**用户影响：** 逐控件导航时难以单独辨认开关用途，依赖屏幕阅读器或语音操作的用户需要额外回溯上下文，多个开关相邻时更易误操作。

**设计依据：** Apple 要求为辅助技术提供可理解的控件标记，并提供 [`accessibilityLabeledPair`](https://developer.apple.com/documentation/swiftui/view/accessibilitylabeledpair%28role%3Aid%3Ain%3A%29) 来关联分离的标签与内容。参见 [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)。

**改进方向：** 给 Toggle 本身提供真实本地化标题并隐藏视觉标签，或在通用行组件中显式建立标题与控件关系。对多个控件的行逐一标记，保留开关的值与操作语义。

**验证与局限：** 已实际检查 AX 暴露结果；没有完成 VoiceOver 朗读和 Voice Control 全流程，因此不声称所有辅助技术均完全不可用。复核应逐开关确认名称、状态及操作结果。

### N02 · P1 · 核心模块展开缺少明确的普通键盘操作路径【S】

**模块：** 实时面板的 CPU / GPU / 内存 / 网络 / 电源 / 显示器等行头。

**问题与证据：** 行头通过 `onTapGesture` 触发展开，再增加 `.isButton` 辅助功能 trait；对应实现没有 `Button`、明确的可聚焦入口、Space / Return 处理或方向键展开命令。可见 [通用模块行头](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift:1009)、[网络](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift:1930)、[电源](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift:2075)、[显示器](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/DisplaySection.swift:294)。排序自定义动作只负责移动，不能替代展开操作。

**用户影响：** 用户即使通过快捷键呼出面板，也可能无法用通常的 Tab 与 Space 完成“选择模块—展开—读明细”的核心任务。单有按钮语义不等于完整的普通键盘交互。

**设计依据：** [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) 与 Skill 的 Native controls / Keyboard and focus 规则：重要操作应具备键盘路径、焦点反馈，并支持 Full Keyboard Access。

**改进方向：** 将行头封装为保留现有外观的语义 Button，或补齐等价焦点、激活与展开状态。焦点顺序跟随视觉排序；折叠明细不可获得隐藏焦点；展开后避免焦点意外跳到其他宿主。保留现有拖动和上下文排序。

**验证与局限：** 源码风险，尚未在真实主面板上完成 Tab / Shift-Tab / Space / Return、Full Keyboard Access 或 VoiceOver 激活测试。不能据此断言 SwiftUI 自动生成的 AXPress 一定失败。P1 是因其覆盖核心任务而建议优先复核。

### N03 · P2 · 全局快速呼出录制器接受常用保留组合，未提示冲突【R】

**模块：** 常规 → 快速呼出。

**问题与证据：** 在隔离实例中点击录制后输入 ⌘Q，控件最终显示 `⌘、Q`，没有看到针对该组合的冲突解释；随后已清除临时快捷键。源码仅校验是否带 Command / Control / Option 或为功能键，随后直接调用 `KeyboardShortcuts.setShortcut`；未在此路径执行标准组合 / 系统占用 / 注册失败的可见校验。参见 [录制处理](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/GeneralSettingsView.swift:258)、[全局触发注册](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/AppDelegate.swift:219)。

**用户影响：** 用户容易把退出、切换等肌肉记忆组合设成全局操作；还可能出现设置显示已保存、实际注册或触发不符合预期的困惑。

**设计依据：** [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) 要求尊重系统和标准快捷键；全局命令还会影响其他应用中的使用习惯。

**改进方向：** 保存前检查系统保留、菜单常用组合和可检测的注册冲突；对不合适的组合提供具体解释及重新录制入口。无法可靠检查的第三方冲突如实提示范围，勿以“已显示”冒充“已注册成功”。

**验证与局限：** 已验证“接受并显示 ⌘Q”。没有验证它确实抢走其他应用的退出命令，也没有证明任何跨进程快捷键被拦截；运行期间出现过独立的 Sparkle 首次更新询问，该询问不是快捷键冲突提示。

### N04 · P2 · 未钉住快捷面板的外部点击判断可能把工具子浮层算作外部【S】

**模块：** 快速呼出面板 → 小工具。

**问题与证据：** `PinnedPanelController` 的本地鼠标监听只排除 `event.window === self.panel`；其他窗口一律进入 `dismissIfTransient()`，未钉住时执行隐藏。小工具则由独立窗口承载的 `NSPopover` 展示。参见 [事件监听](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/PinnedPanelController.swift:151)、[临时态关闭](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/PinnedPanelController.swift:183)、[工具浮层](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/QuickToolsPopover.swift:107)。失去 key 的路径也没有在此区分子浮层。

**用户影响：** 潜在表现为刚打开工具，第一次点击内部开关或浮层获得焦点时，父面板就收起，打断操作；钉住后可能可以绕过。

**设计依据：** Skill 的 Windows / Keyboard and focus 规则与 Apple [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)：父子界面应形成连续任务，子浮层内交互不应等同于离开当前任务。

**改进方向：** 把父面板及其当前工具浮层识别为同一交互区域，并区分子窗口临时接管焦点与真正离开应用。复用浮层 presenter 的生命周期信息，避免仅凭任意窗口不相等就关闭。

**验证与局限：** 源码支持的候选问题，尚未实测 NSPopover 在此系统上的具体窗口 / key 事件顺序。需分别测试临时态和钉住态；不应把普通菜单栏面板、所有浮层都泛化为已故障。

### N05 · P2 · 快捷面板与旧系统菜单栏面板缺少显式 Escape 收起路径【S】

**模块：** 快速呼出面板；macOS 15 / 26 的菜单栏兼容路径。

**问题与证据：** 面板根视图的 `.onExitCommand` 仅取消排序；`NativePanelWindow` 没有 `cancelOperation` 处理；两个控制器主要依赖鼠标或失焦关闭。参见 [Exit 命令](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorPanelView.swift:216)、[窗口子类](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/NativePanelLayerView.swift:6)、[快捷面板失焦](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/PinnedPanelController.swift:350)。macOS 27 的菜单栏路径另有系统 expanded-interface session，不能按相同结论处理，参见 [session 回调](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/FluidPanelController.swift:987)。

**用户影响：** 潜在表现为用户看完临时面板按 Esc，只取消了不存在的拖动，仍需鼠标离开或再按呼出快捷键；子浮层与拖动并存时，取消层次可能不清晰。

**设计依据：** [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) 的 Escape 取消惯例；Skill 要求临时界面具备可预期的取消与焦点行为。

**改进方向：** 定义分层取消顺序：正在拖动时先取消拖动，工具浮层打开时先关闭浮层，否则关闭临时面板。钉住面板是否响应 Esc 应明确决定，防止误破坏用户的常驻意图。macOS 27 配合系统 session，避免重复关闭。

**验证与局限：** 源码风险，没有实测旧系统或快捷面板的 Esc。AppKit 默认响应链的最终表现、首响应者和系统 session 行为仍需真机验证；没有宣称 macOS 27 普通菜单栏面板的 Esc 已失效。

### N06 · P2 · 报表已有打印和导出功能，却没有完整的菜单命令路径【R】

**模块：** 独立统计报表窗口、应用菜单。

**问题与证据：** 隔离实例的报表 AX 树能看到“打印或保存为 PDF”“另存为 HTML 文件”；菜单栏只有应用、编辑、显示、窗口、帮助，没有文件菜单。尝试 ⌘P 未观察到打印对话框。源码的 `AppMenuCommands` 只增加关于、退出、设置和打开报表；报表操作按钮没有键盘等价，参见 [命令定义](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/HagimiMonitorApp.swift:36)、[报表操作条](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Report/ReportTopBarView.swift:82)。

**用户影响：** 用户不能通过熟悉的“文件 → 打印”和菜单搜索发现现成功能，键盘用户需遍历到图标按钮。只读报表仍然有保存和打印需求。

**设计依据：** Apple [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) 要求可发现的命令及标准键盘等价；[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) 规定 ⌘P 的打印惯例。

**改进方向：** 为当前报表增加“打印…”（⌘P）、“导出 HTML…”与适当的重新载入命令；根据窗口焦点、数据就绪及正在执行状态校验可用性。仅有设置窗口时禁用报表专用命令。无需为此引入多文档或重新设计报表外观。

**验证与局限：** 已运行观察菜单结构、按钮名称和 ⌘P 尝试；随后点击打印按钮也未观察到打印对话框，原因未定位，不能把这一观察写成“打印实现本身确定损坏”。本条确认的是菜单 / 显式快捷键接线缺口，不是打印成功率。

### N07 · P2 · 开机自启失败只回弹开关，没有解释和恢复指引【S】

**模块：** 常规 → 开机自启。

**问题与证据：** `SMAppService.mainApp.register()` / `unregister()` 抛错后，catch 只切回 `launchAtLogin`，没有发布错误状态、展示原因或提供系统设置入口。参见 [updateLaunchAtLogin](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/MonitorSettings.swift:1381)。

**用户影响：** 系统拒绝或登记异常时，用户只看到开关弹回，不知道是否生效、原因是什么、能否修复；反复点击无法得到更多信息。

**设计依据：** Apple [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) 要求说明无法执行的操作及原因，并建议将状态反馈放在相关控件附近。

**改进方向：** 保持原状态回滚，同时在该行附近显示简短、可访问的失败说明；按真实系统状态提供重试或打开“登录项”入口。不要给每次成功切换弹确认框。

**验证与局限：** 已核对错误路径，没有故意改变登录项或制造系统拒绝。隔离重签名实例不适合代表正式安装包的 SMAppService 行为，因此本条不是“本机开机自启失败”的报告。

### N08 · P2 · 旧系统状态项路由忽略 Control-click 的上下文菜单含义【S】

**模块：** macOS 15 / 26 菜单栏图标。

**问题与证据：** 旧系统监听 `.leftMouseDown` 与 `.rightMouseDown`，路由输入只接收 `commandDown`。左键始终走 `legacyToggle`，右键才打开菜单，Control 修饰没有参与。参见 [输入路由](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/FluidPanelController.swift:73)、[事件接线](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/FluidPanelController.swift:425)。本地监视器会消费左键事件，不能仅依赖普通 NSView 的后续默认处理。

**用户影响：** 使用 Control + 单击代替次要点击的用户，可能打开监控面板，无法以熟悉手势获得设置 / 退出菜单；实际右键仍有替代路径。

**设计依据：** Apple 官方 [Right-click on Mac](https://support.apple.com/en-gb/guide/mac-help/mh35853/mac) 将 Control-click 明确作为打开快捷菜单的标准方式；Skill 的 Native controls 规则要求保持修饰键惯例。

**改进方向：** 在兼容事件路径中区分普通左键与 Control-click，并让 Control-click 与次要点击共用上下文菜单。继续保留 Command 拖动的系统归属；macOS 27 单独确认系统 session 的处理，避免拦截冲突。

**验证与局限：** 源码支持的兼容性风险，没有 macOS 15 / 26 实机验证，不能将它写成所有受支持版本均已实测失败。

### N09 · P3 · 关闭设置窗口后丢失最后使用的页面【R】

**模块：** 设置窗口的页面恢复。

**问题与证据：** 隔离实例选中“数据统计”，⌘W 关闭设置、回到仍打开的统计报表，再按 ⌘,，新设置窗口选中“常规”。源码每次创建 `SettingsRootView` 都初始化 `selection = .general`；关闭窗口释放视图树，没有独立保存最近 route。参见 [初始路由](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Settings/SettingsRootView.swift:7)、[关闭清理](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/SettingsWindowPresenter.swift:35)。窗口尚未关闭时再次唤起设置可保持当前页，二者应区分。

**用户影响：** 反复调试某个模块或查看统计的用户，每次重新打开设置都要多选一次页面；无数据损失，影响较轻。

**设计依据：** Apple [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) 建议恢复最近查看的设置面板；Skill 的 State preservation 强调保留有意义的选择。

**改进方向：** 把最近可用 route 与窗口视图生命周期分开保存。无显式目标时恢复最近页；“关于”、统计深链等显式目标继续优先。跨渠道或硬件变化导致页面不再可用时回退常规。

**验证与局限：** 已实测同一进程中关闭 / 再开的行为；没有进行跨进程持久性测试，源码表明它也未保存最近路由。不是要求保留已关闭窗口的整棵视图树。

## 值得保留的设计

- **系统状态项基础正确。** 标准 `button.image`、状态项自身 effectiveAppearance、Command 手势交回系统、macOS 27 delegate 的采用，均体现了平台适配意识。多屏是否完全正确仍待实测。
- **设置具有原生导航基础。** 已实测点击 CPU 后按 ↓ 选中 GPU，内容同步变化；⌘, 能从报表唤起设置，⌘W 能关闭设置而不退出应用。
- **排序不完全依赖拖动。** 主面板已有上下文方向移动与辅助功能动作，见 [PanelReorderInteraction](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/PanelReorderInteraction.swift:503)。不应报告成“排序完全鼠标专属”。
- **信息不足反馈有证据边界。** 报表在本次观察中明确显示数据完整度、覆盖缺口、有效数据不足和暂不评分，不把未知伪装为正常。
- **减少动态效果已有实现。** 菜单栏动画与面板 motion 路径读取系统 Reduce Motion，不因某个视图没有 Environment 属性就认定全局缺失。实际系统开关效果仍待验证。
- **渐进披露符合工具定位。** 行头摘要、展开明细、可配置默认展开、完整显示器档案复制，都适合“快速看一眼，再深入”的监控任务；无需为符合系统外观而移除现有产品特色。

## 待人工验证清单【M，不计入 9 项发现】

1. **主状态项完整生命周期：** 左键开关、快速连点、右键、Control-click、点应用外 / 同应用其他窗口、⌘Tab、Esc、连续关闭重开；macOS 15 / 26 / 27 分别执行。特别区分系统 session 与兼容路径。
2. **键盘与辅助功能：** 开启系统键盘导航 / Full Keyboard Access 后，完整遍历主面板、展开、排序、复制档案、小工具、设置；记录焦点环、Shift-Tab、滚动后焦点、隐藏内容是否仍可达；再用 VoiceOver 操作主任务。不要用 AX 树可见代替全部验收。
3. **子浮层：** 从临时快捷面板、钉住面板、普通菜单栏面板分别打开工具，点内部开关、点击外部、连续点击原入口、Esc；确认只关闭期望层级且焦点返回合理。
4. **多屏和 Spaces：** 副屏菜单栏、主屏切换、不同缩放 / 高度、Dock 方位、全屏应用、自动隐藏菜单栏、断开屏幕后重新呼出。主面板已有边界夹取，不能仅凭缺少实测认定不支持多屏。
5. **钉住面板位置恢复：** 尤其验证只剩很窄一条与屏幕相交时能否完整找回；[ensureOnScreen](/Users/acerola/Dev/Swift/hagimi-monitor/HagimiMonitor/Views/Panel/PinnedPanelController.swift:303) 当前主要用矩形相交判定，尚未实测可见操作区是否足够。作为定向验证，不升级为已确认丢窗缺陷。
6. **鼠标与拖动：** 可视按钮边缘是否全部可点、长按移动与点击展开冲突、拖出面板、Esc 取消、边缘自动滚动、中途反转和上下文排序；不根据视觉尺寸推断真实命中区。
7. **外观与辅助显示：** 浅 / 深、平衡 / 活力、复杂壁纸、提高对比度、降低透明度、减少动态效果；系统材质与行卡可读性以原生截图为准。
8. **真实错误与权限：** 正式签名包的登录项拒绝 / 需批准、通知拒绝、键盘锁权限不足、显示器断开与 DDC 不支持、打印生成失败 / WebKit 超时；确认说明及恢复入口。隔离实例不承担硬件和权限验收。
9. **报表打印与导出：** 正式包测试按钮、⌘P、取消、重复触发、大范围准备过程、错误反馈、保存面板、PDF 与 HTML 内容。此次未观测到打印对话框不足以确定根因，也不能宣称打印成功。

## 建议实施顺序与优先处理清单

以下 9 项按用户收益与依赖排序；对于 S 项，第一步都是完成上述定向复现，只有确认后再实施。

1. **N01：补齐设置开关的可访问名称（P1，R）。** 范围明确、外观影响小，先建立可核对的设置交互基础。
2. **N02：核实并完善模块展开的键盘路径（P1，S）。** 这是快捷呼出之后能否继续完成任务的核心链路，应包含跨 NSHostingView 的焦点验证。
3. **N03：加入全局快捷键的冲突保护与失败反馈（P2，R）。** 先避免把不合适的组合无声保存，再验证实际注册与触发。
4. **N04：复现并修正临时父面板与工具子浮层的关闭边界（P2，S）。** 先统一父子界面关系，才能可靠处理取消与焦点返回。
5. **N05：统一分层 Escape 行为（P2，S）。** 在 N04 明确关闭层级后实施，覆盖拖动、浮层、临时态及系统 session。
6. **N06：补上报表菜单、打印快捷键与命令可用性（P2，R）。** 复用现有功能，改善可发现性和键盘效率。
7. **N07：为开机自启失败提供行内解释与恢复路径（P2，S）。** 在正式签名包中验证系统状态，不用隔离签名结果替代。
8. **N08：修正旧系统 Control-click 路由（P2，S）。** 与菜单栏兼容路径回归一起做，保护 Command 拖动和 macOS 27 系统行为。
9. **N09：恢复最近设置页（P3，R）。** 放在核心可达性与关闭行为稳定后完成，保持当前资源释放策略。

本轮不建议启动视觉重做、替换经典毛玻璃、增加文档型功能或为凑齐规范而扩张功能范围。后续综合评审应保留这里的验证标记，尤其不要把 5 项源码候选转写为已运行确认的问题。

## 参考依据

- 本地 Skill：[主文件](/Users/acerola/.agents/skills/mac-arsed-mac-app/SKILL.md)、[行为规则](/Users/acerola/.agents/skills/mac-arsed-mac-app/reference/detailed-rules.md)、[验证方法](/Users/acerola/.agents/skills/mac-arsed-mac-app/reference/review-and-qa.md)。社区经验作为审查视角，未把 Skill 中涉及未来会议的示例当作 API 事实。
- Apple：[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)、[The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Settings](https://developer.apple.com/design/human-interface-guidelines/settings)、[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)。本轮查阅了官方网页及可用的官方 Markdown 版本。
- Apple API：[标签配对](https://developer.apple.com/documentation/swiftui/view/accessibilitylabeledpair%28role%3Aid%3Ain%3A%29)、[expandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate)；系统惯例：[Control-click](https://support.apple.com/en-gb/guide/mac-help/mh35853/mac)。

交付范围：仅本审查报告；源码、资源及项目配置未修改，未提交代码。
