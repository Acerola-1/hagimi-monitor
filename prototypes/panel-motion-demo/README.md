# CPU 原版组件 · 新运动 Demo

本轮把 CPU 内部内容接回正式版组件：行头和趋势图、核心圆环与 P/E 分组、指标网格、温度/热压力、启动时间，以及带图标的五行进程排名。数据通过原有 `MonitorStore` 采样通道实时更新。CPU 指标排列和勾选项从当前安装版只读导入到 Demo 独立的设置域。

运行产物：`tmp/panel-motion-demo/HagimiCPUNativeDemo.app`。打开后使用控制窗的“展开 CPU”“连续反转”“深色外观”，或点击 CPU 行头。关闭时使用“退出 Demo”。两套应用可以同时运行。

## 范围与实现

- `NativeCPUMotionDemo.swift` 负责窗口、材质和统一图层运动；`install_native_cpu.py` 在隔离的源码副本中抽出原有 CPU 渲染组件并接入 Demo。正式源码和 `/Applications` 安装版未替换，未创建 OpenSpec。
- 保留此前认可的临界阻尼运动：窗口尺寸固定，CPU 揭示、下方卡片、按钮、外框描边和阴影同步更新，中途反转保留速度。普通运行没有常驻逐帧主线程动画回调。
- 此次还原重点是 CPU 内部布局。顶部总标题、面板底座仍由原型宿主提供；GPU/内存只展示行头，底部入口仅作布局参照。拖动、封顶滚动、其他模块明细与完整辅助功能尚未接入，不能作为生产版本替换。
- 构建采用独立 Bundle ID；只采样 CPU、GPU、内存和 CPU 进程榜。Demo 不启动统计记录、蓝牙或风扇服务。未修改安装版的配置。

## 已完成的验证

两渠道 Release 构建通过。真实组件版在普通负载和 CPU/GPU 同时压力下分别完成 24 次展开/收起（含快速反转），过程中保持实时更新。最后同步用户指标排列后，已实机检查浅色、深色和连续反转。

`native-final-light.png`、`native-final-dark.png` 及 `native-final-reverse.mp4` 位于 `tmp/panel-motion-demo/`，保留周围真实的白色页面背景。此前组件版压力录屏为 `native-cpu-dark-busy.mp4`。

这些检查验证当前 CPU 原型的内容与运动方向；并未证明完整应用的性能收益，也未完成所有背景、所有硬件或完整无障碍验收。实时 CPU 组件会随数据重新布局，不能套用下面静态原型的布局次数和 CPU 数字。

## 在隔离副本中重新构建

最终验证源码保存在 `tmp/native-cpu-checkout/`。更新原型时，运行：

```bash
python3 prototypes/panel-motion-demo/install_native_cpu.py tmp/native-cpu-checkout
```

然后在该隔离副本使用 `HagimiMonitorDirect` Release scheme 构建，并将 `PRODUCT_BUNDLE_IDENTIFIER` 设为 `local.hagimi.cpu-native-demo`；App Store scheme 构建使用 `local.hagimi.cpu-native-demo.store`。不要把原型安装脚本指向正式工作区。应用启动会依据独立标识进入 Demo。

---

# 历史：快照动画原型

以下记录针对 `HagimiMotionDemo.app`，用于保留此前的方向实验及证据，不代表当前实时 CPU 页面。

独立的原生 macOS 动画原型。点击 CPU 卡片或按空格展开/收起；控制窗可播放往返、连续反转，并切换面板深色外观。退出按钮关闭整个 Demo。

运行产物：`tmp/panel-motion-demo/HagimiMotionDemo.app`。重新构建：从仓库根目录执行 `bash prototypes/panel-motion-demo/build.sh`。

内容按完整尺寸布局，窗口在演示期间保持固定尺寸；原生图层统一裁剪 CPU 明细、移动后续卡片与底部按钮，并改变可见外框高度。采用较收敛的临界阻尼弹簧，中途反转保留当前速度。普通运行没有逐帧主线程驱动；系统开启减弱动态效果时立即切换。

## 范围

- 数值与前三个进程来自之前保存的实际监控快照，不是实时监测。
- 仅 CPU 展开是交互；底部功能按钮是运动参照，不接入实际功能。
- 构建时复用正式版 `MonitorPalette.swift` 和 `Constants.swift`，恢复行卡 `.menu / .withinWindow` 材质、指标内衬、核心圆环与明暗文字配色。外框描边和阴影随同一弹簧轨迹更新。未修改正式面板或创建 OpenSpec。
- 固定透明窗口的输入区域、完整实时内容、封顶滚动、拖动和所有模块尚未实现。它用于判断动画方向，不能作为生产替换版本。

## 本版实测（包含周围真实背景）

浅色正常负载、深色 CPU/GPU 同时压力各完成 24 次切换（包含快速反转）。两组录屏包含面板周围的真实 ChatGPT 白色页面背景，已检查展开终态的文字、圆环、指标内衬、行卡和外框分离度；不能用此前仅录目标窗口的画面替代背景对照。

自动验收额外开启 60 Hz 主线程图层采样，普通演示不启用。两轮采集 1250 / 1249 个图层状态，外框、CPU 揭示、GPU、底部按钮、描边和阴影的相对误差最大约 0.00000000000017 pt。它证明所采样的几何一致，不代表显示器最终帧率。主明细宿主布局累计为 2 / 3 次，CPU 头部因每次切换箭头会额外布局。

Demo 的进程 CPU 中位数为 1.9% / 0.8%；深色压力轮的压力进程 CPU 中位数约 741%。这些只描述静态小原型，不与完整安装版作性能收益比较。

构建和静态界面审计通过。尚未进行完整 VoiceOver、拖动或滚动回归，也未验证所有桌面背景组合。

带背景的录像为 `tmp/panel-motion-demo/contrast-light.mp4` 和 `contrast-dark.mp4`，录屏预览为 `contrast-preview.mp4`；画面对照为 `contrast-comparison.png`，采样汇总为 `contrast-verification.json`。早期录像与统计仍保留为历史资料。
