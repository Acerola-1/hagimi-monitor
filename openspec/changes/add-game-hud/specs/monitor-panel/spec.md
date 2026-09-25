# monitor-panel Delta for game-hud

## ADDED Requirements

### Requirement: Game HUD 工具区开关
主面板工具区 SHALL 新增 Game HUD 快速开关，作为工具条目的一个 case 注册；该开关 SHALL NOT 改变既有监控模块的布局与规则。

#### Scenario: 工具条目登记
- **WHEN** 实现者新增 Game HUD 工具条目
- **THEN** SHALL 在既有工具条目枚举中补充 case 与其存储标识、标题 key、图标
- **AND** SHALL 按既有约定登记一次性迁移，令存量用户的已启用工具集合补上该条目；用户手动关过的条目不复活

#### Scenario: 按钮显示
- **WHEN** 工具区渲染
- **THEN** 显示 Game HUD 开关按钮
- **AND** 图标语义与 Game HUD 用法一致

#### Scenario: 按钮状态
- **WHEN** Game HUD 总开关启用
- **THEN** 按钮显示激活态；关闭时显示非激活态

#### Scenario: 按钮切换行为
- **WHEN** 用户点击该按钮
- **THEN** 切换与设置页相同的总开关
- **AND** 不打开设置窗口
- **AND** 完整配置仍通过设置窗口进入

#### Scenario: 状态反馈
- **WHEN** 用户点击该按钮后
- **THEN** 显示简短状态提示并在数秒后自动消失
- **AND** 提示文本通过 `String(localized:)` 翻译

### Requirement: Game HUD 工具区文案本地化
工具区 Game HUD 相关文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings` 并补齐现有中英翻译。

#### Scenario: 状态提示翻译
- **WHEN** 系统语言为英文
- **THEN** 启用与禁用状态提示显示对应英文
