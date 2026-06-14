## 更新内容

### 新增

- 显示器模块新增对更多 DDC 协议显示器的兼容支持，自动识别虚拟屏、外接 Apple 原生屏，避免误识别
- 新增媒体键接管：可让 F1/F2、F10/F11/F12 直接控制外接显示器的亮度和音量，并显示原生 OSD 提示
- 设置页新增「显示器」相关偏好：是否包含内建屏、亮度/音量/对比度控件开关、媒体键接管开关与权限引导
- 设置页内容超出窗口时支持滚动

### 修复

- 修复音量写入时主动 unmute 导致部分显示器忽略后续音量调节的问题
- 修复显示器拔插后内部缓存残留、再次接入时首次写入被跳过的问题
- 修复 DDC 数值上限按统一 max 钳制不准确的问题，改为按各显示器真实最大值换算百分比

### 优化

- DDC 写入改为全局串行队列并对相同值去重，减少冲突与抖动
- 启动时仅探测亮度，音量/对比度延迟到首次访问时再读，加快启动并降低对部分显示器的干扰
- 显示器重新配置或系统唤醒后自动刷新 DDC 服务列表
- DDC 连续失败后自动延长重试延迟，降低对显示器的压力

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
