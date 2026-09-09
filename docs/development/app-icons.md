# 图标维护说明

仅在修改应用图标、Icon Composer 资产或文档图标时阅读。面板采用经典毛玻璃不意味着需要修改应用图标的系统材质。

## 资产入口

| 资产 | 位置 | 用途 |
| --- | --- | --- |
| Icon Composer 源文件 | `HagimiMonitor/AppIcon.icon/` | 图层、材质及外观配置 |
| 栅格图标资产 | `HagimiMonitor/Assets.xcassets/AppIcon.appiconset/` | 核对构建图标来源及回退时一并检查 |
| 菜单栏负载环 | `HagimiMonitor/MenuBarComputeRingIcon.swift` | 品牌图形的语义参考 |
| 图层导出脚本 | `scripts/export_icon_layers.swift` | 生成图层与关于页使用的合成图 |
| 文档图标 | `docs/images/icon.png`、`icon-128.png` | README 与官网 |
| 历史资产 | `legacy-assets/README.md` | 查找旧版图标与海报 |

图层几何以导出脚本为准，当前材质及图层组合以 `AppIcon.icon/icon.json` 为准。两者表达不同内容，不用菜单栏实时环参数直接覆盖应用图标的专用比例。

## 修改边界

- 保留负载环与绿色核心点的品牌识别，以及现有深底风格；改变整体外观属于设计改动，需要展示原生结果。
- 源图层不额外烘焙系统玻璃高光；图层绘制与 Icon Composer 材质分别调整，便于定位效果来源。
- 文档/官网图标采用扁平展示。为营销图调整材质时使用独立副本，保持正式 `.icon` 源资产不受影响；替换前检查现有引用，通常保留文件名。
- 不根据旧实验笔记自动关闭或开启 gradient、glass、translucency 等字段。当前配置与修改目标是依据，渲染行为以当前工具链验证。
- 如需使用外观 specializations，按当前 Icon Composer 导出的结构编辑并逐外观验证，避免把基础值与外观覆盖的优先级当作未经验证的假设。

## 验证

1. 用当前 Xcode 的 Icon Composer 检查源资产，分别观察支持的明暗外观；静态导出只能辅助检查构图，不能替代系统材质的实时结果。
2. 需要命令行导出时，先检查当前 `ictool` 帮助，确认选项；图层 PNG 可通过 `swift scripts/export_icon_layers.swift <图层类型> <输出路径>` 生成，支持类型见脚本。
3. 构建受影响的渠道，检查实际 `.app` 中的图标资源及运行显示，确认新系统与 macOS 15 回退。不能仅凭源目录中存在同名 `.icon`/appiconset 推断哪个被采用。
4. 比较不同格式资源时先解码或渲染成相同尺寸的像素图；PNG 与 ICNS 文件哈希不同不能说明图标来源错误。
5. 文档图标在实际 README/页面尺寸下检查；验证输出放 `tmp/`，不提交临时副本。

没有对应系统或实时预览时明确列为未验证，不沿用旧工具版本的测量值作为本次结论。
