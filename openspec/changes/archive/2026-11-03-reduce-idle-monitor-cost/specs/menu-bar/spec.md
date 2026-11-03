# menu-bar

## ADDED Requirements

### Requirement: Game HUD 徽章随显隐立即更新
直连版菜单栏图标上的 Game HUD 徽章 SHALL 在浮窗变为可见或隐藏的同一轮界面更新里改变，环形图标与指标文字两种显示模式 SHALL 一致。指标模式的重绘去重 SHALL 把 HUD 显隐纳入比较，不得因数值未变而跳过。徽章 SHALL NOT 等到下一次负载数值变化才更新。告警红点与 HUD 徽章同时存在时 SHALL 只绘制告警。App Store 版 SHALL 不显示该徽章。

#### Scenario: 浮窗出现时徽章点亮
- **WHEN** 直连版的 Game HUD 浮窗从隐藏变为可见，且菜单栏负载数值没有变化
- **THEN** 当前为环形或指标模式的菜单栏图标都出现 HUD 徽章

#### Scenario: 浮窗消失时徽章熄灭
- **WHEN** 直连版的 Game HUD 浮窗从可见变为隐藏，且菜单栏负载数值没有变化
- **THEN** 当前为环形或指标模式的菜单栏图标都去掉 HUD 徽章

#### Scenario: 告警优先
- **WHEN** 菜单栏同时存在告警红点与 Game HUD 运行状态
- **THEN** 状态项只绘制告警红点，不叠画 HUD 徽章

#### Scenario: 商店版没有徽章
- **WHEN** App Store 版运行
- **THEN** 状态项图标不绘制 HUD 徽章
