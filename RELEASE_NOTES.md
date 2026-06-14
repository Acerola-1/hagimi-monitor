## 更新内容

### 新功能

- **内存模块新增 Top 5 进程占用排行**（感谢 @tarnish233 贡献 #14）
  - 在内存模块展开区域显示当前内存占用最高的 5 个进程
  - 进程名称、内存占用一目了然

---

## 安装说明 / Installation

HagimiMonitor 尚未通过 Apple 公证（notarization），macOS 首次启动时可能会阻止运行。将 HagimiMonitor 安装到  后，请执行以下命令：

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```

HagimiMonitor is not notarized by Apple. macOS may block it on first launch. After installing to , run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```
