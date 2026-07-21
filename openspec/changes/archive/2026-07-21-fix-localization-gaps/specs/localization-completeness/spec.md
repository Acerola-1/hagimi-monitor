## ADDED Requirements

### Requirement: All user-visible text SHALL use String(localized:)
所有用户可见的 UI 文本 SHALL 通过 `String(localized:)` 引用 `Localizable.xcstrings`，不得在视图代码、Sampler、枚举 title 属性中硬编码中文或英文字符串。

#### Scenario: Sampler 采样失败占位文本
- **WHEN** GPUSampler、MemorySampler 或 StorageSampler 采样失败
- **THEN** 返回的 `placeholderModule` summary 通过 `String(localized:)` 引用本地化 key（如 `sampler.unavailable`）
- **AND** 中文显示"无法读取"，英文显示"Unavailable"，日文显示"読み取れません"

#### Scenario: 面板标题文本
- **WHEN** MonitorPanelView 渲染面板顶部标题
- **THEN** "SYSTEM · LIVE" 通过 `String(localized:)` 引用本地化 key
- **AND** 各语言显示对应的翻译文本

#### Scenario: 关于页硬编码文本
- **WHEN** AboutSettingsView 渲染关于页面
- **THEN** "Releases" 按钮标签通过 `String(localized:)` 引用本地化 key
- **AND** "© 2026 Acerola" 版权声明通过 `String(localized:)` 引用本地化 key
- **AND** 各语言显示对应的翻译文本

#### Scenario: HaloRingSource title 一致性
- **WHEN** HaloRingSource 的 `.cpu` 或 `.gpu` 分支返回 title
- **THEN** 使用 `String(localized:)` 引用本地化 key，与 `.combined` 和 `.memory` 分支保持一致

#### Scenario: MenuBarMetricKind prefix 本地化
- **WHEN** MenuBarMetricKind 的 `menuBarPrefix` 属性返回菜单栏指标前缀
- **THEN** 每个前缀通过 `String(localized:)` 引用本地化 key（如 `menu-bar-metric-prefix.cpu`）
- **AND** 各语言显示对应的缩写翻译

### Requirement: Localizable.xcstrings 包含完整中英日翻译
`Localizable.xcstrings` SHALL 包含所有 UI 文案的中英日三语翻译，不得有任何 key 缺失翻译。

#### Scenario: 日语系统下使用媒体键接管功能
- **WHEN** 系统语言为日语且用户打开显示器设置页
- **THEN** "媒体键接管" 显示为 "メディアキー割り当て"
- **AND** "接管亮度键（F1/F2）" 显示为 "明るさキーを割り当て（F1/F2）"
- **AND** "接管音量键（F10/F11/F12）" 显示为 "音量キーを割り当て（F10/F11/F12）"
- **AND** "显示原生 OSD 提示" 显示为 "ネイティブ OSD を表示"
- **AND** "辅助功能权限" 显示为 "アクセシビリティ権限"
- **AND** "已授权" / "未授权" 显示为 "許可済み" / "未許可"
- **AND** "刷新权限状态" 显示为 "権限状態を更新"
- **AND** "打开系统设置" 显示为 "システム設定を開く"

#### Scenario: 日语系统下使用面板钉住功能
- **WHEN** 系统语言为日语且用户右键面板标题栏
- **THEN** "钉住面板" 显示为 "パネルをピン留め"
- **AND** "取消钉住" 显示为 "ピン留めを解除"
- **AND** "关闭面板" 显示为 "パネルを閉じる"

#### Scenario: 日语系统下使用快速呼出功能
- **WHEN** 系统语言为日语且用户打开常规设置页
- **THEN** "快速呼出" 显示为 "クイックアクセス"
- **AND** "点按录制" 显示为 "クリックして録音"
- **AND** "按下快捷键…" 显示为 "ショートカットキーを押す…"
- **AND** "按下按键" 显示为 "キーを押す"
- **AND** "清除快捷键" 显示为 "ショートカットをクリア"

#### Scenario: Beta 标签日语翻译
- **WHEN** 系统语言为日语且侧栏显示 Beta 标签
- **THEN** "Beta" 显示为 "ベータ"

### Requirement: 迁移映射使用语言无关标识符
`MonitorSettings.migrateMetrics` 中的旧版 ID 迁移映射 SHALL 使用与系统语言无关的匹配策略，确保非中文系统下旧数据迁移不丢失。

#### Scenario: 英文系统下从旧版迁移
- **WHEN** 用户从旧版升级且系统语言为英文
- **THEN** 旧版英文 metric ID（如 "System", "User"）正确映射到新英文 key
- **AND** 设置不因语言不匹配而丢失

#### Scenario: 日文系统下从旧版迁移
- **WHEN** 用户从旧版升级且系统语言为日文
- **THEN** 旧版日文 metric ID 正确映射到新英文 key
- **AND** 设置不因语言不匹配而丢失
