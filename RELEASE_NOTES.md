## 更新内容

  功能修复
  - 修复 WiFi 切以太网后网络模块无反应的问题
  - 修复关网时文案显示为网络：网络的问题，改为未连接

  性能与体验优化
  - 重写负载聚合逻辑：改用归一化 softmax（k=0.08）替代加权平均，准确反映瓶颈状态
  - 重构菜单栏环动画：从固定步进改为 ease-out 缓动、帧率从 0.5s 提到 30fps、factor=0.10 更柔和
  - 颜色档阈值随 softmax 重标：25/50/78，让告警更及时准确
  - 图标分桶从 2% 到 1%，提升视觉精度

  本地化与界面
  - 新增网络接口类型（Wi-Fi/以太网/蜂窝/网桥等）的三语（简中/英文/日文）本地化
  - 移除内存进程列表标题，优化内存模块布局
  - 调整设置视图的布局与内边距

  代码质量
  - 删除不再使用的 MetricFlowPlacer 残留测试
  - 更新全部测试适配新算法

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
