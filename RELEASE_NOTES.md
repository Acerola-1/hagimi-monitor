## 更新内容

### 新功能

- 开启「媒体键接管」后，调节亮度、音量会新增浮层反馈：在菜单栏附近实时显示当前档位与刻度，亮度在可用时一并显示面板物理亮度（尼特）；指针移入后可直接拖动滑条微调，停止操作约 1.5 秒后自动淡出，主面板展开期间不弹出。
- 媒体键跟随实际设备：亮度键作用于鼠标所在的可控屏幕，内建屏也支持平滑调光；音量键跟随系统当前音频输出。目标无法唯一确定时，仍交还系统处理。

### 修复

- 稳定 CPU 逐核圆环的悬停读数：改为逐环跟踪指针，占用率不再随刷新闪烁或落到相邻核心，并避免与长按拖动排序的提示互相干扰。

### 优化与体验

- 蓝牙主行按明细顺序显示设备类型图标；展开区按设备实际上报的电量部件（整机 / 左耳、右耳、充电盒）排布，不再依据名称或广播来源猜测，同一连接内偶尔缺少分部读数时布局也保持稳定。
- 蓝牙已开启但没有连接设备时，明确显示「未连接设备」，不再显示为「0 台设备」。
- 媒体键浮层的读数气泡随刻度平滑移动、箭头始终指向填充边界；玻璃材质改用更清透的系统材质，并收敛上下沿高光。

### 目前已知的问题

#### 未修复

- Mac mini 无法正常显示能耗（#106）：仍待对应设备验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86）：仍待受影响设备验证。

#### 正在修复

- Apple Watch 无法正常显示电量余量（#131）：已能读取连接数据，但取不到准确的电量读数。

### English

This release adds an on-screen readout for media-key adjustments, along with refinements to Bluetooth and per-core CPU details.

- With Media Key Takeover enabled, brightness and volume adjustments now show a floating readout near the menu bar with the current level and step bar. Brightness also shows physical panel luminance (nits) when available. Move the pointer in to drag the slider directly; it fades out after about 1.5 seconds of inactivity and stays hidden while the main panel is open.
- Media keys now follow the active device: brightness keys target the controllable screen under the pointer (including smooth dimming on the built-in display), and volume keys follow the current audio output. When no unique target can be determined, the keys are handed back to macOS.
- Stabilized per-core CPU usage tooltips: pointer tracking is now per ring, so the reading no longer flickers with refreshes or lands on a neighboring core, and it no longer competes with the long-press reorder hint.
- The Bluetooth row now shows device-type icons in detail order, and the expanded list follows the battery parts each device actually reports (single / left, right, case) instead of inferring them from the name or broadcast source. The layout also stays stable when a sample briefly omits part readings.
- When Bluetooth is on but no device is connected, the row now reads “No devices connected” instead of “0 devices”.
- The media-key readout bubble now moves smoothly with the level and its arrow stays aligned to the fill edge; the glass uses a clearer system material with softer top and bottom highlights.

#### Known Issues

- Missing power-consumption readings on Mac mini still require verification on the affected hardware (#106).
- Network may appear disconnected when a proxy app enables TUN mode; not reproduced locally (#98).
- Missing charging-power readings on MacBook Air M4 remain unverified on the affected hardware (#86).
- Apple Watch connections can be detected, but accurate battery readings remain unavailable (#131, in progress).

