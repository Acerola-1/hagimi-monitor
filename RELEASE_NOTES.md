## 更新内容

## 更新内容

### 中文

#### 新功能

- 面板长按拖动排序：所有模块行与指标格支持长按拖动换位，拖起时浮起预览、落点实时归位；右键（触控板双指轻点）呼出菜单可上下左右逐格移动，并支持一键恢复模块指标默认顺序
- CPU 核心拓扑自适应识别：按 IORegistry 簇字母归类核心，M5 Pro/Max 等三类核芯片自动呈现超核/性能核/能效核 S/P/E 三组拆分，其余机型维持 P/E 两组视图

#### 优化与体验

- 三组核型并存的圆环配色：超核沿用强调红、性能核改用冷蓝、能效核保持绿色，明暗主题分别调校

感谢 @singularitti 在 #115 提出面板模块排序的功能建议，本版本已引入该能力。

### English

#### New Features

- Panel long-press reordering: every module row and metric cell can be reordered by long-press drag, with a floating preview while dragging and live drop placement. Right-click (two-finger click on trackpads) opens a menu to move items step by step in any direction, with one click to restore the default metric order.
- Adaptive CPU core topology recognition: cores are grouped by IORegistry cluster letters, so chips with three core types (M5 Pro/Max and later) automatically show the Super / Performance / Efficiency (S/P/E) split, while other models keep the P/E view.

#### Improvements

- New ring color scheme for three core groups: super cores keep the accent red, performance cores switch to a cold blue, and efficiency cores stay green, tuned separately for light and dark themes.

Thanks to @singularitti for proposing panel module reordering in #115 — this release ships exactly that.

