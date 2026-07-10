## 更新内容

### 修复

- 修复外接显示器音量数值与硬件实际状态不同步的问题
- 修复鼠标停留在内建屏幕时，媒体键无法调节唯一外接显示器亮度/音量的问题
- 修复紧凑模式下网络上传/下载速率数值进位时被截断成省略号的问题

### 优化与体验

- 大幅降低 CPU 和内存占用，运行更轻量，建议所有用户升级
- 优化紧凑模式菜单栏图标：数值与单位改为居中对齐、固定宽度显示，不再随数字变化左右跳动
- 精简接管媒体键设置，移除低效用的精细步进反转开关

---

## 安装说明 / Installation

HagimiMonitor 尚未通过 Apple 公证（notarization），macOS 首次启动时可能会阻止运行。将 HagimiMonitor 安装到 `/Applications` 后，请执行以下命令：

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```

HagimiMonitor is not notarized by Apple. macOS may block it on first launch. After installing to `/Applications`, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```
