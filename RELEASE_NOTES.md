## 更新内容

感谢 @xyy386 为 CPU 逐核圆环补充占用率悬停提示（#145）。

### 新功能

- 鼠标悬停 CPU 逐核圆环时，可查看该核心当前的整数占用率；面板与设置页预览均支持。

### 优化与体验

- 显示器展开区按设备分节，增加设备之间的分隔线，统一名称与参数摘要的对齐和层级，让多屏信息更清楚。
- 统一未连接显示器的条目样式，只保留设备名称与原有操作入口。
- 移除显示器亮度、音量和对比度滑轨的密集刻线，仍按整数百分比调节。
- 移除显示器不支持控制时的重复提示，保留禁用样式表示不可用状态。
- 补齐电源、显示器主行与展开内容之间的分隔线，电源设置预览同步保持一致。
- 电源模块的「拓扑」分页更名为「功耗」，让分项功耗信息更容易理解。

### 目前已知的问题

#### 未修复

- Mac mini 无法正常显示能耗（#106）：仍待对应设备验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86）：仍待受影响设备验证。

#### 正在修复

- Apple Watch 无法正常显示电量余量（#131）：已能读取连接数据，但取不到准确的电量读数。

### English

Thanks to @xyy386 for adding per-core CPU usage tooltips (#145).

- Hover over a CPU core ring to see its current usage as a whole-number percentage, in both the panel and Settings preview.
- Grouped display details into clearer device sections, with separators and consistent alignment for names and specifications.
- Unified disconnected-display rows, keeping only the device name and existing actions.
- Removed dense tick marks from display brightness, volume, and contrast sliders while preserving whole-percentage adjustments.
- Removed repetitive unsupported-control messages while retaining disabled styling for unavailable controls.
- Added separators between the main rows and expanded content for Power and Displays, with matching Power previews in Settings.
- Renamed the Power module's “Topology” tab to “Power” to make component power readings easier to find.

#### Known Issues

- Missing power-consumption readings on Mac mini still require verification on the affected hardware (#106).
- Network may appear disconnected when a proxy app enables TUN mode; not reproduced locally (#98).
- Missing charging-power readings on MacBook Air M4 still require verification on the affected hardware (#86).
- Apple Watch connections can be detected, but accurate battery readings remain unavailable (#131, in progress).

