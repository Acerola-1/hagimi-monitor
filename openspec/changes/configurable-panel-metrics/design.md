## Context

当前主面板各模块展开后显示的详细指标是硬编码在视图中的：
- CPU: 系统、用户、闲置、启动时间
- GPU: GPU内存、已分配、渲染、分块
- 内存: 已用、压力、交换已用、总量
- 存储: 已用、可用、总量（通过 StorageVolumeDetailList 展示）
- 网络: IP 地址
- 电池: 充电功率、健康度、循环数、温度（电池供电时隐藏充电功率）

设置页面 `ModuleSettingsView` 中已有「检测项目」区域，使用 `MetricSelectionRow` 展示可勾选项，最多选4项。但当前 `MonitorKind.availableMetrics` 每个 kind 只有1个占位项，未与实际指标关联。

## Goals / Non-Goals

**Goals:**
- 将各模块展开区域的实际指标提取为可配置项，充实 `availableMetrics`
- 设置页面「检测项目」显示真正的多选列表，默认全勾选
- 主面板展开时按 `enabledMetrics` 过滤显示
- 保持现有 UI 布局和交互不变

**Non-Goals:**
- 不修改指标数据来源（Sampler 逻辑不变）
- 不修改模块可见性设置
- 不修改最多4项的限制
- 不新增指标，只将现有指标可配置化

## Decisions

**Decision: 使用 metric name 作为 enabledMetrics 的 key**
- `availableMetrics` 的 `id` 必须与 Sampler 返回的 `MonitorMetric.name` 完全匹配
- 这样视图层过滤时可以直接用 `metrics.filter { enabledNames.contains($0.name) }`
- 替代方案：用独立 ID 映射，但会增加复杂度且无必要

**Decision: 电池「充电功率」的动态隐藏保留在视图层**
- 电池供电时充电功率值为 "--"，视图层过滤掉空值指标是现有行为
- 不将此逻辑下沉到配置层，因为这不是用户偏好而是数据可用性问题

**Decision: 存储模块使用 StorageVolumeDetailList 的特殊展示**
- 存储展开后显示的是卷列表（系统盘+外置盘），不是简单的指标网格
- 存储的 `availableMetrics` 仅用于设置页面的勾选，面板渲染保持现有 StorageVolumeDetailList 逻辑
- 如果用户取消勾选存储指标，不影响卷列表展示（存储的展开内容本质不同）

**Decision: 默认全选而非部分选中**
- 用户要求「把当前有的都做成默认展示项目」
- `defaultMetricIds` 改为返回所有 `availableMetrics` 的 id

## Risks / Trade-offs

- **[Risk]** `availableMetrics` 的 `id` 与 Sampler 的 `MonitorMetric.name` 不一致导致过滤失败
  → **Mitigation**: 统一使用中文名称作为 id，与现有 Sampler 输出对齐；代码审查时逐项核对

- **[Risk]** 用户全部取消勾选后展开区域为空
  → **Mitigation**: 接受此行为，用户可以通过勾选恢复；或者保留至少1项不可取消（暂不实现）

- **[Risk]** 网络模块目前展开只显示 IP 地址，上传/下载在主行已显示
  → **Mitigation**: 将上传/下载也加入可配置指标，展开时显示（与现有主行不冲突）
