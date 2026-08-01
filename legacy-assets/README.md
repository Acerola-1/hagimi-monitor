# 旧资产归档 (Legacy Assets)

历代废弃但需要留档的设计资产,按类别与时间线组织。

## icons/ — 应用图标历史版本

| 目录 | 版本 | 说明 |
|---|---|---|
| `01-ai-neon-original/` | 初版 | AI 生成的霓虹绿环:满幅直角原图(曾致 macOS 15 启动台直角)+ 官网用圆角变体(web-icon-1024/128) |
| `02-rounded-neon/` | 第二代 | 圆角合规修复版母版:烘焙官方圆角矩形+透明边距+标准投影,保留原霓虹风格 |
| `03-redesign-variants/` | 重设计探索 | 矢量重绘三变体对比稿:A 克制霓虹 / B 纯扁平(后被采纳) / C 明亮霓虹,各含 1024+128 |
| `04-flat-glass-layers/` | 第三代 | 扁平绿环液态玻璃版:Icon Composer 图层资产(ring/ring-light/dot)+icon.json+亮暗渲染预览 |
| `05-menubar-faithful-270deg/` | 第四代初版 | 菜单栏源码还原首版:270°弧/#2D9578墨绿点/环半径241,含完整图层+icon.json+预览 |
| `06-light-appearance/` | 浅色外观版 | 定稿几何的浅色变体(浅底+黑弧+白背板):图层/双外观icon.json/docs浅色渲染/预览,后改为双外观统一深底 |

当前线上版本(第四代定稿:环外缘342顶到官方圆形网格、240°弧止于8点钟位、#3BEC64亮绿点、亮暗双外观统一深色背景)位于 `HagimiMonitor/AppIcon.icon/`,不在此归档;图层导出脚本为 `scripts/export_icon_layers.swift`。

## posters/ — 海报与宣传图

| 目录 | 说明 |
|---|---|
| `hagimi-promo-2880/` | 2880px 宣传海报五张(promo-01~05),原位于 docs/,官网未引用故归档 |
