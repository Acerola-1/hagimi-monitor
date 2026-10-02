# 正式组件迁移目录

本目录按当前源码登记。表中的渠道可见项是源码条件与设置投影；实际桌面检查结果另见 `verification.md`，不能把编译分支清单写成已完成实机验收。

## 顶层与专用内容

| 稳定 ID | 原组件与内容 | 渠道及可用条件 | 既有交互 |
| --- | --- | --- | --- |
| `cpu` | MetricGlassRow，逐核、指标、进程图标 | 两渠道；温度/热压力依数据与渠道能力 | 整行展开、指标选择/排序、原进程列表 |
| `gpu` | MetricGlassRow，GPU 指标与进程 | 两渠道；缺失数据沿原语义 | 整行展开、指标选择/排序 |
| `fan` | MetricGlassRow / FanList，实际风扇与状态 | Direct；多风扇才有明细，单风扇主行显示 RPM | 多风扇列表展开；不新增风扇写入能力 |
| `memory` | MetricGlassRow，压力/使用率、指标与进程 | 两渠道；压力主值由原设置控制 | 主值模式、指标选择/排序、原进程列表 |
| `storage` | MetricGlassRow，卷/磁盘与进程 | 两渠道；列表按可用数据 | 整行展开、指标选择/排序 |
| `network` | NetworkGlassRow，连接、诊断、进程 | 两渠道；Wi-Fi/有线/断开依实际连接和权限 | 原复制、指标顺序、列表 |
| `battery` | BatteryGlassRow / PowerDetailPages，功率流、健康、供电 | 两渠道；按硬件/供电/探针可用性 | 原分页状态、拓扑、诊断、分页指标顺序 |
| `bluetooth` | BluetoothGlassRow / BluetoothDeviceList，设备与电量 | 两渠道；设置/设备/权限决定出现及可展开性 | 原组件整体展开，逐设备静态内容；没有原生逐设备折叠动作 |
| `display` | DisplaySection，显示器主分区 | 两渠道；模块开关控制；数量按实际设备 | 主分区展开、原设备档案与复制 |

`nativePanelItems` 直接从原 `compactRow` 与 `displaySection` 生成宿主，不维护 Demo 内容副本。八种 MonitorKind 加独立显示器组成完整目录；蓝牙、风扇或其他项因设置/硬件不出现不代表适配缺失。

## 递归与布局身份

- 显示器顶层为 `display`，逐设备档案为 `display-arc-<CGDirectDisplayID>`。设备列表的内衬与间距来自现有 PanelChildGroup。Direct 由 DisplayControlGroup 保留亮度/音量/对比度及控制区到档案替换；App Store 为 DisplayInfoCard 的只读基础信息/档案。
- 电源各页面共用 `battery` 的自然尺寸，不额外创建第二套高度动画。页内供电排序身份仍为 `adapter-port`、`pd-contract`、`pd-tiers`、`adapter-transports`、`input-telemetry`。
- `__header__` 和 `__footer__` 是尺寸/宿主身份，原标题、统计、监视器、工具、设置、钉住及关闭动作继续负责功能。
- 可见投影与用户完整顺序分开；隐藏项保留原排序身份。嵌套宽度由 GeometrySnapshot.width 逐层扣除当前 group 内衬，指标跨度仍由 MetricCellSizing 的静态登记决定。

## 渠道清单与实际观察

Direct 的源码目录为 CPU/GPU/风扇/内存/磁盘/网络/电源/蓝牙，加显示器；App Store 的同一投影排除风扇并提供只读显示器。实际列表还受设置与可用数据过滤。

已有 Direct 原生检查看到 CPU/GPU/风扇/内存/磁盘/网络/电源/显示器；当时蓝牙隐藏。App Store 最新候选已构建，当前版本的桌面可见列表及控制边界还需实机检查。

后续用户于 2026-10-01 明确确认完整人工操作矩阵全部检查通过，包含全模块与两渠道边界、蓝牙空态和可用设备。该当前验收登记见 `verification.md`，上段保留早期观察的版本与范围边界。

## 与其他 change 的交叉

`panel-long-press-reordering` 的稳定 ID、持久化、既有方向命令、捕获预览及作用域复用原实现。本次只适配独立宿主窗口坐标、呈现坐标及边缘滚动；不改该 change 的任务标记，不宣告其未完成的长按交互通过。

## 本次后台模型验证

PanelGeometryTests 新增全模块自定义顺序、封顶/解封顶、不可用明细、底部可达，以及显示器增减/隐藏蓝牙/旧版本测量拒绝。既有测试继续覆盖 300/340/460 宽度的嵌套内衬和替换端点。此处的设备/可用性数据是几何夹具，不是实际热插拔或蓝牙连接证据。
