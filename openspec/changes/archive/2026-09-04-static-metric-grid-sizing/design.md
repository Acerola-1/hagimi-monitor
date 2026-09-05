## Context

`MonitorPanelView.isFullRow`(:1181)是当前唯一的整行/半行判官:每次调用对标签、数字、单位各做一次 `NSString.size`,喂的是当前采样值;基准 `halfCellContentWidth = 126` 按理想面板宽 340 推导,而面板实际可调区间为 300~460。渲染侧 `metricCell`(:1311)是 HStack:标签 `layoutPriority(1)` + `Spacer(minLength: 4)` + 数值 `layoutPriority(2)`,数值带 `minimumScaleFactor(0.75)`、单位 `fixedSize()`——数值是特权方,标签是截断弱势方。`structurallyFullRowIDs`(:1157)已存在结构性整行白名单机制。面板支持中/英两语(日文本地化在本变更中移除)。

## Goals / Non-Goals

**Goals:**
- 布局成为慢变量(语言、静态登记表)的纯函数,会话期间零重排
- 两语 × 最坏值 × 最窄面板宽下零省略号
- 新指标/新文案漏评估被审计测试在开发期拦截

**Non-Goals:**
- 不做奇数半行的末格跨列补格(留待原型目测后另行决定)
- 不改变格子视觉形态(trackFill 色块、间距、圆角)与现有交互(点击复制)
- 不覆盖设置窗口、报告页等其他界面的文本溢出问题
- 不移除 `minimumScaleFactor`/`lineLimit(1)` 保险丝

## Decisions

**1. 登记表落在 MetricCellSizing.swift,键为 (kind, name) 二元组。**
`MetricCellSizing.swift` 已是网格度量常量的归属地,静态基准(整行登记、最坏值表)与之同域。指标 name 不全局唯一(`current` 同时存在于电池与风扇),键必须带模块 kind。

**2. 半格内容宽按最窄面板宽 300 推导(≈106pt),替代现值 126。**
300 − 两侧内边距 20 − 网格前导缩进 28 = 252;两列减 8 间距得每列 122;再减格子左右内衬 16 得 106。常量随代码落定,注释保留推导链。按最窄档布局,300~460 全区间判定一致,面板 resize 不触发重排。

**3. 最坏值表是静态字典,值由格式化函数的输出域推导。**
`(kind, name) → 最坏串`,如速率 `"888.8 MB/s"`、百分比 `"100.0%"`、电池电流 `"−4321 mA"`。无界值(SSID、IP、型号)不进表,直接登记整行 + 中部截断。运行时 `isFullRow` 退化为一次字典查找;`splitValue`/`minimumScaleFactor` 渲染路径不动。

**4. 标签压缩按语言独立、保守口径执行;整行登记按语言分表。**
只压超预算的语言;优先语义优化("Cycle Count"→"Cycles"),其次缩写;中文默认不压,压不动就在该语言升整行。压缩结果直接改 `Localizable.xcstrings`(python 脚本按 JSON 编辑,两语同步维护)。整行登记 `fullRowMetricIDsByLanguage` 按语言独立判定——zh 标签普遍两字(如「压力」+「严重」= 59pt 半行放得下),en 长词超预算则 en 单独升整行;语言取自 `Bundle.main.preferredLocalizations`,运行期内恒定,不构成跳动源。

**5. 行序保持既有排布:半行两列网格在前,热压力合并行与整行指标沉底。**
奇数半行的空洞因此落在模块末尾。`wifi-rssi`/`gateway-latency` 的语义配对在整行区内保持相邻。整行置顶方案经两语实例目测被推翻——热压力/启动时间等低频信息贸然置顶打断阅读节奏,恢复原行序。

**6. 审计测试放 Direct test target,与判定共享同一套字体常量与登记表。**
按语言独立遍历全部 `(kind, name)` 的半行判定 × 最窄宽,断言预算。测量用 `NSFont.size`(与渲染同规格的 labelFont/valueFont/unitFont),不依赖 SwiftUI 渲染。已知约束:TRAE 终端跑 `xcodebuild test` 会因 sandbox-exec 失败,测试由用户终端/Xcode 执行,本流程以 build 编译通过 + 一次性测量脚本产出数据为准。

**7. 一次性测量脚本放 tmp/,不进仓库。**
Swift CLI 脚本读取 `Localizable.xcstrings`,用同规格 AppKit 字体实测各语言标签宽,输出超预算清单——大清洗的数据来源;审计测试是其常驻化形态。

## Risks / Trade-offs

- [NSFont 实测宽与 SwiftUI Text 实际渲染有细微差异] → 审计与运行时判定共用同一套字体常量与同一测量 API,误差同源抵消;保险丝(minimumScaleFactor)兜住残余差异。
- [指标集合演进导致登记表过期] → 审计测试遍历 Samplers 产出的指标全集,漏登记即红。
- [行序调整的观感风险] → 两语实例目测验收;排序是独立子项,可单独回退。
- [最坏值表与格式化函数漂移(改了格式化忘改表)] → 表注释标明每项对应的格式化函数;漂移只造成预算虚高/虚低,前者无害,后者被审计拦截。

## Migration Plan

一次性替换 `isFullRow` 实现(删运行时测量,留字典查找),无数据迁移。某些指标归属预期翻转(此前按 126pt 误判半行的长值指标升整行)。回滚 = revert 单次提交。
