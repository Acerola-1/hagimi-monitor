## 1. 数据模型层

- [x] 1.1 扩充 `MonitorKind.availableMetrics`：CPU（系统/用户/闲置/启动时间）、GPU（GPU内存/已分配/渲染/分块）、内存（已用/压力/交换已用/总量）、存储（已用/可用/总量）、网络（IP 地址/上传/下载）、电池（充电功率/健康度/循环数/温度）
- [x] 1.2 修改 `MonitorSettings.defaultMetricIds` 返回所有 `availableMetrics` 的 id（默认全选）
- [x] 1.3 验证各 Sampler 返回的 `MonitorMetric.name` 与 `availableMetrics` 的 `id` 完全匹配

## 2. 设置页面层

- [x] 2.1 确认 `ModuleSettingsView` 的「检测项目」列表能正确显示扩充后的多选项
- [x] 2.2 确认最多4项限制和重置默认值按钮工作正常

## 3. 主面板视图层

- [x] 3.1 修改 `MetricGlassRow` 的展开内容：根据 `settings.enabledMetrics` 过滤 `details`，仅显示勾选的指标
- [x] 3.2 修改 `NetworkGlassRow` 的展开内容：根据 `settings.enabledMetrics` 过滤网络指标
- [x] 3.3 修改 `BatteryGlassRow` 的展开内容：根据 `settings.enabledMetrics` 过滤电池指标，保留无外接电源时隐藏「充电功率」的现有逻辑
- [x] 3.4 验证存储模块的 `StorageVolumeDetailList` 不受指标过滤影响（存储展开内容特殊）

## 4. 验证

- [x] 4.1 构建项目，确认无编译错误
- [ ] 4.2 运行应用，验证各模块设置页面的「检测项目」显示正确多选项且默认全勾选
- [ ] 4.3 验证取消勾选后主面板展开区域仅显示选中指标
- [ ] 4.4 验证重置默认值按钮恢复全选状态
