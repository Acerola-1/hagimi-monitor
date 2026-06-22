## 更新内容

### 新功能

- 菜单栏新增「指标」显示模式，可在「光环」与最多 4 个数值指标之间切换
- 支持的菜单栏指标：CPU / GPU / 内存使用率、电池电量、网络上下行、CPU 温度、剩余存储
- 通用设置新增菜单栏显示配置，可选择模式、勾选指标并调整显示顺序，带实时预览
- 热力图新增说明文字与平均负载提示，事件查询范围扩展为一年并支持手动展开

### 优化

- 菜单栏数值左对齐并按最长占位符锁定宽度，数字变化时不再挤动其他菜单栏图标
- 预览区域支持滚动与居中布局，在小窗口下也能完整展示选中的指标组合

### 变更

- 通用设置中的「光环数据源」选择器已移除，光环统一展示综合负载

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
