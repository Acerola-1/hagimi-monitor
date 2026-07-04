## 更新内容

### 新功能

- 新增匿名使用统计：仅上报匿名安装 ID、App 版本、系统版本、芯片型号、系统语言与分发渠道，每天最多一次，不采集任何可识别个人身份的信息，可在官网「使用数据」页面查看聚合统计
- 设置窗口新增更新提醒横幅：检测到新版本时非阻塞弹出提示，网络异常时静默不打扰

### 优化与体验

- 统一设置窗口材质与无边框标题栏，标题栏透明、侧栏背景延伸至顶部
- 调整重置默认按钮布局与样式

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
