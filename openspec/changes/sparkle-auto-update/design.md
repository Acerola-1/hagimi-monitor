## Context

HagimiMonitor 是 macOS 26+ Apple Silicon 菜单栏应用，目前没有更新检查能力。当前仓库没有第三方依赖，也没有完整 Developer ID 签名、公证、Sparkle appcast 和 CI 发布配置。

完整自动更新的真实链路如下：

```
Sparkle 自动更新
  ├─ Sparkle SPM/framework
  ├─ EdDSA 更新签名私钥
  ├─ appcast.xml
  ├─ Developer ID 签名
  ├─ Apple notarization
  ├─ 沙盒 XPC helper entitlement
  └─ 端到端安装重启验证
```

这些适合正式分发阶段，但当前目标是先让用户知道有新版本，并能去下载。

## Goals / Non-Goals

**Goals:**

- 用户可在应用内手动检查 GitHub 上是否有新版本
- 有新版本时展示版本号、发布时间和下载入口
- 下载和安装由用户手动完成
- 不引入 Sparkle，不要求 EdDSA 私钥
- 不要求 Developer ID 证书、公证或自动发布 CI
- 保持 App Sandbox 开启，仅增加必要网络权限

**Non-Goals:**

- 不自动下载并替换 app bundle
- 不自动重启应用
- 不生成 appcast.xml
- 不签名更新包
- 不处理差分更新、更新频道、后台自动检查

## Decisions

### 1. 使用 GitHub Releases latest API

**选择**: 请求 `https://api.github.com/repos/acerola/hagimi-monitor/releases/latest`

**理由**:

- 不需要额外服务器
- GitHub Release 已经是当前分发入口
- JSON 响应包含 `tag_name`、`html_url`、`assets`、`published_at`、release notes
- 可以先做到“提示 + 下载”，不承担安装安全链路

**替代方案**:

- Sparkle: 体验更完整，但当前缺少私钥、签名、公证和 CI 条件
- GitHub raw/version 文件: 简单但需要额外维护版本文件
- GitHub Pages: 对当前目标过重

### 2. 手动下载，不自动安装

**选择**: 打开 release 页面或首个匹配的 `.dmg`/`.zip` asset 链接。

**理由**:

- 沙盒应用不需要写入 `/Applications`
- 不需要 XPC helper
- 不需要替换正在运行的 app bundle
- 失败模式清晰：用户只是去浏览器下载

```
Settings About
      │
      ▼
检查更新
      │
      ▼
GitHub latest release
      │
      ├── 当前已是最新版
      │
      ├── 有新版本 ──► 下载更新 ──► 浏览器打开 GitHub Release/asset
      │
      └── 请求失败 ──► 显示错误状态
```

### 3. 版本比较以 SemVer 为主，容忍 `v` 前缀

**选择**: 将 release `tag_name` 中的 `v` 前缀去掉后，与 `CFBundleShortVersionString` 做数字段比较。

**理由**:

- 常见 tag 格式是 `v1.2.3`
- Bundle 版本通常是 `1.2.3`
- 字符串比较会把 `1.10.0` 错判为小于 `1.9.0`

初版只需要支持稳定版本号，例如：

- `1.0.0`
- `v1.0.0`
- `1.2`
- `v1.2.3`

预发布 tag 如 `v1.2.0-beta.1` 初版可忽略，除非 GitHub latest 返回它。

### 4. About 页面承载更新入口

**选择**: 先只在 Settings → About 添加检查更新，不改 App 菜单。

**理由**:

- About 页面已有版本信息，语义最自然
- 不需要引入全局 command 状态
- 降低首版实现范围

未来如果用户需要，也可以把同一个服务注入到 App menu。

## Risks / Trade-offs

- **[权衡] 不是自动更新**: 用户仍需手动安装，但当前没有签名/公证条件，这是合理边界
- **[风险] GitHub API 网络失败或限流**: 手动触发频率低，直接显示失败状态即可
- **[风险] release asset 命名不稳定**: 优先打开 `html_url` 最稳；如果直接下载 asset，需要约定 `.dmg`/`.zip` 命名
- **[风险] 未签名/未公证下载包会被 Gatekeeper 拦截**: 本变更不解决分发可信问题，只提供发现和下载入口
- **[后续] 正式自动更新**: 等 Developer ID、公证、Sparkle EdDSA key 和 CI secrets 准备好后，另起 Sparkle 变更
