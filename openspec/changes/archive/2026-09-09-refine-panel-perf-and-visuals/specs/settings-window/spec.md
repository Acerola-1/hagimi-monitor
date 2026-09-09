## ADDED Requirements

### Requirement: 常规设置页外观组 Liquid Glass 开关
在 macOS 26 及以上系统，「设置 → 常规 → 外观」组 SHALL 包含一个名为「Liquid Glass」的切换开关，提供副标题说明，并与 `settings.liquidGlassEnabled` 持久化绑定。

#### Scenario: 外观组呈现 Liquid Glass 开关
- **WHEN** 在 macOS 26+ 系统打开「设置 → 常规」
- **THEN** 外观设置组在配色选项后呈现 Liquid Glass 开关
- **AND** 开关默认处于关闭状态，并附带简要提示说明

#### Scenario: 旧系统自动隐藏开关
- **WHEN** 在 macOS 15 系统上打开设置
- **THEN** Liquid Glass 开关不渲染，保持经典毛玻璃表现
