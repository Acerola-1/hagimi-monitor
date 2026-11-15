# PR #141 的本地吸收与验证

日期：2026-11-15。基线分支 `dev`，HEAD `a6c27e9600181980821bd50aae15bd8241bd7efb`。
贡献者 PR：[xyy386 / #141](https://github.com/Acerola-1/hagimi-monitor/pull/141)，固定提交 `6405160fb2bf5f65b91c870c2836eb28f1cd24a6`。

## 已完成的吸收

1. 保留 [贡献者 M3 验证记录](../power-topology-m3-macos27.md) 原文，增加来源、固定提交及“原 PR 结果/整合版结果”边界，记录当前策略差异和同机复测步骤。
2. 生产 CLPC 描述符从订阅函数提取到 `CLPCPowerChannels.descriptors`，使用现有 allowlist、完整报告 ID、格式、单位与可变字典。没有另接入原 PR 的采样器，也未改变来源选择、动态准入、零值、补报或恢复算法。
3. 从贡献者测试适配了真实生产描述符的 M3 身份/格式/nJ 单位和未知版本/驱动门控测试、nJ 在非整秒间隔的换算测试、缺失屏幕与零值 ANE 同屏的布局回归；增加了持续零活动屏的缺失状态回归。共增加 6 个测试定义，其中系统版本门控有 2 个参数实例。
4. 既有诊断探针增加实际 CLPC 请求身份、返回计数和原始 `sourceTimestampTicks`，复用生产订阅与解析。`PRODUCTION_ONLY=1` 仍关闭额外诊断订阅。该变化仅属于手工运行的验证脚本，不增加应用轮询。
5. 新增 [第三方与贡献者说明](../../THIRD-PARTY-NOTICES.md)，复用现有 Direct 产物内的 macmon MIT 许可，没有增加重复资源。

## 保留的本地业务规则

- 有效源时间戳在前进、且同订阅代次已通过正增量准入的 ANE，可显示健康零。
- 无源时间戳的 CLPC 只以连续正增量出值；零值保持缺失，恢复首份增长丢弃补报。原 PR 的 M3 报告未给出原始源时间戳，因此本次没有放宽该规则。
- 屏幕仍按活动状态与有界能量区间判定，不加入 M3 品牌字符串特判，不根据亮度或整机差值推算瓦数。
- 电池健康度、输入/负载/电池流向解算、IOPS 失败的消费者隔离及统计过滤沿用本地实现。
- OpenSpec 的 `power-telemetry` 行为契约未改变；已归档的 `harden-power-telemetry` 硬件验收缺口不因引用贡献者记录而勾选完成。本次为该实现补充验证，没有另建行为提案。

## 本轮自动验证

- `git diff --check` 通过。
- `HagimiMonitor` Debug 构建通过；`HagimiMonitorDirect` Debug 随定向测试构建通过。
- 定向测试：72 个测试定义全部通过、0 失败、0 跳过；动态参数展开后设备统计为 73 次通过。已检查 xcresult，6 个新增测试均实际执行。
- 覆盖套件：`PowerChannelTests`、`PowerTelemetryTests`、`PowerPanelLayoutTests`、`BatterySamplerTests`、`BatteryHealthProbeTests`、`PowerReadingsTests`、`PowerConsumerTests`、`MetricWidthAuditTests`、`SamplingGateStateTests`。
- 明暗拓扑夹具截图已检查：屏幕 `--` 与 ANE `0.0 W` 同屏布局正常。它们是注入夹具，不是 M3 实机或实际悬停验证；本次没有改变产品视图实现。
- 检查构建产物与 Debug 动态库依赖：App Store 不链接 `libIOReport`，Direct 链接且资源内存在 `macmon-LICENSE.txt`。
- 结果包含已有电池/消费者测试的 QoS 等待运行时警告；测试无失败。本轮未重跑全量、Release 或绝对精度标定。

执行命令：

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-appstore build

xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct \
  -resultBundlePath tmp/pr141-comparison/integrated-tests.xcresult \
  -only-testing:HagimiMonitorTests/PowerChannelTests \
  -only-testing:HagimiMonitorTests/PowerTelemetryTests \
  -only-testing:HagimiMonitorTests/PowerPanelLayoutTests \
  -only-testing:HagimiMonitorTests/BatterySamplerTests \
  -only-testing:HagimiMonitorTests/BatteryHealthProbeTests \
  -only-testing:HagimiMonitorTests/PowerReadingsTests \
  -only-testing:HagimiMonitorTests/PowerConsumerTests \
  -only-testing:HagimiMonitorTests/MetricWidthAuditTests \
  -only-testing:HagimiMonitorTests/SamplingGateStateTests test
```

日志：`tmp/pr141-comparison/integrated-tests.log`、`integrated-appstore-build.log`、`test-summary.json`；结果包见上方路径。重复运行时需指定新的结果包路径。
截图：`tmp/power-ui-review/topology-light.png`、`topology-dark.png`。

## 本轮 M4 只读采样

环境：Apple M4 / Mac16,1 / macOS 27.3（26C5035r）。探针按文件顶部命令重新编译；先记录原始报告，再用 `PRODUCTION_ONLY=1` 排除额外诊断订阅。

- 两轮各 12 帧，间隔 1 秒；CPU 各有 9 帧有效值，GPU 各有 11 帧，屏幕各有 10 帧；其余为启动预热。
- 原始轮实际解码 CLPC 24 条记录，每帧请求/返回均为 2 条，源时间戳全为 0。CPU 原始计数可增长；两轮空闲 ANE 均无生产功率值，符合当前保守策略。
- 两轮背景负载不同（首轮同时存在构建/测试），瓦数不用于彼此精度比较，也未在本轮施加受控 CPU/ANE 负载。
- 原始与纯生产数据分别为 `tmp/pr141-comparison/integrated-M4-raw.jsonl`、`integrated-M4-production.jsonl`。

## 工作区与交付边界

任务开始时已有的四个面板文件差异已逐字节核对保留。本轮期间另外出现的键盘焦点源文件/测试属于并行工作，未修改或纳入本次吸收范围。
本轮验证未合并或关闭远端 PR，也未发送 GitHub 消息；Git 提交和推送状态以仓库记录为准。

整合版仍待贡献者同一台 M3 的 CPU/ANE 负载与空闲、原始源时间戳、真实睡眠/合盖/外屏恢复及实际面板复测；原 PR 的 39 样本、构建与测试通过记录不能替代这一验收。
