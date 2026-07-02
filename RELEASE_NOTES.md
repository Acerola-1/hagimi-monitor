## 更新内容

### 新功能

- 最低系统要求降至 macOS 15,更多 Mac 用户现在都能使用 HagimiMonitor 了
- 菜单栏指标支持 SF 图标 / 文字前缀切换,可在设置中自由选择

### 修复

- 修复多屏切换时状态栏图标渲染异常、未跟随系统外观的问题
- 增强主线程存活监测,降低高负载下被系统回收导致静默退出的风险

### 优化与体验

- 统一面板与底部按钮为毛玻璃质感,展开动画更顺滑一致
- 菜单栏多指标改为独立定宽单元并左对齐,消除数值变化时的左右跳动
- 精简统计报告:移除负载热力图,优化健康评分卡片布局

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
