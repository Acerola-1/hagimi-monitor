## Why

面板指标格的整行/半行判定依赖运行时对当前值的逐帧文本测量(`isFullRow` 每次调用对标签、数值、单位各做一次 `NSString.size`),导致两类反复出现的 bug:判定基准用的是理想面板宽 340 推导的 126pt,面板收窄到 300 时实测放得下、渲染却溢出省略号;判定喂的是当前值,快变长值(速率、SSID、IP)在面板打开期间跳变引发一次性重排。历史修复方式是逐个人工目测调整,没有系统性计算,同类 bug 反复回归。

## What Changes

- 删除 `isFullRow` 的运行时文本测量与当前值参与,整行/半行判定改为静态登记表(哪些指标 ID 整行、哪些半行),判定基准改为按最窄面板宽 300 推导的半格内容宽(约 106pt),使 300~460 全程判定一致成立。
- 整行登记按语言分表(`fullRowMetricIDsByLanguage`):zh 标签普遍两字,半行能容纳的指标比 en 多,同一指标在两语下的布局归属可以不同;语言取自 `Bundle.main.preferredLocalizations`,运行期内恒定,不构成跳动源。
- 建立中英两语标签宽度基准表:逐指标×逐语言用渲染同规格字体实测标签宽,标签超预算时按语言分别做极限压缩(缩写/语义优化),压缩是逐语言的——中文通常无需压缩,重点在英文长词。
- 移除日文本地化(xcstrings 全部 ja 条目与 pbxproj knownRegions),本地化收敛为中英两语,降低文案维护成本。
- 建立指标最坏值表:每个数值格式化路径声明其最坏串(如 "99.99 GB"、"100%"),值宽度由格式化契约保证有界,不再依赖运行时实测。
- 新增构建期宽度审计测试:按语言独立遍历半行指标 × 最坏值 × 最窄面板宽,断言「压缩后标签宽 + 最坏值宽 + 间距 ≤ 半格内容宽」;从某语言的整行登记中移除条目,该语言立即恢复半行审计——登记即布局决策。
- 行序保持既有排布:半行两列网格在前、热压力合并行与整行指标沉底,奇数个半行的空洞落在模块末尾(整行置顶方案经目测被推翻)。
- `minimumScaleFactor` 与标签 `lineLimit(1)` 保留为最后防线,从主要机制降级为保险丝,兜超出登记口径的硬件极值。
- 接线 `isReplacedByCoreDetail`:core-split 指标格被 P/E 占用瓦片取代后不再进网格,消除同源数据双重渲染。
- 显示器档案区 tile 纳入同口径治理(预算 104pt @ caption2):分辨率与厂商格升整行跨列,超预算的英文标签压缩(Refresh/Depth/Density/Gamut 等)。
- AGENTS.md 增补纪律条目:新增指标必须登记最坏值与标签宽度基准,并通过宽度审计测试。

## Capabilities

### New Capabilities

- `metric-width-audit`: 构建期指标宽度审计——静态登记表、最坏值表、按语言分表的整行登记的维护规则与测试执法机制,保证新增/修改指标在编译期暴露宽度超预算。

### Modified Capabilities

- `monitor-panel`: 展开区指标网格的整行/半行判定从运行时实测改为按语言分表的静态登记;行序保持半行在前、整行沉底;值宽度由格式化契约保证。

## Impact

- `HagimiMonitor/MonitorPanelView.swift`:`isFullRow` 改静态查表、`shortMetrics`/`fullRowMetrics` 过滤条件、`isReplacedByCoreDetail` 接线、`splitValue` 保险丝注释。
- `HagimiMonitor/Views/Panel/MetricCellSizing.swift`:`StaticMetricSizing` 静态基准(按语言整行登记、auditInventory 最坏值契约、测量字体)。
- `HagimiMonitor/Views/Panel/DisplayInfoSection.swift`:基础四项/档案区整行升级与标签口径。
- 新增 `HagimiMonitorTests/MetricWidthAuditTests.swift`(按语言独立审计)。
- `HagimiMonitor/Localizable.xcstrings`:英文部分标签压缩改写、日文本地化移除。
- `hagimi-monitor.xcodeproj/project.pbxproj`:knownRegions 移除 ja。
- `AGENTS.md`:设计纪律增补一条。
