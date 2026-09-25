# game-hud Specification

## Purpose

Defines the game HUD's game identification, auto-display behavior, metric catalog, overlay layout, curve rendering, optional official HUD assistance, and lifecycle management.

## ADDED Requirements

### Requirement: 游戏自动识别
Game HUD SHALL 依据前台应用的 bundle ID 判定是否为游戏候选项，并允许用户手动添加或排除；判定 SHALL NOT 以「使用了 Metal/OpenGL」作为充分条件。

#### Scenario: 自动识别候选游戏
- **WHEN** 前台应用为内置候选名单中的原生 macOS 游戏（含 Steam 原生游戏）
- **THEN** Game HUD 激活并显示悬浮层
- **AND** 判定来源为前台应用的 bundle ID 与候选名单的匹配结果

#### Scenario: 用户手动添加游戏
- **WHEN** 用户在设置中用 bundle ID 添加一个应用
- **THEN** 该应用进入前台时激活 Game HUD

#### Scenario: 用户排除候选游戏
- **WHEN** 用户在设置中排除一个已自动识别的游戏
- **THEN** 该应用进入前台时不激活 Game HUD
- **AND** 排除判定优先于候选名单

#### Scenario: 图形 API 不作为游戏判据
- **WHEN** 前台应用使用 Metal 或 OpenGL 但不在候选名单与用户名单中（如浏览器、视频播放器）
- **THEN** Game HUD 保持隐藏

#### Scenario: 非游戏应用前台
- **WHEN** 前台应用既不在候选名单也不在用户添加列表中，且不在排除列表中
- **THEN** Game HUD 保持隐藏

#### Scenario: 转译与虚拟化环境不承诺识别
- **WHEN** 游戏运行在 CrossOver、Parallels 等转译或虚拟化宿主中
- **THEN** 首版不承诺识别宿主内部的具体游戏
- **AND** 用户可手动添加宿主应用；不显示针对该场景的特殊提示

### Requirement: 显示状态机
Game HUD SHALL 依据匹配游戏的前台状态切换悬浮层显示与隐藏，并保持总开关与实际显示状态可区分。

#### Scenario: 游戏进入前台
- **WHEN** 匹配的游戏应用成为前台应用
- **THEN** Game HUD 显示悬浮层
- **AND** 悬浮层位于游戏所在屏幕的配置角落

#### Scenario: 游戏失去前台
- **WHEN** 匹配的游戏失去前台焦点
- **THEN** Game HUD 隐藏悬浮层
- **AND** 悬浮层窗口不被销毁，仅隐藏

#### Scenario: 游戏退出
- **WHEN** 匹配的游戏完全退出
- **THEN** Game HUD 隐藏悬浮层
- **AND** 保持总开关启用状态，等待下次匹配游戏进入前台

#### Scenario: 总开关启用但无匹配游戏
- **WHEN** 用户启用 Game HUD 总开关但前台应用不是匹配游戏
- **THEN** 不出现悬浮层
- **AND** 该状态与「总开关已启用」在 UI 上可区分

#### Scenario: 多显示器环境
- **WHEN** 存在多个显示器且匹配游戏在非主显示器上
- **THEN** 悬浮层显示在该游戏所在屏幕的配置角落

### Requirement: 监控项目目录
Game HUD SHALL 提供仅包含游戏相关指标的勾选目录；指标来源 SHALL 为既有采样通道的真实读数，且 SHALL NOT 伪造或换算为未采集的数值。

#### Scenario: 目录不含与游戏无关的项目
- **WHEN** 代码访问 Game HUD 的可用指标目录
- **THEN** 目录不包含 IP 地址、SSID、公网 IP、网关延迟、蓝牙设备、电池健康、电池循环次数、电池电压/电流/容量、充电限制、剩余时间与一般电脑信息
- **AND** 目录不包含完整进程表、历史报告与控制按钮

#### Scenario: 候选指标与既有指标 ID 对齐
- **WHEN** 实现者把指标接入 HUD
- **THEN** 每项 SHALL 复用 `MonitorKind.availableMetrics` 中已存在的指标 ID，映射关系见下表
- **AND** SHALL NOT 在 HUD 内新建与既有 ID 同义或近义的指标标识

| HUD 展示项 | 模块 | 指标 ID | 数据性质 |
|---|---|---|---|
| CPU 占用 | `.cpu` | `system` / `user` | 整机聚合 |
| GPU 占用 | `.gpu` | `render` | 整机聚合 |
| 内存占用 | `.memory` | `used` | 整机 |
| 压缩内存 | `.memory` | `compressed` | 整机 |
| Swap 占用 | `.memory` | `swap-used` | 整机 |
| 内存压力 | `.memory` | `pressure` | 整机 |
| 系统功耗 | `.battery` | `power` | 整机遥测，非 CPU/GPU 分项 |
| 热压力 | `.cpu` | `thermal-pressure` | 公开 API，双渠道可用 |
| GPU 内存（驱动聚合） | `.gpu` | `gpu-memory` | 驱动聚合值，非游戏专属显存 |
| GPU 内存分配（驱动聚合） | `.gpu` | `allocated` | 驱动聚合值，非游戏专属显存 |
| CPU 温度 | `.cpu` | `temperature` | 沙盒下取值为空 |
| 分项功耗（CPU/GPU/ANE/屏幕） | `.battery` | `cpu-power` / `gpu-power` / `ane-power` / `display-power` | 仅官网渠道 |

#### Scenario: GPU 内存项的语义标注
- **WHEN** 悬浮层渲染 `gpu-memory` 或 `allocated`
- **THEN** 展示语义 SHALL 为「GPU 驱动聚合内存」，SHALL NOT 标注为「显存容量」「游戏显存占用」或「独立显存」
- **AND** 该限制来自数据源本身：读数为 IOAccelerator 驱动聚合字节数

#### Scenario: 沙盒渠道不出现的项目
- **WHEN** App Store 渠道（沙盒环境）构建指标目录
- **THEN** CPU 温度与分项功耗不出现于目录，也不以灰显或占位形式出现
- **AND** 该过滤 SHALL 依据运行时可读性判定，而不是仅依据编译条件——SMC 代码在两个渠道均被编译，差异来自沙盒运行时的访问拒绝

#### Scenario: 官网渠道追加项目
- **WHEN** 官网渠道（非沙盒）构建指标目录
- **THEN** 在基础目录上追加 CPU 温度与分项功耗
- **AND** 这些项目可被用户勾选

#### Scenario: 本机没有对应硬件的项目
- **WHEN** 某项目在当前硬件上不存在（如无风扇机型的风扇转速）
- **THEN** 该项目不出现在目录中

#### Scenario: 已勾选项目暂时没有读数
- **WHEN** 某已勾选项目在本次采样中取值失败或暂时不可用
- **THEN** 悬浮层保留该行并把值显示为 `—`
- **AND** 不隐藏该项目、不显示假零值、不改变整体布局高度

### Requirement: 悬浮层布局
Game HUD 悬浮层 SHALL 位于配置角落、始终点击穿透且不抢焦点。

#### Scenario: 默认位置
- **WHEN** Game HUD 首次激活
- **THEN** 悬浮层位于游戏所在屏幕的右下角
- **AND** 距屏幕边缘有默认偏移以避免被 Dock 遮挡

#### Scenario: 角落与偏移配置
- **WHEN** 用户在设置中更改角落或偏移量
- **THEN** 悬浮层按新配置移动到对应角落
- **AND** 该配置为全局配置，对所有游戏生效

#### Scenario: 点击穿透
- **WHEN** 悬浮层显示时
- **THEN** 鼠标事件穿透到下层游戏窗口
- **AND** 用户无法点击或拖动悬浮层
- **AND** 悬浮层不成为 key window、不夺取游戏焦点

#### Scenario: 布局内容
- **WHEN** 悬浮层渲染
- **THEN** 只显示已勾选项目的当前值与单位
- **AND** 布局为紧凑形式，不出现指标名称长标签

#### Scenario: 选太多项目的溢出处理
- **WHEN** 已勾选项目的数量超出悬浮层可容纳范围
- **THEN** 悬浮层 SHALL 保持预先确定的尺寸契约，不随勾选数量逐次改变高度
- **AND** 具体截断或滚动策略由 design.md 决定；本 spec 只约束「布局不抖动」

### Requirement: 帧率与曲线
Game HUD SHALL 在数据来源可用时展示帧率曲线；SHALL NOT 用屏幕刷新率、录屏帧率或采样频率冒充游戏帧率。

#### Scenario: 曲线数据来源必须已验证
- **WHEN** 实现者接入帧率曲线
- **THEN** 数据来源 SHALL 为经过实机验证的通路
- **AND** SHALL NOT 把统一日志（`log stream`）作为帧率来源——实测中其逐帧明细被系统隐藏为 `<private>`
- **AND** SHALL NOT 在未验证的通路上先实现曲线 UI

#### Scenario: 帧率来源不可用时
- **WHEN** 当前游戏未提供已验证可用的帧率数据
- **THEN** Game HUD 不显示帧率曲线
- **AND** 不注入游戏、不拦截其渲染、不以其他频率数据替代

#### Scenario: 非帧率负载曲线
- **WHEN** 悬浮层展示 CPU/GPU 占用曲线
- **THEN** 该曲线语义 SHALL 为整机占用历史，SHALL NOT 标注为帧率或帧时间

### Requirement: 官方 Metal HUD 集成
官网渠道 SHALL 可提供针对指定游戏的可选启用辅助；两个渠道 SHALL NOT 修改影响所有 Metal 应用的全局开关、不注入游戏、不自动结束或重启游戏。

#### Scenario: 不修改全局开关
- **WHEN** 用户启用官方 HUD 辅助
- **THEN** 应用 SHALL NOT 写入影响所有 Metal 应用的全局偏好
- **AND** 作用范围 SHALL 限于用户指定的目标游戏

#### Scenario: 不自动重启游戏
- **WHEN** 官方 HUD 需要重启游戏才能生效
- **THEN** 应用只提示用户手动处理
- **AND** SHALL NOT 自动结束或重启游戏进程

#### Scenario: 环境变量按进程传递
- **WHEN** 应用尝试为目标游戏启用官方 HUD
- **THEN** SHALL NOT 依赖通过 `NSWorkspace` 启动参数或环境字典传递到已运行/已启动的游戏——实测中该环境与参数被忽略
- **AND** 若实现依赖重新以受控环境启动游戏，SHALL 先验证该路径，否则只输出供用户手动使用的说明

#### Scenario: 启用失败不影响硬件 HUD
- **WHEN** 官方 HUD 辅助启用失败或不可用
- **THEN** 硬件指标悬浮层照常工作

#### Scenario: 沙盒渠道不承诺代开官方 HUD
- **WHEN** App Store 渠道运行
- **THEN** 不提供代开官方 HUD 的能力
- **AND** 不因此隐藏 Game HUD 的其余功能

### Requirement: 全局配置
Game HUD SHALL 使用一套全局配置，不按游戏分别保存。

#### Scenario: 指标选择全局生效
- **WHEN** 用户勾选或取消勾选某项目
- **THEN** 该选择对所有游戏生效

#### Scenario: 布局配置全局生效
- **WHEN** 用户更改角落或偏移量
- **THEN** 该配置对所有游戏生效
- **AND** 游戏名单只决定「是否启用」，不承载指标与布局差异

### Requirement: 工具区入口
主面板工具区 SHALL 提供 Game HUD 的快速开关，与设置页总开关同源。

#### Scenario: 按钮状态
- **WHEN** 工具区渲染
- **THEN** 显示 Game HUD 开关按钮，激活态反映总开关状态

#### Scenario: 按钮切换
- **WHEN** 用户点击该按钮
- **THEN** 切换与设置页相同的总开关
- **AND** 不打开设置窗口
- **AND** 切换后立即影响后续的游戏前台判定

#### Scenario: 状态反馈
- **WHEN** 用户切换总开关
- **THEN** 显示简短状态提示并在数秒后自动消失

### Requirement: 生命周期与性能
Game HUD SHALL 复用既有采样通道，不引入独立采样器或每帧硬件轮询。

#### Scenario: 复用既有采样数据
- **WHEN** Game HUD 需要指标数据
- **THEN** 从既有采样发布通道读取
- **AND** 不启动独立的采样器或高频定时器

#### Scenario: 隐藏时不渲染
- **WHEN** 悬浮层隐藏
- **THEN** 不执行渲染或重绘

#### Scenario: 数据刷新频率
- **WHEN** 悬浮层显示
- **THEN** 刷新频率与既有面板采样一致
- **AND** 不因悬浮层显示而提高硬件查询频率

### Requirement: 设置界面
设置窗口 SHALL 提供 Game HUD 配置页，包含总开关、项目勾选、应用名单与布局配置。

#### Scenario: 设置页内容
- **WHEN** 用户打开 Game HUD 设置页
- **THEN** 页面包含总开关、监控项目勾选列表、应用名单与悬浮层布局配置
- **AND** 官网渠道额外包含官方 HUD 辅助说明

#### Scenario: 项目勾选列表
- **WHEN** 用户查看监控项目
- **THEN** 列表只显示本渠道与当前硬件可用的项目
- **AND** 勾选状态持久化

#### Scenario: 应用名单管理
- **WHEN** 用户查看应用名单
- **THEN** 可查看自动识别候选并排除其中项目
- **AND** 可手动添加与移除应用

#### Scenario: 布局配置
- **WHEN** 用户查看布局配置
- **THEN** 可选择四角之一并调整偏移量

### Requirement: 本地化
Game HUD 的所有用户可见文案 SHALL 通过 `String(localized:)` 接入 `Localizable.xcstrings` 并补齐现有中英翻译。

#### Scenario: 设置与提示文案
- **WHEN** 系统语言为英文
- **THEN** 设置页与状态提示显示英文

#### Scenario: 悬浮层单位不翻译
- **WHEN** 悬浮层显示数值与单位
- **THEN** 单位符号（如 `%`、`W`、`°C`）不翻译

#### Scenario: xcstrings 编辑方式
- **WHEN** 实现者补充本地化
- **THEN** SHALL 按 JSON 结构编辑 `HagimiMonitor/Localizable.xcstrings`
- **AND** SHALL NOT 引入无关重排
