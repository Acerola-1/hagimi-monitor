## 更新内容

### 中文

感谢 @kuaoaoaoao 提供设备协助验证，多风扇与 AirPods Pro 的显示改进得以落地。本次更新聚焦风扇与蓝牙明细的呈现，并让主行图表样式可按模块选择。

#### 修复

- 蓝牙：设备类型识别补齐电脑、手机、平板与手表；AirPods 改用左耳 / 右耳 / 充电仓的分部电量，已有分部电量时不再重复显示耳机总电量，单部件耳机只显示一项；未上报的部件保留破折号与空轨道，不把缺失读成 0%。
- 风扇：实测转速为 0 时不再判定为故障，改显示中性的「停转」，也不再触发故障与恢复通知；只有读数超出传感器上报范围才提示异常。

#### 优化与体验

- 磁盘主行保留容量占比，右侧改为读取 / 写入速率读数，与网络、电源行头共用同一套标签浅底；单项速率缺失显示缺失符号，两项都不可用时显示真实可用容量。
- CPU、GPU、内存与风扇的主行图表可在「柱状图 / 折线图」之间按模块单独选择，已有用户沿用原来的折线图。
- 风扇明细改为分组网格：多个风扇按两列排布，数量为奇数时末项占满整行；风扇名称（左侧风扇 / 右侧风扇 / 风扇 #N）随界面语言显示。
- 普通蓝牙设备（鼠标、键盘、手表等）继续显示真实总电量，未上报电量时保持破折号占位。
- 网络与电源的成对行头读数改用同一套组件与几何，收起、展开与设置页预览保持一致。
- 底部监视器、工具与设置按钮的悬浮高亮改为只随鼠标悬浮淡入淡出，按下与松开不再额外改变颜色或整体透明度。

#### 目前已知的问题

以下问题本版尚未修复，仍在跟进：

- Apple Watch 无法正常显示电量余量（#131 · 修复中）：已能读取连接数据，但取不到准确的电量读数。
- Mac mini 无法正常显示能耗（#106 · 待解决）：手头没有对应设备，暂时无法验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98 · 未复现）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86 · 待解决）：手头没有对应设备，暂时无法验证。

### English

Thanks to @kuaoaoaoao for helping verify with an extra device — the fan and AirPods Pro display improvements are in. This release focuses on how fan and Bluetooth details are presented, and lets each module choose its own main-row chart style.

#### Fixes

- Bluetooth: device type detection now covers computers, phones, tablets, and watches. AirPods battery is split into Left / Right / Case; the headset total is no longer repeated when per-part levels exist, single-part headsets show one item, and parts with no reading keep a dash and an empty track instead of reading as 0%.
- Fans: an actual 0 RPM is no longer treated as a fault. It now reads as a neutral "Stopped" and no longer sends fault or recovery notifications; only a reading outside the sensor's reported range is flagged as unusual.

#### Improvements

- The storage row keeps its capacity share and now shows read/write rates on the right, sharing the same labeled pill as the network and power rows. A single missing rate shows the missing symbol, and when both are missing the row falls back to the real free capacity.
- The main-row chart for CPU, GPU, Memory, and Fans can be set to Bars or Line per module; existing users keep the line chart they already had.
- Fan details use a grouped grid: multiple fans in two columns, with the last item filling the row on an odd count. Fan names (Left Fan / Right Fan / Fan #N) follow the interface language.
- Ordinary Bluetooth devices (mice, keyboards, watches) still show their real total battery, and keep a dash when nothing is reported.
- Network and power paired header readings now share one component and geometry, so collapsed, expanded, and Settings preview stay in agreement.
- The hover highlight on the bottom monitor, tools, and settings buttons now fades only with hover; pressing and releasing no longer change the color or overall opacity.

#### Known Issues

The following are still open in this release:

- Apple Watch does not show the correct battery level (#131 · in progress): the connection data can be read, but not an accurate battery level.
- Mac mini does not show power consumption (#106 · open): no device available for verification yet.
- Network shows as disconnected after a proxy app enables TUN mode (#98 · not reproduced): enabling TUN mode locally does not trigger it.
- MacBook Air M4 does not show charging power (#86 · open): no device available for verification yet.

