# powermetrics 应用能耗评分实测

结论：已确认可以授权调用、解析并取得进程/应用进程组评分，但本机实测不支持直接把它作为完整的应用能耗排行。独立 Metal 应用产生明显 GPU 活动时，评分仍然很低；需要先查明评分对 GPU 的覆盖范围。未修改产品实现，未安装后台服务。

## 实验范围与证据

- 本地时间：2026-11-16 23:57 至 2026-11-17 00:03（原始时间戳为 UTC）。
- Apple M4，Mac16,1，32 GiB，macOS 27.3 / 26C5035r。开始时使用电池供电，电量 52%。
- 用户通过 macOS 系统窗口授权运行两次限时采样。两个授权调用均正常退出；采样结束后确认无遗留负载或 powermetrics 进程。
- 两轮使用相同配置：`--samplers tasks,cpu_power,gpu_power --show-process-energy --show-process-coalition -i 2000 -f plist`，分别限制 70、45 帧。
- 共取得 115 帧，覆盖累计约 236 秒采样窗口；以 NUL 分隔的 plist 全部可解析，无残缺记录。
- 第一轮从命令行启动负载，进程归入调用方 Codex 的进程组；第二轮通过 LaunchServices 启动两个独立测试应用，确认它们分别进入独立进程组，排除第一轮的混组干扰。
- 采样时保留原有应用运行。基线表示没有本实验负载，并非整机完全空闲。未控制所有后台活动，不能把整机功率差额等同于测试应用的准确瓦数。

原始输出、配置、工作负载源文件、分析脚本和汇总已从临时目录迁入本机长期档案 `/Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/`，不纳入产品或仓库。原始 plist 使用 gzip 无损压缩；`evidence-summary.json` 记录解压后 SHA-256，档案父目录的 `FILE-MANIFEST.json` 校验全部证据文件。原始数据包含本机进程信息，仅保存在本地。

用户于 2026-11-17 要求暂缓排行修复；需求、后续任务和恢复入口保存在 [OpenSpec 交接记录](../../openspec/changes/improve-app-energy-ranking/reference/handoff.md)。历史执行记录中的 tmp 路径不再是当前档案位置。

## 取得的数据结构

- 每个进程：PID、启动标识、CPU 时间、唤醒、磁盘、网络、`energy_impact`、`energy_impact_per_s` 等。
- 应用进程组（coalition）：组 ID、名称、组内任务、CPU 时间、部分组的 `gputime_ms_per_s`、评分。
- 在这两轮配置和本机系统上，逐进程任务记录未输出 GPU 时间字段；GPU 时间出现在进程组级别。缺失字段不能解释成 GPU 使用量为零。
- 系统 CPU/GPU 功率位于 `processor.cpu_power`、`processor.gpu_power`。本报告将工具的 mW 值除以 1000 后以 W 表示。
- 比较评分使用 `energy_impact_per_s`，保持工具原始数值，不假设它与活动监视器的显示刻度相同，也不将其标为 W。

## 独立应用复测结果

每个负载约 20 秒。统计时排除阶段开始后 4 秒和结束前 3 秒，降低启动、退出与两秒采样边界的影响。以下均为保留样本的算术平均值。

CPU 测试应用（PID 48602，独立进程组 36677，7 个样本）：

- CPU 时间 996.1 ms/s，约为一个核心的 99.6%。
- 进程评分 637.82；进程组评分 637.78。
- 同期整颗 CPU 功率 1.818 W、整颗 GPU 功率 0.694 W。

GPU 测试应用（PID 48681，独立进程组 36681，6 个样本）：

- Metal compute 持续提交并等待 GPU 命令完成。LaunchServices 的启动/等待命令返回 0，负载结束后无残留进程；该返回值不等同于直接取得应用本身的退出码。
- CPU 时间 23.38 ms/s，约为一个核心的 2.34%。
- 进程组 GPU 时间 638.2 ms/s，约为墙钟时间的 63.8%；这表示累计执行时间比例，不等于 GPU 功率占比或所有执行单元的利用率。
- 进程评分 16.60；进程组评分 16.61。
- 同期整颗 GPU 功率 5.746 W、整颗 CPU 功率 1.165 W。
- 在该应用运行期间另取 19 个 `proc_pid_rusage` CPU 能量读数，形成 18 个有效差分，平均 CPU 功率约 0.0164 W。这仍然只是 CPU 部分。

第一轮也出现相同方向：CPU 负载进程评分约 633.49；GPU 负载进程评分约 16.34，而 GPU 域功率约 6.163 W。第一轮的应用组混有调用方活动，因此不使用该轮组评分作独立应用比较。

观察：GPU 活动和 GPU 域功率确实升高，但该应用的进程评分与独立组评分均远低于 CPU 测试应用。分组修正没有消除现象。

判断边界：这足以否定“取得官方评分后，就可以直接认为已完整覆盖 GPU 并可靠排序”的前提；不足以证明评分在所有系统上完全忽略 GPU，也不能据此给出其内部公式或断言为 macOS 缺陷。尚未与活动监视器和电池菜单逐项对照。

## 采样自身开销

- 第一轮：143.67 秒采样窗口，powermetrics 的记录累计约 3.919 CPU 秒，约占一个核心的 2.73%。
- 第二轮：92.33 秒采样窗口，累计约 2.547 CPU 秒，约占一个核心的 2.76%。
- 第二轮通过外部 `ps` 取得 45 个内存观测，RSS 平均约 9.52 MiB，最大约 9.70 MiB。
- CPU 占比以一个核心为 100% 计算，不是全机 10 核的 2.7%，也不是电池耗电占比。
- 开销只代表上述两秒采样和所选 sampler 的组合；尚未测仅 tasks、降低频率、产品解码/传输以及长期运行的开销。原始输出每帧约数百 KB，持续落盘不可直接照搬为产品方案。
- 第一轮外部内存观测因 `ps` 字段截断没有匹配到采样进程，不作为内存证据；第二轮修正字段顺序后得到上述有效观测。

## 后续决策依据

1. 暂不将现有 CPU 瓦数替换为 powermetrics 综合排行，也不把能耗评分标成瓦数或电池消耗百分比。
2. 先核实 GPU 对评分的贡献范围，并在同一负载下与活动监视器对照；本轮结果不能支持“与系统电池提示同口径”的说法。
3. 若评分覆盖满足目标，再测较低频率与仅 tasks 采样开销、应用/辅助进程归属、短命进程、睡眠恢复及支持的系统/芯片范围。
4. 磁盘、网络、硬件视频编解码、ANE 和长期历史排行均未专项验证。CPU/GPU 实验不能替代这些证据。

## 依据与复算

- 本机 `/usr/bin/powermetrics --help`、`man powermetrics` 的原文已分别保存为 `help.txt`、`manual.txt`。手册称评分是 CPU/GPU/磁盘/网络的粗略代理，且权重与平台有关；本机测量结果需要与该描述一起解读。
- [Apple：活动监视器能耗指标说明](https://support.apple.com/en-euro/guide/activity-monitor/actmntr43697/mac)：能耗影响是相对量，12 小时指标是平均能耗影响。
- [Apple：后台服务授权](https://developer.apple.com/videos/play/wwdc2022/10096/?time=762)：提升权限的 daemon 需要管理员批准。
- [App Store 审核规则](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)：2.4.5(v) 禁止请求提升 root 权限，因此当前调用路径不能直接用于 App Store 渠道。

无需再次授权即可离线复算已采集数据：

```sh
python3 /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/analyze.py
python3 /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/analyze.py /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/isolated
```

临时测试应用及可执行文件已在采样后清理；保留原始证据与源文件。产品源码、设置及后台服务配置均未更改。
