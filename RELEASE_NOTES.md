## 更新内容

### 新功能

- 状态项新增右键菜单，可直接退出 App。感谢 @cloudandman-ai (#56) 的反馈

### 修复

- 修复按住 ⌘ 点击菜单栏图标时无法触发系统拖动重排的问题（macOS 15 上无法调整图标位置）。感谢 @kyon45 (#44) 和 @Jwlmn (#57) 的反馈

### 优化与体验

- 优化电池功耗图标显示与本地化文案

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
