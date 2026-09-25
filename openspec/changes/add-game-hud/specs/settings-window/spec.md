# settings-window Delta for game-hud

## ADDED Requirements

### Requirement: Game HUD 设置页
设置窗口 SHALL 新增 Game HUD 设置页，并在侧栏「扩展」分组中提供入口；该页面 SHALL 不影响既有模块选择与菜单栏指标配置的规则。

#### Scenario: 侧栏入口
- **WHEN** 用户打开设置窗口
- **THEN** 侧栏在既有「扩展」分组中显示 Game HUD 条目
- **AND** 该条目 SHALL 作为新的 `SettingsRoute` case 注册，与既有分组内条目的组织方式一致

#### Scenario: 详情页设置组顺序
- **WHEN** 用户进入 Game HUD 设置页
- **THEN** 页面按以下顺序显示设置组：总开关、监控项目、应用名单、悬浮层布局
- **AND** 官网渠道在末尾追加官方 HUD 辅助说明组

#### Scenario: 总开关
- **WHEN** 详情页渲染总开关
- **THEN** 开关状态与设置在设置页与主面板工具区之间保持同源
- **AND** 关闭后悬浮层隐藏

#### Scenario: 监控项目勾选列表
- **WHEN** 用户查看监控项目设置组
- **THEN** 列表只包含本渠道与当前硬件可用的项目
- **AND** 沙盒渠道不出现 CPU 温度与分项功耗，且不以灰显或占位形式出现
- **AND** 勾选状态持久化

#### Scenario: 应用名单
- **WHEN** 用户查看应用名单设置组
- **THEN** 可查看自动识别候选并排除其中项目
- **AND** 可手动添加与移除应用
- **AND** 候选名单的展示 SHALL NOT 依赖每次进入页面时重新全量枚举系统中所有已安装应用

#### Scenario: 悬浮层布局配置
- **WHEN** 用户查看布局配置
- **THEN** 可选择四角之一并调整水平与垂直偏移量
- **AND** 配置持久化并对所有游戏生效

#### Scenario: 沙盒渠道不显示官方 HUD 辅助
- **WHEN** App Store 渠道渲染 Game HUD 设置页
- **THEN** 不显示官方 HUD 辅助设置组
- **AND** 其余设置组正常显示

### Requirement: Game HUD 设置文案本地化
Game HUD 设置页的所有用户可见文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings` 并补齐现有中英翻译。

#### Scenario: 设置组标题翻译
- **WHEN** 系统语言为英文
- **THEN** 设置组标题、开关标签、按钮与说明文本显示对应英文
- **AND** 专有名词（如 Metal）不强行翻译

#### Scenario: 指标名称复用既有翻译
- **WHEN** 设置页显示监控项目名称
- **THEN** 已存在的指标 SHALL 复用既有本地化 key，不新增同义 key
