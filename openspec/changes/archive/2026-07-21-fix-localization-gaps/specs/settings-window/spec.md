## MODIFIED Requirements

### Requirement: 设置页面所有文案支持本地化
设置窗口中的所有 UI 文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings`，支持中英日自动切换。关于页的硬编码文本（Releases 按钮、版权声明）SHALL 同样走本地化系统。

#### Scenario: 侧栏导航显示
- **WHEN** 用户打开设置窗口
- **THEN** 侧栏导航项根据系统语言显示中文、英文或日文
- **AND** "常规" 显示为 "General" / "一般"
- **AND** "监控模块" 显示为 "Modules" / "モジュール"
- **AND** "显示器" 显示为 "Display" / "ディスプレイ"
- **AND** "关于" 显示为 "About" / "概要"
- **AND** "Beta" 标签显示为 "Beta" / "ベータ"

#### Scenario: 关于页面硬编码文本修复
- **WHEN** 用户进入关于页面
- **THEN** "Releases" 按钮标签通过 `String(localized:)` 引用本地化 key
- **AND** "© 2026 Acerola" 版权声明通过 `String(localized:)` 引用本地化 key
- **AND** 日文环境下显示对应日文翻译

#### Scenario: 快速呼出设置本地化
- **WHEN** 用户进入常规设置页
- **THEN** "快速呼出" 显示为 "Quick Access" / "クイックアクセス"
- **AND** "点按录制" 显示为 "Click to record" / "クリックして録音"
- **AND** "按下快捷键…" 显示为 "Press keys…" / "ショートカットキーを押す…"
- **AND** "按下按键" 显示为 "Press key" / "キーを押す"
- **AND** "清除快捷键" 显示为 "Clear shortcut" / "ショートカットをクリア"
