# HagimiMonitor

macOS 菜单栏硬件监控工具，实时展示 CPU、GPU、内存、存储、网络和电池状态。

## 截图

*待补充*

## 安装

1. 从 [Releases](https://github.com/Acerola-1/hagimi-monitor/releases) 下载最新版 `.dmg`
2. 打开 DMG，将 HagimiMonitor 拖入 Applications 文件夹

## 未公证应用放行

HagimiMonitor 目前未经过 Apple 公证，macOS 会阻止打开。安装后在终端执行：

```bash
sudo xattr -cr /Applications/HagimiMonitor.app
```

之后即可正常启动。

## 系统要求

- macOS 26 及以上
- Apple Silicon (M 系列芯片)

## 功能

- 菜单栏实时显示硬件负载
- CPU / GPU / 内存 / 存储 / 网络 / 电池监控
- 自适应浅色/深色模式
- 应用内检查更新

## 构建

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build
```

## 许可证

MIT
