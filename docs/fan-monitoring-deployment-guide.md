# 风扇监控功能 — 部署说明与用户操作手册

## 1. 功能概述

HagimiMonitor 风扇监控功能提供以下能力:

| 能力 | 说明 |
|------|------|
| **风扇转速采样** | 通过 SMC (AppleSMC) 读取 `FNum`/`F0Ac`/`F0Mn`/`F0Mx` 键,2 秒周期采样所有风扇的当前 RPM 及 min/max 范围 |
| **菜单栏指标** | 在菜单栏显示当前最大风扇 RPM(4 字符右对齐,>9999 cap),可与其他指标混排 |
| **面板详情行** | 面板中 GPU 与内存之间插入风扇行,展开后列出所有风扇(name / RPM / min-max 比例条 / 状态指示点) |
| **健康状态监控** | 基于 RPM 自动判断:normal(正常) / warning(≥85% maxRPM) / fault(停转/传感器异常) / unknown(数据不足) |
| **异常告警** | 状态恶化时发送 macOS 系统通知(fault 用紧急声音,warning 用默认声音),恢复正常时发恢复通知 |
| **无风扇机型适配** | MacBook Air 等无风扇机型自动隐藏所有风扇相关 UI,不显示空行 |

## 2. 构建与部署

### 2.1 环境要求

- macOS 15.0+(Apple Silicon)
- Xcode 16+(当前开发使用 Xcode 27 / macOS 26.5 SDK)
- Swift Package 依赖:Sparkle 2.9.4、KeyboardShortcuts 2.4.0

### 2.2 构建命令

```bash
# Direct 分发版(禁用沙盒,含显示控制)
./launch.sh dev direct

# App Store 沙盒版
./launch.sh dev appstore

# 构建并打包到 build/ 目录
./launch.sh -p
```

### 2.3 验证构建成功

构建成功后,应用自动启动,菜单栏出现猫咪图标。构建产物路径:
```
/tmp/hagimi-builds/dev/HagimiMonitor.app
```

## 3. 用户操作指南

### 3.1 查看风扇转速

1. **菜单栏**:点击菜单栏猫咪图标展开面板
2. **面板风扇行**:在 GPU 行下方找到"Fan"行,显示当前最大 RPM
3. **展开详情**:点击风扇行,展开显示所有风扇列表:
   - 每行:风扇名称 + 当前 RPM + min-max 比例条 + 状态指示点
   - 状态指示点颜色:🟢正常 / 🟠警告 / 🔴故障 / ⚪未知

### 3.2 在菜单栏显示风扇 RPM

1. 打开设置(菜单栏图标 → 设置,或 ⌘,)
2. 在"通用"设置页找到"菜单栏指标"
3. 勾选"风扇转速"(仅在有风扇的机型上可见)
4. 菜单栏将显示当前最大风扇 RPM(4 字符右对齐)

> **注意**:MacBook Air 等无风扇机型不会出现此选项。

### 3.3 告警通知

- 首次启动时,系统会弹出通知授权对话框,请点击"允许"
- 风扇停转(RPM=0)或传感器异常时:发送**紧急通知**(带 Critical 声音)
- 风扇接近最大转速(≥85% maxRPM)时:发送**警告通知**
- 风扇恢复正常时:发送**恢复通知**
- 通知去重:同一状态级别不重复发送,仅状态变化时触发

### 3.4 通知未收到?

1. 打开"系统设置" → "通知"
2. 找到 HagimiMonitor,确保"允许通知"已开启
3. 确保"横幅"或"提醒"样式已选择
4. 确保声音已开启

## 4. 状态判断规则

| 状态 | 条件 | 颜色 | 通知 |
|------|------|------|------|
| `normal` | RPM > 0 且 < 85% maxRPM | 绿色 | 无 |
| `warning` | RPM ≥ 85% maxRPM | 橙色 | 警告通知(默认声音) |
| `fault` | RPM = 0(停转)或 RPM > maxRPM(传感器异常) | 红色 | 紧急通知(Critical 声音) |
| `unknown` | maxRPM ≤ 0(SMC 未提供上限) | 灰色 | 无 |

> 多风扇场景下,整体状态取所有风扇中最差值。

## 5. 技术架构

### 5.1 文件清单

| 文件 | 职责 |
|------|------|
| `Samplers/SMC.swift` | SMC 底层读取:fanCount() / maxFanRPM() / allFans() |
| `Samplers/FanSampler.swift` | 风扇采样器:2s 周期采样,发布 fans + status |
| `Samplers/FanAlertService.swift` | 告警服务:订阅 status,发 macOS 通知 |
| `MonitorModels.swift` | FanInfo / FanStatus / MonitorStore fanAvailable/fanStatus |
| `MenuBarDisplayModels.swift` | fanSpeed 指标 case + fanRPM formatter + userSelectableCases(hasFan:) |
| `MenuBarStatusLabel.swift` | 菜单栏风扇指标渲染分支 |
| `MonitorPanelView.swift` | 面板风扇行 + FanList 展开视图(含状态着色) |
| `Views/Settings/GeneralSettingsView.swift` | 设置选单联动 hasFan |
| `Localizable.xcstrings` | 中英文本地化(20+ 条风扇相关 string) |
| `HagimiMonitorTests/FanMonitorTests.swift` | 35 个单元测试 |

### 5.2 采样生命周期

```
MonitorStore.init()
  ├── FanSampler.start()        ← 常驻启动,不随面板显隐
  ├── FanAlertService.attach()  ← 订阅 status 变化
  └── 每 2s:
        SMCReader.allFans()
          → FanInfo[]
            → FanInfo.status (per fan)
              → overallStatus (worst)
                → FanAlertService (notify if upgraded)
                → MonitorStore.fans / fanStatus (@Published)
                  → Panel FanList (status-colored UI)
```

### 5.3 SMC 读取协议

```
protocol FanSMCReading: AnyObject
  func fanCount() -> Int?
  func allFans() -> [(id, currentRPM, minRPM, maxRPM)]

SMCReader: FanSMCReading   ← 生产实现
MockFanSMCReader            ← 测试 mock
```

## 6. 故障排查

### 6.1 面板不显示风扇行

- **原因**:该机型无风扇(MacBook Air / 12" MacBook)
- **验证**:在"终端"运行 `sudo powermetrics --samplers smc | grep -i fan`,无输出 = 无风扇
- **预期行为**:无风扇机型不显示风扇行是正确行为,非 Bug

### 6.2 风扇 RPM 显示为 0

- **可能原因**:SMC 读取失败或风扇确实停转(睡眠唤醒瞬间)
- **排查**:连续观察 5-10 秒,RPM 恢复 = 瞬时读取失败;持续 0 = 硬件问题,系统会发 fault 告警

### 6.3 通知不弹出

- 检查系统设置 → 通知 → HagimiMonitor 是否允许
- 检查勿扰模式是否开启
- 查看日志:`log show --predicate 'subsystem == "com.acerola.hagimi-monitor"' --last 5m`
