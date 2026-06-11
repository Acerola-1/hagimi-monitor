## 1. GPU 温度暴露

- [x] 1.1 修改 `GPUSampler.sample()`，将 `reading.temperature` 加入 `metrics` 数组
- [x] 1.2 格式化温度值为 `"XX°C"` 格式
- [x] 1.3 在 `MonitorKind.gpu.availableMetrics` 中新增 `"温度"` 选项（`isDefault: false`）

## 2. CPU 温度采集（SMC 方案）

- [x] 2.1 新增 `SMC.swift`，实现 SMC 通信层（参考 `docs/stats/SMC/smc.swift`）
- [x] 2.2 定义 Apple Silicon CPU 温度 SMC 密钥列表：`Tp09`, `Tp0T`, `Tp01`, `Tp05`, `Tp0D`, `Tp0H`, `Tp0L`, `Tp0P`, `Tp0X`, `Tp0b`
- [x] 2.3 实现 `readSMCTemperature()`：尝试读取多个密钥，取可用值的平均值
- [x] 2.4 在 `CPUSampler.sample()` 中调用 SMC 读取，将温度加入 `metrics` 数组
- [x] 2.5 在 `MonitorKind.cpu.availableMetrics` 中新增 `"温度"` 选项（`isDefault: false`）

**方案说明：** 采用 SMC 读取而非 HID/IOReport。SMC 用户态即可访问、参考代码完整（`docs/stats/SMC/smc.swift`），HID 需 Objective-C 桥接、IOReport 读取的是功耗非温度。

## 3. 设置与面板

- [ ] 3.1 验证 CPU/GPU 设置页面中「温度」显示为可选、默认不勾选
- [ ] 3.2 验证勾选后主面板展开区域显示温度
- [ ] 3.3 验证取消勾选后温度不显示
- [ ] 3.4 验证最多4项限制对温度选项生效

## 4. 构建与测试

- [x] 4.1 构建项目，确认无编译错误
- [ ] 4.2 运行应用，验证 GPU 温度显示（如果硬件支持）
- [ ] 4.3 运行应用，验证 CPU 温度显示
- [ ] 4.4 验证 SMC 读取失败时返回 `"--"`
