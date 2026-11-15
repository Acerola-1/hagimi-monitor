> 贡献者原始验证记录：由 [xyy386](https://github.com/xyy386) 在 [PR #141](https://github.com/Acerola-1/hagimi-monitor/pull/141) 提供，固定提交 `6405160fb2bf5f65b91c870c2836eb28f1cd24a6`。
> 下列“本机”“本次修改”和测试结果均指贡献者的 M3 与 PR 代码，按原文保留；不是当前整合代码的 M3 验收结果。当前实现差异与后续复测要求见文末。

# M3 / macOS 27 电源拓扑读数验证

验证日期：2026-11-15。设备：MacBook Air M3（Mac15,12），macOS 27.2.1（26B131），Xcode 27.2。
上游基线：`1ed9c3a04957224aba4a5780285a7015613354c1`（1.7.9）。

## 问题与修复范围

原版 `Energy Model / CPU Energy`、`ANE` 在连续采样中不增长，`GPU Energy` 正常增长。
本机当前启动镜像的 `AppleT8122CLPC` 报告表含独立的累计 nJ 计数：

| 分项 | 完整报告 ID | 换算 |
| --- | --- | --- |
| CPU | `0x0000001054b51c99` | 相邻计数差 × 1e-9 / 实际间隔秒数 |
| ANE | `0x00000018960afe2f` | 相邻计数差 × 1e-9 / 实际间隔秒数 |

映射和描述符布局参考 [macmon](https://github.com/vladkens/macmon/blob/6ebbd71c2930f1b9a25a68eaf857dfd134ade606/src/clpc.rs)，并与本机报告表核对。
只在 macOS 主版本为 27、驱动标识为 `com.apple.driver.AppleT8122CLPC` 时使用。
启动时确定来源，缺报时清除差分基线；不会单帧切回冻结或批量更新的旧计数。
未知驱动、其他系统主版本或订阅建立失败时保留原路径。整机和 GPU 来源不变。

## 生产采样代码的本机负载验证

独立探针直接编译本次修改的 `IOReportPowerSampler`、`CLPCEnergyChannels` 及其既有依赖，未复制采样算法。
不使用 sudo 或私有 entitlement。CPU 负载为 4 个短时 `yes` 进程；ANE 使用明确选择 Neural Engine 设备的
`VNGenerateImageFeaturePrintRequest`，负载结束后回收子进程。

| 阶段 | 样本数 | CPU 中位数（W） | ANE 中位数（W） | ANE 峰值（W） |
| --- | ---: | ---: | ---: | ---: |
| 日常背景 | 5 | 1.537 | 0 | 0 |
| CPU 负载 | 8 | 14.116 | 0 | 0 |
| CPU 负载后 | 5 | 1.863 | 0 | 0 |
| ANE 负载（含启动过程） | 16 | 2.343 | 0.841 | 1.203 |
| ANE 负载后 | 5 | 1.685 | 0 | 0 |

39 个样本中 GPU 均有读数，屏幕均按缺失返回。此实验验证了读数与负载的响应及恢复，
尚未通过 `powermetrics` 或外部功率计进行绝对精度校准，也未在其他芯片上验证本次路径。

## 屏幕为何仍显示缺失

用实时亮度接口确认了低—高—低对照。三档整机功耗中位数分别为：

| 实际亮度 | 整机功耗（W） | DCP power / instant_energy | SMC PBLR |
| --- | ---: | --- | --- |
| 20.8% | 5.723 | 0 / 0 | 0 |
| 100% | 11.478 | 0 / 0 | 0 |
| 24.1% | 6.442 | 0 / 0 | 0 |

`Energy Model / DISP`、`DISPEXT` 也未增长；背光报告的电流字段停留在旧值。
SMC 电压/电流键、CLPC 报告表、HID 传感器与显示服务排查均未找到可靠的独立屏幕瓦数来源。
因此，M3/macOS 27 的 DCP 零增量改为 `nil`，界面保留“屏幕”一格和 `--`，并提供中英文缺失说明。
未将整机差值或亮度估算冒充屏幕绝对功耗；该处理也不宣称其他机型的有效零读数有问题。

## 构建与自动测试

- Direct Debug 构建及最终针对性复测通过：39 项测试，覆盖采样、电池读数、拓扑布局、存储生命周期与排行门控。
- Direct Release、App Store Release 构建通过。App Store 产物不链接 libIOReport；Direct 产物包含 macmon 的 MIT 许可文件。
- 中英文 × 浅深色拓扑已渲染检查，保持原有五项排列，缺失屏幕与空闲 ANE 的 `0.0 W` 均可区分。
- 首次完整单元测试：993 通过、3 失败、2 跳过。失败为两项 `UXAcceptanceRenderingTests` 和统计存储生命周期用例。
- 排除上述两项报表渲染测试后复测：993 通过、1 失败、2 跳过；此次失败为排行预加载的异步时序断言。
- 两项报表渲染失败在未修改的上游基线上复现；统计存储及排行门控两个测试套件在上游单独复测均通过，
  在修复分支的最终针对性复测中也通过。保留这些全量运行失败记录，不将完整测试报告为全部通过。

本地构建使用临时 Ad Hoc 签名：`CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual`。
最终 Debug 复测另使用 `ENABLE_DEBUG_DYLIB=NO`；没有修改仓库的签名配置或用户的全局 Xcode 配置。


## 当前实现的吸收范围与差异

- 当前基线为 `a6c27e9600181980821bd50aae15bd8241bd7efb` 的电源遥测框架，保留 `PowerReading`、完整身份/单位/成员校验、动态准入、独立来源选择、限频订阅恢复和补报保护；不另接入原 PR 的 `CLPCEnergyChannels` / `IOReportCounterRate`。
- CPU/ANE 的 M3 完整报告 ID 与上文相同。生产订阅改为通过 `CLPCPowerChannels.descriptors` 构造，使测试可验证真实使用的描述符和平台门控；已知其他驱动仍沿现有映射处理，不收窄为仅 M3。
- 已吸收描述符、nJ/实际间隔换算、缺失屏幕与空闲 ANE 同屏的布局回归。持续零屏幕的测试使用合成计数，不将上文中位数还原或冒充 39 份原始样本。
- 活动内屏沿当前有界区间策略：无有效能量增量时显示缺失；不新增机型特判，也不根据亮度或整机差值估算屏幕瓦数。缺失原因沿现有中英 `PowerReading` 状态说明，避免重复提示入口。
- ANE 零值不直接照搬原 PR。带有效源时间戳的 CLPC 在当前代次内通过正增量准入后，允许时间戳前进、计数不变的健康零。无源时间戳的 CLPC 继续要求连续正增量，空闲保持暂缺/未验证；计数重新增长的首份补报只重建基线。
- 原 PR 未记录 M3 CLPC 的原始源时间戳，故本记录只能支持映射与负载响应，不能单凭空闲零值决定当前无时间戳策略是否可以放宽。保留“启动即零/后负载回零”的显示差异，等待同机原始报告证据。
- 电池健康度、整机/输入/电池流向、IOPS 失败隔离继续采用本地实现，不从该 PR 回退。

## 整合版的同机复测

复用 `scripts/validation/power-topology-probe.swift` 文件顶部的编译命令，输出到 `tmp/power-topology-audit/probe`。例如：

```bash
mkdir -p tmp/power-topology-audit
tmp/power-topology-audit/probe 120 1 > tmp/power-topology-audit/m3-integrated-raw.jsonl
PRODUCTION_ONLY=1 tmp/power-topology-audit/probe 120 1 > tmp/power-topology-audit/m3-integrated-production.jsonl
```

第一轮除生产结果外，记录实际 CLPC 请求/返回的完整 driver/channel/format/unit、累计 counter 和 `sourceTimestampTicks`；第二轮关闭额外诊断订阅，排除其影响。源码编译命令已在探针中给出，两个运行命令均需先完成编译。

由具备同机硬件的验证者分别记录以下场景及开始/结束时刻：

1. 日常背景 → 4 个短时 CPU worker → 负载结束；确认 CPU 来源、响应和恢复，不要求重现上文具体瓦数。
2. 明确使用 Neural Engine 的负载 → 结束后空闲；同时保留 ANE 原始 counter/源时间戳与生产状态，区分计数健康零、无时间戳和冻结。既有 PR 仅记录了负载方法；未提交可复跑的 ANE 负载脚本。
3. 低 → 高 → 低亮度；记录实际亮度。活动屏持续零计数时，生产值应保持缺失。
4. 真睡眠/唤醒、合盖/外屏变化；长间隔和恢复后的首份读数应预热，不产生累计补报尖峰。

提交运行版本/芯片/系统与两轮完整 JSONL，并检查实际面板及中英缺失提示。当前整合尚未完成上述 M3 同机、ANE 负载、真实睡眠及绝对精度验收；原 PR 的构建和测试结果不替代整合版结果。

本地吸收后的构建、定向测试与 M4 探针结果见 [2026-11-15 整合验证记录](reviews/2026-11-15-pr141-integration.md)。
