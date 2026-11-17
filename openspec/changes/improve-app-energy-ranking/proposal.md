# 应用能耗排行：保留需求与调查证据

> 状态：**暂缓实施（用户于 2026-11-17 明确要求）**。本 change 保存需求和后续调查路线，不表示已选定数据源或获准继续实施。恢复前先读 [交接记录](reference/handoff.md)。

## Why

用户希望电源模块帮助识别「哪个应用更耗电」，而现有榜单只按进程 CPU 能量差分得到的近期平滑功率排序，不能代表完整应用能耗。`powermetrics` 虽然提供系统评分，但本次 M4 实测中 GPU 负载评分偏低，尚不足以证明可用于目标排行。

## What Changes

- 保留应用级能耗排行的目标，区分 CPU 功率、GPU 活动、综合能耗影响评分与累计耗能；不把 CPU-only 榜单当作完整应用排行。
- 恢复工作后先验证候选数据源的实际覆盖范围、GPU 贡献与系统工具的一致性，再选择方案；`powermetrics` 只是候选，不是已定方案。
- 记录应用/辅助进程归属、短命进程、退出与 PID 复用、缺失数据及采样开销的验收要求。
- 保持 App Store 与官网渠道的能力边界；本次临时采样授权不扩展为安装持久后台服务的授权。
- 当前只保存规划、证据和交接文档，不修改产品、不继续负载实验、不安装服务。

## Capabilities

### New Capabilities

- `app-energy-ranking`：应用能耗排行的指标口径、覆盖证据、应用归属、有效性及渠道边界。

### Modified Capabilities

无。现有 `power-telemetry` 管理分项功率；`top-process-rows` 管理五类资源 TOP 行。新增能力单独描述应用能耗排行，不以本提案放宽既有分项采样的权限约束。

## Impact

未来可能涉及 `ProcessEnergySampler`、`ProcessEnergyShare`、`ProcessGrouping`、电源模块采样与排行展示；最终文件范围取决于调查结论。管理员采样助手、持久安装和权限交互均未选定或实现。现有实测只覆盖 M4 / macOS 27.3，不能代替其他机型验收。

实测结论见 [调查报告](../../../docs/reviews/2026-11-17-powermetrics-feasibility.md)，原始数据位置及恢复步骤见 [交接记录](reference/handoff.md)。
