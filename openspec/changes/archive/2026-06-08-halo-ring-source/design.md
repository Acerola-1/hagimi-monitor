## Context

当前菜单栏圆环（Halo Ring）数据流：

```
MonitorStore.combinedComputeLoad (硬编码 cpu*0.6 + gpu*0.4)
  → displayedComputeLoad (平滑过渡)
    → MenuBarComputeRingIcon.image(load:)
      → 内部根据 load 值计算颜色等级 (idle/working/busy/stressed)
```

需要改为可配置数据源，且内存模式下颜色逻辑不同。

## Goals / Non-Goals

**Goals:**
- 用户可选择圆环监测项目：综合/CPU/GPU/内存
- 内存模式下圆环颜色按系统内存压力等级显示
- 设置持久化，重启后保持用户选择

**Non-Goals:**
- 不改变圆环的视觉样式（弧度、动画、尺寸）
- 不改变 CPU/GPU/综合模式下的颜色阈值逻辑
- 不支持自定义权重（如 CPU 70% + GPU 30%）

## Decisions

### D1: 内存压力等级传递方式

**选择：在 `MonitorModule` 新增 `pressure` 枚举属性**

备选方案：
- A) 解析 metrics 中的"压力"文字 → 脆弱，依赖中文匹配
- B) 新增 `pressure` 属性 → 类型安全，只影响内存模块

理由：B 方案代码更清晰，不改模型结构（只加一个可选属性），类型安全避免文字解析错误。

### D2: 颜色等级计算位置

**选择：`MonitorStore` 计算颜色等级，传给圆环**

备选方案：
- A) 圆环内部根据 load + source 计算 → 需要圆环知道 source，耦合增加
- B) Store 计算好颜色等级，圆环只负责绘制 → 解耦，圆环不关心数据来源

理由：B 方案让圆环保持纯绘制职责，Store 负责数据逻辑。

### D3: 设置 UI 位置

**选择：常规设置中新增"负载环" section**

放在"外观" section 下方，与主题/配色同级，作为外观配置的一部分。

## Risks / Trade-offs

- **内存压力等级获取失败** → 显示 working 浅绿作为兜底，不影响圆环弧度显示
- **用户切换数据源时圆环突变** → 已有平滑过渡机制 (`displayedComputeLoad`)，无需额外处理
