## MODIFIED Requirements

### Requirement: 菜单栏面板文案本地化
菜单栏下拉面板中的所有文案 SHALL 支持本地化，包括面板标题、右键菜单和钉住/关闭操作。

#### Scenario: 面板按钮和标题
- **WHEN** 用户打开菜单栏面板
- **THEN** "活动监视器" 显示为 "Activity Monitor" / "アクティビティモニタ"
- **AND** "设置" 显示为 "Settings" / "設定"
- **AND** "SYSTEM · LIVE" 通过 `String(localized:)` 引用

#### Scenario: 面板钉住和关闭操作
- **WHEN** 用户右键点击面板标题栏
- **THEN** "钉住面板" 显示为 "Pin Panel" / "パネルをピン留め"
- **AND** "取消钉住" 显示为 "Unpin Panel" / "ピン留めを解除"
- **AND** "关闭面板" 显示为 "Close Panel" / "パネルを閉じる"
