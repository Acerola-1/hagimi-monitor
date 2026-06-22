# HagimiMonitor

> [English](README.en.md) · [官网](https://acerola-1.github.io/hagimi-monitor/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="HagimiMonitor icon">
</p>

<p align="center">
  <strong>你的 Mac，一眼即懂。</strong>
</p>

<p align="center">
  HagimiMonitor 是一款优雅的 macOS 菜单栏系统监控工具，将 CPU、GPU、内存、存储、网络、电池与显示器状态，以动态圆环和紧凑玻璃面板呈现在菜单栏。
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/hagimi-monitor/releases/latest"><strong>下载最新版</strong></a> ·
  <a href="#功能亮点">功能亮点</a> ·
  <a href="#截图">截图</a> ·
  <a href="#安装">安装</a> ·
  <a href="#构建">构建</a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M%20series-2ECC71?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

## 截图

### 多主题配色

HagimiMonitor 内置语义化 Palette，模块色、玻璃背景、分隔线、进度轨道和状态色会随主题统一变化。目前提供「平衡」与「活力」两套风格，并完整适配浅色 / 深色模式。

| 平衡 · 深色 | 平衡 · 浅色 |
| --- | --- |
| ![平衡深色主题](docs/images/balance-dark.png) | ![平衡浅色主题](docs/images/balance-light.png) |

| 活力 · 深色 | 活力 · 浅色 |
| --- | --- |
| ![活力深色主题](docs/images/vitality-dark.png) | ![活力浅色主题](docs/images/vitality-light.png) |

### 展开即见详情

默认状态保持紧凑，点击菜单栏后即可展开查看 CPU、GPU、内存、存储、网络、电池和显示器等模块的完整信息。

<p align="center">
  <img src="docs/images/detailed-data.png" width="430" alt="HagimiMonitor expanded rich metrics">
</p>

## 功能亮点

### 菜单栏一眼可见

动态环形图标实时反映系统负载，综合 CPU 与 GPU 使用率平滑计算当前压力。轻载、忙碌、接近高压，都能直接从菜单栏判断。

### 七大监控模块

从菜单栏到详细面板，每一个关键指标都触手可及：

- **CPU**：系统 / 用户 / 空闲占用、运行时间、温度读取、进程级占用
- **GPU**：图形负载、渲染 / 分块性能、显存信息
- **内存**：使用率、内存压力、交换分区、压力等级变化
- **存储**：系统磁盘、外部卷容量、读写速率
- **网络**：上传 / 下载速率、网络接口类型、IP 信息
- **电池与电源**：电量、供电状态、功耗、健康度等可用信息
- **显示器**：亮度、音量、对比度控制，取决于设备 DDC/CI 支持情况

### 玻璃拟态与统一配色

面板采用轻量玻璃拟态 UI，并通过统一 Palette 管理模块强调色、状态语义色、分隔线、进度轨道和浅深色模式，让信息层级更清晰。

### 统计、健康评分与事件检测

HagimiMonitor 会围绕系统状态提供更多长期视角：

- 0-100 分 Mac 健康评分，覆盖 CPU、GPU、磁盘、内存压力与散热维度
- 24 小时、7 天、30 天、一年等多时间维度统计
- 自动检测 CPU 高负载、内存压力、磁盘空间不足、网络流量峰值等关键事件

### 外接显示器控制

支持通过 DDC/CI 协议在菜单栏内调节外接显示器亮度、音量和对比度。该功能依赖显示器、线材、连接方式和系统环境支持；不支持的控制项不会强行展示为可用。

### Swift 原生，轻量常驻

应用使用 Swift / SwiftUI 原生开发，面向 Apple Silicon 优化。日常常驻内存约 30 MB，适合作为长期挂在菜单栏里的系统状态面板。

## 安装

1. 从 [Releases](https://github.com/Acerola-1/hagimi-monitor/releases/latest) 下载最新版 `.dmg`
2. 打开 DMG，将 HagimiMonitor 拖入 Applications 文件夹
3. 从 Launchpad 或 Applications 启动

## 未公证应用放行

HagimiMonitor 目前未经过 Apple 公证，macOS 可能会阻止打开。安装后在终端执行：

```bash
sudo xattr -cr /Applications/HagimiMonitor.app
```

之后即可正常启动。

## 系统要求

- macOS 26 及以上
- Apple Silicon（M 系列芯片）

## 构建

开发调试建议使用 `HagimiMonitorDirect` scheme：

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Release / App Store 构建：

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Release build
```

运行测试：

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test
```

## Star History

<p align="center">
  <a href="https://star-history.com/#Acerola-1/hagimi-monitor&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acerola-1/hagimi-monitor&type=Date" width="720" />
    </picture>
  </a>
</p>

<p align="center">
  如果这个项目对你有帮助，欢迎点一个 ⭐ 支持持续维护。
</p>

## 许可证

MIT
