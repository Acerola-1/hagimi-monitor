## 1. 数据模型

- [x] 1.1 在 `MonitorModels.swift` 中定义 `HaloRingSource` 枚举（combined / cpu / gpu / memory），含中文 title 属性，默认 combined
- [x] 1.2 在 `MonitorModule` 上新增可选 `pressure: MemoryPressureLevel?` 属性，仅内存模块使用
- [x] 1.3 将 `MemorySampler` 中的 `MemoryPressureState` 提升为模块级 `MemoryPressureLevel` 枚举（normal / warning / critical / unknown），采样时赋值到 `MonitorModule.pressure`

## 2. 设置持久化

- [x] 2.1 在 `MonitorSettings` 中新增 `ringSource: HaloRingSource` 属性，从 UserDefaults 初始化，默认 combined
- [x] 2.2 新增 `Keys.ringSource` 常量，绑定 `$ringSource` 持久化到 UserDefaults

## 3. 数据流改造

- [x] 3.1 修改 `MonitorStore.combinedComputeLoad`：根据 `settings.ringSource` 选择对应模块的 value（combined 仍用 cpu*0.6+gpu*0.4）
- [x] 3.2 在 `MonitorStore` 新增计算属性 `haloRingLoadLevel`：综合/CPU/GPU 按 load 阈值推断，Memory 模块从 `pressure` 属性映射
- [x] 3.3 修改 `HagimiMonitorApp` 传给 `MenuBarComputeRingIcon.image()` 的参数，新增 `loadLevel` 参数

## 4. 圆环绘制改造

- [x] 4.1 修改 `MenuBarComputeRingIcon.image()` 新增 `loadLevel: MenuBarComputeLoadLevel` 参数
- [x] 4.2 修改 `MenuBarComputeRingImageStyle`：`loadLevel` 由外部传入而非内部从 load 推断

## 5. 设置 UI

- [x] 5.1 在 `SettingsView` 常规设置中新增"负载环" section，含"监测项目" Picker，绑定 `$settings.ringSource`

## 6. 验证

- [x] 6.1 构建并运行，验证四种数据源切换圆环弧度和颜色正确
- [x] 6.2 验证设置持久化，重启后保持选择