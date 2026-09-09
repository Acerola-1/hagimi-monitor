## Context

动机与范围见 [proposal.md](proposal.md)。行为契约见 [动画规格](specs/panel-animation-consistency/spec.md) 与 [面板规格](specs/fluid-menu-bar-panel/spec.md)。本变更跨越 SwiftUI 布局、AppKit 窗口、滚动和性能验证，需要设计文档。

当前每个面板有一个 `NSHostingView`，根包含面板 Header、ScrollView、卡片 VStack、显示器区和底部按钮。`CollapsibleDetail` 通过隐式弹簧修改 `.frame(height:)`；`PanelExpansionDriver` 预测目标高度，窗口控制器再运行 `PanelWindowSpring`，自然尺寸反馈与结束校准可能继续重定向窗口。`body` 少量求值不能证明 AttributeGraph 或内容布局只运行一次。

材质以现有实现为基线：外层保留 `CompatibleGlassContainer`；当前行级 `CompatibleGlassEffect` 在支持系统上都使用 `.menu / .withinWindow`，ID modifier 是透传；窗口底材质、填充与裁剪也共同影响最终外观。保留容器名称而替换这些材质，不能视为视觉等价。

旧 `refactor-panel-expansion-compositor` 中的逐卡 hosting 岛、AppKit 硬裁剪、10pt 底边距和固定 Footer 不属于本变更。旧计划不作为本计划的依赖，也不与本计划并行实施。

## Goals / Non-Goals

**Goals:**

- 将内容测量与当前可见几何分开，使昂贵的行头/明细叶子内容收到稳定的宽高提议。
- 将动画成本集中在有限数量的外壳尺寸、裁剪与定位上；通过仪器验证减少递归布局，接受轻量布局每帧执行。
- 维持现有单宿主材质上下文，以真实窗口承载当前可见边界、阴影和事件区域。
- 使用同一运动时间和版本化几何求解窗口、卡片、主体视口与自动滚动，消除预测高度与末帧补调的正常路径。
- 在生产迁移前证明视觉等价、布局隔离收益与实际呈现同步。

**Non-Goals:**

- 不追求“SwiftUI 任意内部布局函数调用次数为零”，也不通过私有层级访问、CALayer 重挂接或逐卡 hosting 岛达成隔离。
- 不使用假透明大窗口、位图快照、内容缩放或材质栅格化代替实时面板。
- 不改变模块内容、配色、字号、指标格归属、底部按钮滚动语义或渠道能力。
- 不声称公共 API 能保证跨 WindowServer 原子提交，或在任意系统负载下保证每个 VSync 都有新帧。
- 本次规划不实施代码、不创建实验分支、不构建或重启应用。

## Decisions

### 1. 单宿主内建立稳定内容提议的布局边界

```text
NSPanel：真实 frame 与系统阴影
└─ 现有外层实时材质 / continuous 20pt 裁剪
   └─ 单个 NSHostingView
      └─ CompatibleGlassContainer
         └─ PanelChromeLayout：读取已知 Header / viewport 几何
            ├─ 原有 Header
            └─ 原有 ScrollView
               └─ AccordionLayout：读取卡片与按钮位置
                  ├─ CardShell + 原有行级材质
                  │  ├─ 原有 Header：稳定自然尺寸
                  │  └─ DetailViewportLayout：当前揭示高度
                  │     └─ 原有 Detail：稳定自然尺寸
                  ├─ 其他卡片 / 嵌套显示器布局
                  └─ 原有底部操作按钮
```

`AccordionLayout.sizeThatFits` 返回已求出的主体文档尺寸，`placeSubviews` 读取已知位置，对每个卡片传递相同几何版本中的固定自然尺寸提议。`DetailViewportLayout` 对外返回揭示高度，对内始终提议完整自然尺寸。卡片外壳根据当前可见高度绘制材质；行头与明细内容的字体和内部 padding 不变。

根也建立同样的边界：保留真实窗口大小的 host，逐帧变化的 host 高度只影响已知尺寸的面板外壳，不通过旧 `FluidPanelSizeReader.fixedSize()` 重新协商整棵树。保留 `sizingOptions = []` 本身不足以解决此问题。

动画状态仅由薄的表现层观察。指标内容继续经现有数据发布与刷新门控更新，几何不变时不因帧状态重建整段指标数据或读取全部 store。`Equatable` 如被采用，其输入必须完整覆盖真实内容与依赖，不能仅按卡片 ID 判等掩盖陈旧数据。

替代方案判断：`layoutPriority` 只影响分配顺序；单独 `.fixedSize()`、`.equatable()` 不构成布局隔离；自定义 Layout 内每帧重新遍历 `sizeThatFits` 仍会保留热点。`offset` 可辅助定位，但独自使用不能统一高度、滚动与命中区域。原生布局缓存是否阻断内部递归需要实测，未通过时不继续迁移，也不自动退回 hosting 岛方案。

### 2. 自然尺寸登记按版本冻结，身份不按数组偶然位置绑定

协调器维护三个小型数据层，优先复用现有 driver，避免引入通用布局引擎：

| 数据 | 必要字段 | 更新时机 |
| --- | --- | --- |
| GeometrySnapshot | revision、宽度、locale/字体环境、backingScale、有序稳定 ID、行头与明细自然高度、层级、Header/Footer 高度、屏幕约束 | 有效几何变化 |
| MotionState | 分区目标、起点、速度、开始时间、当前自动滚动状态 | 操作或合法重定向 |
| PanelFrame | revision、frameID、采样时间、可见卡片矩形、揭示范围、文档与视口高度、滚动偏移、窗口内容尺寸 | 每次运动采样 |

新几何测量以实际面板宽度减两侧留白为提议，包含已有内部 padding。缓存高度不绕过 `StaticMetricSizing` 的语言登记表，不新增运行时文本宽度判定。

按首次挂载、语言、宽度、字体环境、指标/进程行结构、设备集合、渠道控制结构等失效；遵守最坏值契约的普通读数变化只刷新值。测量附带 revision；旧版本迟到结果丢弃。同一版本准备齐全后一次发布，不能逐个回填活动帧。

首次未准备好时保留完整收起态，尺寸就绪后再开始动画。输入结构在运动期间改变时，保存当前几何和可见速度，提交新版本并重定向仍有效分区；如果自然尺寸变化导致归一化参数改变，使用 pt / pt·s⁻¹ 的可见量重基准。设备消失等改变可用性的事件同步隐藏失效内容并重新求解，不允许旧控件继续存在于事件树中。

折叠只是揭示状态变化，不销毁昂贵内容。面板隐藏时沿用现有资源回收机制，停止时钟并丢弃活动提交，防止迟到测量重新撑大已回收窗口。

### 3. 几何直接保留留白与圆角，裁剪只作用于明细视口

以面板内容坐标的左上角为原点，尺寸单位为 pt：

```text
cardWidth = panelWidth - 6 - 6
cardHeight[i] = headerHeight[i] + revealHeight[i]
cardTop[i + 1] = cardTop[i] + cardHeight[i] + 6
bodyHeight = 最后一个主体项目（包含底部按钮）的底缘
viewportHeight = min(bodyHeight, bodyViewportCap)
panelContentHeight = 8 + panelHeaderHeight + 4 + viewportHeight + 6
```

340pt 宽时卡片为 328pt；其他受支持宽度仍保留两侧各 6pt。屏幕安全余量是独立的窗口定位/封顶策略，不能加入底部 padding。当前高度上限换算中的额外缓冲需要在样机记录清楚，再按同一方程传给视口与窗口；不沿用两个分别推导且口径不同的 cap。

行头高度来自完整内容测量，约 34pt 而非硬编码 34。原有横向 10pt、纵向 8pt 内边距保留一次。明细视口原点为明细顶部，其裁剪完全在 SwiftUI 局部坐标执行；零揭示时高度与 opacity 均精确为 0。

现有 `.compatibleGlassEffect` 附于当前高度的 CardShell，实时材质与 continuous 14pt 圆角随当前外壳几何绘制。不从一张完整长卡片中部硬切其背景，避免底部圆角和材质边缘消失。外框继续使用现有 continuous 20pt 裁剪与原生窗口阴影。

骨架仅说明布局契约，测量准备、ID 匹配和事件门控由包装层提供：

```swift
struct DetailViewportLayout: Layout {
    let naturalSize: CGSize
    let revealHeight: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: naturalSize.width, height: revealHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: naturalSize.width,
                height: naturalSize.height
            )
        )
    }
}
```

该 viewport 包裹原有明细，再应用无抗锯齿的矩形裁剪、可见区域 contentShape、交互门控及辅助功能隐藏。行头是其兄弟节点，不在裁剪范围内。`clipped()` 不代表完整命中裁剪，按钮、滑杆、滚轮和键盘导航分别进行原生验证；开始收起前将明细焦点移至可见行头。

### 4. 一个运动协调器，窗口是派生几何

每个面板实例拥有私有 `PanelExpansionDriver`。操作入口保留 `store.beginExpansionAnimation()`，更新语义目标，并在统一时刻读取当前运动位置和速度。动画仅在活跃期间由所在屏幕的一个 CADisplayLink 驱动，使用绝对时间和 `targetTimestamp`，不按帧数或累积 dt 积分。

使用公开 `Spring(response: 0.32, dampingRatio: 0.82)` 查询位移和速度；也可复用现有闭式解，但必须用同参数样本对照，不能同时维护内容与窗口两条弹簧。重定向时从当前位置和速度接续。内部时间不倒退：事件到达时的重基准时间不早于最后提交的采样时间。

```swift
let elapsed = max(0, sampleTime - startTime)
let distance = target - start
let position = start + spring.value(
    target: distance, initialVelocity: startVelocity, time: elapsed
)
let velocity = spring.velocity(
    target: distance, initialVelocity: startVelocity, time: elapsed
)
```

窗口高度由同一帧的可见内容和视口求得，删除其独立轨迹。展开相关 opacity、chevron 与自动揭示也读取同一表现状态，避免遗留 `.animation` 在暂停或掉帧时继续独立推进；与展开无关的数值动画保持原有职责。

欠阻尼边界策略：自然展开高度不是硬上限，允许原弹簧的小幅过冲，内容仍保持自然尺寸，由实时背景承载额外高度；零揭示是硬下限，统一使用非负揭示高度后再派生全体几何。屏幕限制只钳制视口/真实窗口，不回写未封顶文档高度。解析状态保留用于有效的中途重定向，硬边界上的可见速度不能宣称全域 C1 连续。收敛同时检查位置误差和速度，最后一次提交使用精确目标；不能因“距目标很近”而在仍有明显速度时提前结束。零附近尾段须证明不会露出明细残帧。

收起轨迹按解析首次过零时间识别边界，不依赖某一显示回调恰好采到负相位。到达后，本次收起保持精确零揭示与零透明度，内部位置/速度继续衰减；再次展开若已进入零揭示保持态，则映射到可见位置 0、可见速度 0，从零加速，消除负相位等待和穿越边界时的速度突跃；尚未碰到边界的反转继续保留解析位置与速度。几何换版保留内部带符号点数和速度，父节点只累计孩子的可见高度。

最初保留现有采样刷新暂停，反复点击延长到实际收敛；不以固定 0.5s 后的测量覆盖运动状态。停止/隐藏/减少动态效果走同步路径并停止 display link。

### 5. 帧提交只有一个出口，实际呈现同步作为强制实验门槛

单次回调顺序为：采样所有轨迹 → 纯几何求解 → 应用一个带 frameID 的 `PanelFrame`。求解过程不读取 SwiftUI 的当前 fittingSize，不在 Layout 或 `animatableData` setter 中修改窗口。

首选帧提交适配：关闭隐式动画，在一个主线程更新中设置薄表现层状态，执行真实窗口 `setFrame(display: false, animate: false)`，再使 hosting 完成需要的布局。候选使用 `CATransaction.setDisableActions(true)`、无动画 SwiftUI Transaction 与 `layoutSubtreeIfNeeded()`，但不将任何一个视为显示屏同步 API。

`setFrame` 的 content/frame 换算复用两个控制器现有窗口样式；菜单栏锚点、横向屏幕夹取和钉住顶边规则由宿主适配提供。现有点击关闭、失焦关闭、hasShadow、显隐 alpha 动画及原生圆角事件语义保持。

通过带 frameID 的提交日志与单独录制的逐帧画面验证窗口边缘和卡片边缘。不得把“同回调内发出命令”当作“同屏幕帧呈现”的证据。`display: true/false` 的选择及布局触发顺序只允许在该小适配层对照，不用 async 延迟、独立弹簧、每帧强制 flush 或收尾校准掩盖相位差。

若同一 logical frame 无法在受测平台稳定呈现，样机门槛失败，生产迁移停止，保留基线并以证据修订此设计；不会自动放宽视觉规格或切换到已否定架构。

### 6. 嵌套展开与屏幕封顶共享同一几何模型

登记表按稳定 ID 保存层级，父节点保存自有静态内容，子节点各自保存内容尺寸与揭示状态。求解按层级合成已实现的子节点几何，再应用父视口，父节点不会同时累计“含孩子的自然高度”与“孩子增量”。外层关闭时子节点既不撑大顶层，也不暴露命中区域。

子列表通过 `PanelChildGroup` 登记左右/上下内衬及间距，子宽度逐层从父宽度扣除。显示器列表保留原有外侧 10pt、内部 28pt：子组相对 328pt 父卡片为 leading 38 / trailing 10，宽 280pt；Direct 组内图标 14pt 加间距 8pt，控制/档案叶子宽 258pt。Direct 列表顶部 9pt、组间 17pt、底部 9pt，包含 1pt 分隔线和原 8pt 间距。App Store 组间 9pt、底部 9pt。

控制/档案替换节点分别登记 `collapsedDetailHeight` 和完整 `detailHeight`，可见高度为 `base + (natural - base) × phase`，允许档案比控制区更矮；换版按带符号高度差映射位置与速度，父级只合成子级当前可见高度。父级收敛阈值使用合成高度，避免自有明细为零的容器过早停止。

固定提议约束施加在昂贵静态叶子内容上。含动态孩子的显示器容器本身仍属于轻量布局层；不能把它整体冻结后仍在内部运行旧高度动画。父子同次切换采用一批目标、一个采样和一次求解，尺寸版本改变时重基准实际可见几何。

Header 固定；底部按钮与卡片都属于 ScrollView 的文档。自动揭示目标按视觉顺序选最后一个新展开且有内容的节点，记录为稳定 ID。ScrollView 的自动偏移通过公开接口在无动画事务中应用同一帧求出的偏移，不再调用独立 spring；是否与窗口同帧仍属于提交样机的验收范围。

用户滚轮/触控板接管时，以当前可见偏移为基准结束自动滚动分量，清除旧的自动揭示意图，保留卡片轨迹。手势或惯性阶段内新点击展开则只登记新意图，到 idle 后按最新几何重新贴合；再次发起手势、关闭目标/其祖先或删除设备会取消该意图。嵌套目标使用主体坐标中的分区矩形。屏幕封顶和解封时，文档高、视口高与合法偏移从同一几何求解得到；溢出渐隐由真实溢出与偏移决定，不使用迟到的高度反馈触发闪烁。受测范围包括底部滚动位置收起、自动揭示中手动反向滚动、切屏和 backingScale 变化。

### 7. 原生样机同时证明性能、视觉和事件行为

该变更不改变交互设计，不需要先用 HTML 重做视觉。三卡片原生样机使用生产 Header、CPU 复杂明细、两张相邻卡片、原有底部按钮、完整玻璃层级和真实 NSPanel；HTML 无法验证 hosting、原生材质、阴影与 WindowServer 提交。

记录基线和候选的 OS、机器、屏幕刷新率/缩放、构建配置、渠道、模块内容、负载方法与原始输出路径。性能使用 Release、相同冻结的真实输入快照、至少 5 次预热后每组 20 次操作，并交替运行两路径减小热状态漂移；另行运行真实采样回归，快照夹具仅在测试路径使用。

动作组包括单行展开/收起、全量切换、100ms 间隔反转、封顶后展开、底部位置收起。至少在 60Hz 正常负载和可复现 CPU 负载下对照，高刷新率和低电量模式作为附加矩阵。负载由验证脚本记录工人数量、持续时间与实际 CPU 占用，清理仅针对其自建进程。

记录 `Measure`、`Solve`、`ApplyWindow`、`ApplyPresentation`、总主线程工作及帧间隔的 p50/p95/p99；统计 >16.7ms、>33.3ms、>40ms 间隔并关联 Time Profiler，区分系统调度延迟与应用自身阻塞。测量与录像分开运行。

进入生产迁移的门槛：

1. 340/328pt 宽度和 8/6/6pt 留白、6pt 行距、14/20pt 圆角满足规格；固定同一真实数据快照比较收起/展开端点，收起明细区域无任何像素污染，行头完整。材质因系统动态噪声不要求整窗位图逐像素相等，但几何边缘与内容布局必须一致。
2. 同一几何版本运动期间，自有内容自然尺寸测量次数不随帧数增长；同一叶子收到的提议不变；Instruments 不再出现展开关联的兄弟内容递归布局热点。轻量外壳的 `sizeThatFits` / `placeSubviews` 调用可存在。
3. 与相同条件基线相比，展开归因的递归布局耗时至少降低 50%，且不再出现可重复由该路径造成的 40–50ms 主线程阻塞。百分比是验收目标，不是当前实测结论；若基线捕获不到原问题，先完善复现，不能据此宣告通过。
4. 独立视觉捕获中，窗口边缘、卡片底缘和主体视口不存在可重复的一帧先后、两段跳变或末帧补调；应用 sampleID 一致只是必要条件。
5. 阴影、点外行为、部分揭示命中、键盘与辅助功能无回归；可见/隐藏内存对照没有额外多宿主或常驻渲染表面，隐藏与收敛后时钟为零。

## Risks / Trade-offs

- [Risk] 稳定提议仍可能被 SwiftUI 内部布局、材质或根尺寸变化牵动 → 样机同时埋点自有边界并用 Instruments 查看实际递归栈；未满足门槛时修订边界，不能仅凭代码结构宣告完成。
- [Risk] SwiftUI 状态与 NSWindow frame 的实际提交异步 → 将提交策略集中为小适配层，使用独立画面证据验证；不宣称 CATransaction 提供跨窗口原子性。
- [Risk] 零揭示和屏幕封顶是硬约束，不能与无界欠阻尼轨迹同时保持全域光滑 → 统一合法几何映射，保留原弹簧参数，单独测试边界反转与尾段残帧。
- [Risk] 自然尺寸缓存过期或冻结了真实内容 → 版本化完整失效键、稳定 ID、批量提交与迟到测量丢弃；用冷启动和设备变化验证实际内容及时性。
- [Risk] 原有玻璃 modifier 顺序或 padding 在包装时被改变 → 直接复用生产视图和材质，在迁移每类卡片后与固定数据基线对照。
- [Risk] 自动滚动通过 SwiftUI 公开接口仍存在延迟 → 在三卡片样机增加受限高度场景，作为同一个同步门槛验证，不将滚动问题留到全量迁移之后。
- [Risk] 常驻明细增加布局或内存开销 → 与当前已经常驻明细的基线对照，沿用隐藏资源回收；不另建永久测量树或截图缓存。

## Migration Plan

1. 明确选择本变更作为实施入口，创建 `codex/panel-expansion-single-host` 实验分支前检查当前工作区归属，记录现有视觉、布局栈与 Release 基线；不提交用户工作。
2. 实现版本化尺寸和纯运动/几何求解，建立有意义的边界与中断测试；仅连接三卡片实验入口。
3. 接入单宿主布局与帧提交、屏幕封顶和滚动，执行第 7 节全部样机门槛。失败则保留生产入口，记录证据并修订本设计。
4. 通过后逐类迁移通用指标、网络/电池、显示器及嵌套区，保持原内容组件和材质；每步构建、重启两个渠道供视觉检查。
5. 两面板接入同一实现但各自持有运动状态，验证隐藏恢复、拖动/钉住位置、主题/语言及设备变化；再移除旧预测、双弹簧与常规尾部补偿。
6. 运行 Direct scheme 测试、双渠道构建及完整矩阵，记录原始证据；仅在验收通过后移除实验切换入口并更新描述错误的实现注释与 AGENTS.md 动画说明。主规格由后续 OpenSpec 归档流程同步。

回退保留到第 6 步完成前：切回原生产视图与控制器尺寸路径即可，禁止将候选尺寸缓存或部分 driver 状态混入基线。计划完成不等于实施完成，tasks 在对应代码和证据完成前保持未勾选。

参考公开接口：[SwiftUI Layout](https://developer.apple.com/documentation/swiftui/layout)、[SwiftUI Spring](https://developer.apple.com/documentation/SwiftUI/Spring)。这些接口支持本设计所用的提议、定位及弹簧采样，但不承诺上述性能收益或实际屏幕原子提交。
