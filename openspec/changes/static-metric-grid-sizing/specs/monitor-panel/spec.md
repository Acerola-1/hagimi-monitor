## MODIFIED Requirements

### Requirement: Long Panel Content Handling
The panel SHALL handle long metric values, localized labels, display names, network identifiers, and storage volume names without overlapping adjacent UI. Metric grid 的整行/半行布局 SHALL 是静态登记与格式化契约的纯函数,不依赖运行时对当前值的文本测量。

#### Scenario: Network details contain long values
- **WHEN** network details include long IP addresses, interface names, upload values, or download values
- **THEN** the expanded details use a layout that preserves readable label/value relationships
- **AND** overflowing values use explicit truncation or scaling behavior without overlapping other controls

#### Scenario: Storage or display names are long
- **WHEN** a storage volume name or display name exceeds available width
- **THEN** the name is truncated in the middle or otherwise preserves the most useful identifying portions
- **AND** adjacent percentage, badge, slider, or status controls remain visible and aligned

#### Scenario: Localized text is longer than the current language baseline
- **WHEN** localized labels or button titles are longer than their Chinese baseline text
- **THEN** the panel keeps readable spacing and avoids text overlap in collapsed and expanded states

#### Scenario: 布局不随当前值与面板宽度重排
- **WHEN** 面板宽度在支持区间内调整,或指标值在会话期间发生长度变化
- **THEN** 每个指标格的整行/半行归属与排列保持稳定
- **AND** 判定基准取最窄支持面板宽度推导的半格内容宽,使全区间判定一致成立

## ADDED Requirements

### Requirement: 展开区指标行序
模块展开区指标网格 SHALL 将半行两列网格排在前面,热压力合并行与整行指标沉底;半行数量为奇数时,空缺格 SHALL 落在模块末尾。

#### Scenario: 整行与半行混合
- **WHEN** 某模块展开区同时含整行与半行指标
- **THEN** 半行两列网格先渲染,热压力合并行与整行格随其后
- **AND** 半行数量为奇数时,模块末尾最后一格留空而非中部出现空洞

#### Scenario: 语义配对的整行指标
- **WHEN** 两个整行指标存在语义配对关系(如 Wi-Fi 信号与网关延迟)
- **THEN** 二者在整行区内保持相邻与既定先后顺序

### Requirement: core-split 指标格的 P/E 瓦片取代
CPU 展开区 SHALL 以 P/E 占用瓦片展示分组占用;core-split 指标被瓦片取代后 SHALL 不再进入指标网格,避免同源数据双重渲染。
