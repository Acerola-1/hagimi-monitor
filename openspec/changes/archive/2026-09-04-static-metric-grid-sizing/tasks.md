## 1. 测量与数据准备

- [x] 1.1 枚举全部 (kind, metric name) 指标全集(CPU/GPU/内存/存储/网络/电池/风扇/显示器模块明细指标),标注各指标的格式化函数与单位
- [x] 1.2 编写 tmp/ 一次性 Swift 测量脚本:读取 Localizable.xcstrings,用渲染同规格字体(labelFont/valueFont/unitFont)实测标签宽,输出「标签+最坏值」超预算清单
- [x] 1.3 依据测量结果确定压缩清单(逐语言:哪些英文标签压、压成什么;压不动的升整行)与整行登记清单

## 2. 静态基准落码

- [x] 2.1 在 MetricCellSizing.swift 建立静态登记:auditInventory 最坏值表 [(kind, name) → 最坏串] 与按语言分表的整行登记 fullRowMetricIDsByLanguage,注释标明各项对应的格式化函数
- [x] 2.2 半格内容宽常量改为按最窄面板宽 300 推导(=106pt),注释保留推导链,删除 340 推导口径
- [x] 2.3 isFullRow 改为字典查找:结构性整行 + 按语言整行登记判定;删除运行时 NSString.size 测量与当前值参与;测量字体常量迁移至审计测试可复用的位置
- [x] 2.4 无界值指标(SSID、IP、型号名等)确认走整行 + 中部截断路径

## 3. 标签压缩与本地化收敛

- [x] 3.1 按压缩清单用 python 脚本修改 Localizable.xcstrings(两语同步维护),压缩只动超预算语言
- [x] 3.2 移除日文本地化:xcstrings 全部 ja 条目与 pbxproj knownRegions,本地化收敛为中英两语
- [x] 3.3 行序保持既有排布(半行网格在前、整行沉底),移除依赖旧排序的过时注释;接线 isReplacedByCoreDetail 消除 core-split 格子与 P/E 瓦片的双重渲染
- [x] 3.4 显示器档案区同口径治理:分辨率/厂商格升整行跨列,超预算英文标签压缩;电池条 ETA 英文文案压缩至电池条可用宽内

## 4. 审计执法

- [x] 4.1 在 Direct test target 编写宽度审计测试:按语言独立遍历半行指标 × 最窄宽,断言预算,超预算时失败信息含语言、指标与实测宽度
- [x] 4.2 审计测试编译通过(xcodebuild build);实际 test 运行因 TRAE 终端 sandbox 限制,交付时提示用户在终端/Xcode 执行
- [x] 4.3 AGENTS.md 设计纪律增补:新增指标必须登记最坏值与标签基准,并通过宽度审计测试

## 5. 验证与交付

- [x] 5.1 构建 HagimiMonitor 与 HagimiMonitorDirect 两个 scheme(Debug)
- [x] 5.2 退出现有直连版实例,以中/英两语各启动一个直连版实例(-AppleLanguages 参数),供用户目测两语下零省略号、行序与空洞位置
