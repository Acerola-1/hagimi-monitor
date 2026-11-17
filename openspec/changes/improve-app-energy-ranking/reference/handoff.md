# 恢复入口：应用能耗排行

状态：**暂缓实施**。2026-11-17 用户要求先搁置排行修复，保存本轮需求与证据，以后可能重新开启。现在只完成记录和归档，不继续实验、不修改产品、不安装持久服务。以后只有用户明确恢复时才继续。

## 用户实际想解决什么

- 电源模块应该帮助识别哪个应用更耗电，而不仅仅是 CPU 使用率或 CPU 单项功率。
- 用户关心 macOS 电池菜单“使用大量能耗”的数据是否可取得、能否采用官方依据，及应用 GPU 能耗是否能计入。
- 用户要求评估现有 CPU 功率换算是否合理，以及在 CPU/GPU 集成的 Apple 芯片上怎样区分分项与应用归因。
- 用户同意先收集证据、再决定下一步；没有要求把任意官方评分直接上线。
- 当前没有决定最终数据源、管理员助手、长期后台服务、即时/历史排行时间窗口，也未确定全机型支持范围。

## 已知结论与不要重复的误判

- 当前公式读取进程累计 CPU 能量，做能量差分 / 时间得到 W，按应用归属合并后平滑。这不是直接用 CPU 占用率乘固定瓦数，但也不是完整应用功耗。
- 审查发现退出后短暂保留、PID 复用平滑历史及短命进程遗漏等问题；具体修复尚未实施。
- 已有部分应用 GPU 使用时间采样，不能概括为“GPU 信息完全拿不到”；使用时间不等于能量。
- powermetrics 在本机可以授权运行并输出评分及应用进程组 GPU 时间，但实测不足以把其评分直接当作完整应用能耗排行。
- 115 帧、约 236 秒；M4 / macOS 27.3。独立 CPU 应用组评分约 637.78，独立 GPU 应用组评分约 16.61；后者 GPU 时间约 638.2 ms/s、同期整颗 GPU 功率约 5.746 W。
- 不能把整颗 GPU 的 5.746 W 全归给该应用，不能断言所有系统完全忽略 GPU，不能宣称评分与活动监视器或电池菜单同口径。
- 当前两秒 tasks/cpu_power/gpu_power 配置约占一个核心 2.7%，RSS 约 9.5 MiB。不是全机 CPU 的 2.7%，也不是电池占比；未代表仅 tasks 或低频方案。
- 本轮只有临时采样授权；两个限时采样正常退出，无遗留工作负载或安装服务。临时应用和二进制已清理。

## 文件入口

- 本提案：`openspec/changes/improve-app-energy-ranking/`。
- [实测报告](../../../../docs/reviews/2026-11-17-powermetrics-feasibility.md)。
- [可公开的数值与校验摘要](evidence-summary.json)；该摘要不含其他应用的进程明细。
- **本机长期原始档案**：`/Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/`。
- 档案的 `evidence/` 含两轮压缩 plist、manifest、analysis、工作负载源文件、复算脚本及本机工具手册；`FILE-MANIFEST.json` 校验每份文件。
- 档案的 `handoff-snapshot/` 保存当前提案、报告及恢复说明的快照；独立压缩包与 `ARCHIVE-SHA256.txt` 位于同一目录。
- 原 `tmp/powermetrics-evidence-2026-11-16/` 已在复制并校验后移除；历史 manifest 中的 tmp 路径保留为当时执行记录，不再是当前存储位置。

原始样本含本机进程信息，仅在本机档案保存，不放进仓库。迁出 tmp 可避免临时目录清理丢失；本机档案和压缩包并不等于远程备份。用户于 2026-11-17 要求将本次提案、交接记录和报告保存为本地 Git 提交，原始进程数据仍仅留本机；本次不推送。

## 再次开启时怎样继续

用户可以说：**“继续 improve-app-energy-ranking，先看交接记录和实测证据。”**

1. 先读本文件、proposal/design/tasks 和实测报告，核对原始档案清单及压缩数据 SHA-256，不重新凭手册假设评分覆盖完整。
2. 重新检查当前分支、工作区、产品源码、系统版本与权限状态；这些会变化。历史测试不能替代当前验证。
3. 从 tasks.md 的第 2 组开始：优先核实独立 GPU 负载评分与活动监视器的关系，再讨论其余覆盖、开销和产品方案。
4. 不沿用临时授权去静默安装服务；产品权限及最终实施按新的明确指令处理。

不需要管理员权限即可复算历史数据：

```sh
python3 /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/analyze.py
python3 /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/analyze.py /Users/acerola/Workspace/reports/hagimi-monitor/2026-11-17-app-energy-ranking/evidence/isolated
```
