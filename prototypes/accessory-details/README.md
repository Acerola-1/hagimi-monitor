# 风扇与蓝牙明细原生预览

这是独立的 SwiftUI + AppKit 初稿设计预览，不进入正式应用 target，不连接硬件、不写入应用偏好，也不改变 `MonitorStore` 的数据。方案 A 已接入正式组件，正式实现以 `MonitorPanelView.swift`、`PanelAccessoryGroup.swift` 及其原生布局测试为准；此窗口保留初稿对照。

复用 `MonitorPalette.swift`、`Constants.swift` 和经典毛玻璃材质：面板 `.popover/.behindWindow`，行 `.menu/.withinWindow`。示例界面明确标注 PREVIEW 和示例数据。

## 两个方案

- A：左右风扇在共同内衬中并排；AirPods 用一个设备容器承载标题和左耳、右耳、充电仓三格，取消重复的耳机总电量。多风扇按两列继续排布，多蓝牙设备各有自己的容器。
- B：保留纵向明细，用设备标题和共同底色建立归属，风扇列表加入图标、状态与分隔线。适合纵向比较和较长的名称。

两个方案都将 0 RPM 表示为中性的“停转”，没有把它推断为正常休眠或故障；部件没有上报电量时保留 `—`。示例充电状态使用闪电图标。

## 运行

```sh
bash prototypes/accessory-details/build.sh
open tmp/accessory-ui-preview/AccessoryDetailsPreview.app
```

右侧可以切换方案、截图同态/完整电量/四风扇多设备、300/340/460 pt、明暗外观和中英文。一次只展示一个完整方案。

如需导出原生截图，设置 `HAGIMI_ACCESSORY_PREVIEW_EXPORT` 为输出目录，再直接运行 app 内的可执行文件。导出涵盖两种方案、三个场景和明暗中英文，宽度使用 300 pt。产物写入 `tmp/`，不提交。

## 正式落地边界

正式实现使用独立的 `FanStatus.stopped` 表示实测 0 RPM，告警服务对停转不发送故障或恢复通知。硬件不能提供健康证据时，不推断风扇故障。

正式集成时接入真实 `FanInfo`、`BluetoothDevice` 和现有展开/高度/滚动链路，文案接入 `Localizable.xcstrings` 中英翻译；宽度契约登记到现有静态尺寸体系，并验证长设备名、不同部件组合、单/多风扇、多个设备、充电/缺失/真实 0% 及渠道构建。独立预览不证明真实设备读取和正式面板的动画验收。
