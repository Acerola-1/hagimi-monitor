## ADDED Requirements

### Requirement: 面板可见性采用引用计数判定

`MonitorStore` 的可见性状态（`isPanelVisible`）SHALL 反映「是否存在任一可见面板」，而非单一面板的显隐。当菜单栏面板与钉住面板中任意一个可见时，系统 SHALL 判定为可见并保持进程采样与显示器 DDC 轮询活跃；仅当所有面板均不可见时，才判定为不可见并暂停这些采样。

#### Scenario: 单一面板显示时保持采样
- **WHEN** 仅有一个面板（菜单栏面板或钉住面板）可见
- **THEN** `isPanelVisible` 为真，进程采样定时器保持运行

#### Scenario: 关闭其中一个面板仍有另一面板可见
- **WHEN** 两个面板同时可见，随后其中一个被关闭
- **THEN** `isPanelVisible` 仍为真，进程采样不被暂停

#### Scenario: 所有面板关闭
- **WHEN** 所有面板均被关闭
- **THEN** `isPanelVisible` 为假，进程采样定时器暂停
