## ADDED Requirements

### Requirement: docs 官网支持中英文双语
产品官网 SHALL 支持中英文双语展示，根目录 `docs/index.html` 自动检测浏览器语言并重定向到对应语言页面，同时支持用户手动切换并持久化选择。

#### Scenario: 首次访问（中文浏览器）
- **WHEN** 用户首次访问 `docs/index.html`
- **AND** 浏览器语言为中文
- **THEN** 页面自动重定向到 `docs/zh/index.html`
- **AND** 展示中文内容

#### Scenario: 首次访问（英文浏览器）
- **WHEN** 用户首次访问 `docs/index.html`
- **AND** 浏览器语言非中文
- **THEN** 页面自动重定向到 `docs/en/index.html`
- **AND** 展示英文内容

#### Scenario: 手动切换语言
- **WHEN** 用户在页面右上角点击语言切换按钮
- **THEN** 页面跳转到对应语言版本
- **AND** 用户选择写入 localStorage
- **AND** 下次访问时优先使用用户选择而非浏览器语言

#### Scenario: 再次访问（已有选择）
- **WHEN** 用户再次访问 `docs/index.html`
- **AND** localStorage 中已存储语言偏好
- **THEN** 页面根据 localStorage 中的偏好重定向
- **AND** 忽略浏览器语言设置

#### Scenario: localStorage 不可用
- **WHEN** 用户浏览器禁用或限制 localStorage
- **THEN** 根页面不抛出 JavaScript 错误
- **AND** 页面回退到浏览器语言检测

#### Scenario: 禁用 JavaScript
- **WHEN** 用户禁用 JavaScript 访问 `docs/index.html`
- **THEN** 页面通过 `<noscript>` 提供中文和英文入口链接

### Requirement: 语言切换按钮位于右上角
官网 SHALL 在页面右上角提供语言切换按钮，支持中文/英文切换。

#### Scenario: 切换按钮展示
- **WHEN** 用户查看页面右上角
- **THEN** 可见语言切换按钮（显示为 "中/EN" 或当前语言标识）
- **AND** 点击后展开语言选择菜单
- **AND** 选择后页面立即跳转

### Requirement: 中英文页面内容一致
`docs/zh/index.html` 和 `docs/en/index.html` SHALL 保持内容结构一致，仅文案语言不同。

#### Scenario: 内容同步
- **WHEN** 中文页面更新内容
- **THEN** 英文页面 SHALL 同步更新对应内容
- **AND** 两者保持相同的 HTML 结构和样式

### Requirement: 语言页资源路径可用
`docs/zh/index.html` 和 `docs/en/index.html` SHALL 正确加载共享静态资源。

#### Scenario: 语言页加载图片与图标
- **WHEN** 用户访问 `docs/zh/index.html` 或 `docs/en/index.html`
- **THEN** favicon、App icon、截图、Star chart 等资源均正常加载
- **AND** 从原 `docs/index.html` 复制而来的 `images/...` 路径已改为 `../images/...` 或站点根相对路径

### Requirement: 双语页面 SEO 元信息完整
每个语言页面 SHALL 提供与当前语言匹配的 SEO 与结构化数据。

#### Scenario: 中文页面元信息
- **WHEN** 用户访问 `docs/zh/index.html`
- **THEN** `<html lang="zh-CN">`
- **AND** title、meta description、JSON-LD description 使用中文
- **AND** 页面包含 zh-CN/en 的 `rel="alternate" hreflang` 链接与 canonical 链接

#### Scenario: 英文页面元信息
- **WHEN** 用户访问 `docs/en/index.html`
- **THEN** `<html lang="en">`
- **AND** title、meta description、JSON-LD description 使用英文
- **AND** 页面包含 zh-CN/en 的 `rel="alternate" hreflang` 链接与 canonical 链接
