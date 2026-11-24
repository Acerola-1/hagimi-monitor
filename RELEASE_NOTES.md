## 更新内容

感谢 @xyy386 提供 AirPods 实机验证和修复方案（#150）。

### 修复

- 修复同一副 AirPods 在蓝牙设备列表中重复显示、设备数偏高的问题，保留自定义名称以及左右耳、充电盒分别上报的电量（#147）。
- 改用 M2 系列对应的 CPU 温度传感器，过滤空闲时的异常低值，避免平均温度被拉低（#149）。
- 更新应用后自动清除旧版本遗留的更新提示（#143）。

### 优化与体验

- 改善音量与亮度浮层的玻璃效果。连续调节亮度时，滑条跟随按键变化，百分比和尼特读数在背光稳定后同步显示。

### 目前已知的问题

#### 未修复

- Mac mini 能耗（#106）与 MacBook Air M4 充电功率（#86）仍待受影响设备验证。
- 部分用户反馈开启代理 TUN 模式后网络显示未连接（#98）。

#### 正在修复

- Apple Watch 可以识别连接，电量读数仍待解决（#131）。

### English

- Fixed duplicate AirPods entries and inflated device counts while preserving the custom name and battery levels for each earbud and the case (#147). Thanks to @xyy386 for the fix and hardware verification (#150).
- Updated CPU temperature sensor selection on M2 Macs and filtered invalid idle readings out of the average (#149).
- Cleared stale update prompts after installing an update (#143).
- Refined the volume and brightness overlay. When brightness keys are pressed repeatedly, the slider follows the input and the percentage and nits appear together once the backlight settles.

Known issues include Mac mini power consumption (#106), MacBook Air M4 charging power (#86), network status with TUN mode (#98), and Apple Watch battery readings (#131).

