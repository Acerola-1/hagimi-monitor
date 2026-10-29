## 更新内容

### 中文

本次更新新增独立的显示器控制菜单栏入口，并修正了部分应用的进程占用无法正确合并统计的问题。

#### 新功能

- 设置 → 显示器新增「独立显示器控制菜单栏图标」开关（默认关闭）：开启后可从菜单栏直接打开显示器控制，无需先展开主面板；独立窗口按卡片内容贴合，与主面板的显示开关互不影响。

#### 修复

- 修复部分应用（Chromium / Electron 系浏览器与客户端）的 Helper 子进程未按宿主应用合并统计的问题。此前这类应用在内存、CPU、GPU、磁盘、网络与能耗排行中会被拆成多条，合计占用被低估，甚至完全不显示。

#### 优化与体验

- 小工具「不息屏」更名为「屏幕常亮」，与英文 Keep Display On 对应，含义更直白。

#### 目前已知的问题

以下问题本版尚未修复，仍在跟进：

- Apple Watch 无法正常显示电量余量（#131 · 修复中）：已能读取连接数据，但取不到准确的电量读数。
- Mac mini 无法正常显示能耗（#106 · 待解决）：手头没有对应设备，暂时无法验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98 · 未复现）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86 · 待解决）：手头没有对应设备，暂时无法验证。

### English

This release adds a standalone display-control menu bar entry and fixes process usage that was not merged correctly for some apps.

#### New Features

- Settings → Display gains a "Standalone display control menu bar icon" switch (off by default): when enabled, display controls open directly from the menu bar without expanding the main panel; the standalone window fits its card content and is independent of the main panel's display switch.

#### Fixes

- Fixed Helper processes of some apps (Chromium / Electron-based browsers and clients) not being merged under their host app. These apps could appear as several separate rows across memory, CPU, GPU, disk, network, and energy rankings, so their total usage was understated or missing entirely.

#### Improvements

- The "Keep Display On" quick tool is now labeled "屏幕常亮" in Chinese, matching the English wording.

#### Known Issues

The following are still open in this release:

- Apple Watch does not show the correct battery level (#131 · in progress): the connection data can be read, but not an accurate battery level.
- Mac mini does not show power consumption (#106 · open): no device available for verification yet.
- Network shows as disconnected after a proxy app enables TUN mode (#98 · not reproduced): enabling TUN mode locally does not trigger it.
- MacBook Air M4 does not show charging power (#86 · open): no device available for verification yet.

