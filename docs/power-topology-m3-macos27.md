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
