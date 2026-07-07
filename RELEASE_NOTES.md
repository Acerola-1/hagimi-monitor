## 更新内容

### 新功能

- 新增紧凑模式,对小屏用户更友好,感谢 @myg321 的建议

### 修复

- 修复指标右侧占位异常的问题,感谢 @myg321 的反馈
- 修复死循环逻辑概率导致软件无响应,感谢 @qlenlen 提供的日志

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
