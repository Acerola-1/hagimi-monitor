# top-process-rows

## Purpose

规定 CPU、内存、GPU、磁盘和网络 TOP 榜如何判定系统进程，以及 Direct 上每个 Apple container 如何以容器 ID 单独显示为一行。

## ADDED Requirements

### Requirement: 本地安装路径不是系统进程

用户关闭「显示系统进程」时，可执行文件路径以 `/usr/local/` 开头的进程 SHALL 仍进入对应 TOP 榜。`/usr/` 下其余既有系统路径 SHALL 继续被排除。五个 TOP 榜 SHALL 使用同一结论。

#### Scenario: container 在关闭系统进程时可见

- **WHEN** 用户关闭某模块的「显示系统进程」，且进程路径位于 `/usr/local/`
- **THEN** 该进程按普通进程参与该模块 TOP 榜的过滤和排序

#### Scenario: 系统目录仍被排除

- **WHEN** 用户关闭「显示系统进程」，且进程路径位于 `/usr/libexec/`、`/usr/bin/` 或 `/System/`
- **THEN** 该进程不进入 TOP 榜

#### Scenario: 五个榜结论一致

- **WHEN** 同一可执行文件路径分别进入 CPU、内存、GPU、磁盘和网络榜的过滤
- **THEN** 五个榜对它是否算系统进程给出相同结论

### Requirement: 每个容器单独一行

每个 Apple container 的 runtime 与归属于它的虚机 SHALL 合计为一条 TOP 行。不同容器 SHALL 保持分开，内存不得相加。

#### Scenario: 虚机内存算进该容器

- **WHEN** 一个虚机进程归属于某个 container runtime
- **THEN** 该虚机的内存计入这个 runtime 的一行
- **AND** 虚机不因自身路径位于系统目录而从该行消失，也不单独占一行

#### Scenario: 两个容器不合并

- **WHEN** 两个 container runtime 同时运行
- **THEN** 榜上各自至多一行，两行内存不相加

### Requirement: 不提供全部容器合计

TOP 榜 SHALL NOT 增加一条代表全部 Apple container 内存之和的条目。

#### Scenario: 多个容器同时运行

- **WHEN** 多个容器同时运行，且其中若干行已出现在 TOP 榜
- **THEN** 榜上没有额外的全部容器合计行

### Requirement: Direct 用容器 ID 作为行名

Direct 上，container runtime 分组的显示名 SHALL 使用该进程启动参数中的容器 ID。读不到 ID 时 SHALL 回退为可执行文件名，且该行仍然显示。行名 SHALL NOT 使用容器根目录的完整路径。

#### Scenario: 参数里有容器 ID

- **WHEN** Direct 采样到一个 container runtime，且能读到其容器 ID
- **THEN** 该行名称是这个 ID，而不是可执行文件名

#### Scenario: 读不到容器 ID

- **WHEN** Direct 无法读取该进程的容器 ID
- **THEN** 该行仍参与排名，名称回退为可执行文件名

#### Scenario: 不展示根路径

- **WHEN** 进程参数同时包含容器根目录和容器 ID
- **THEN** 行名只使用容器 ID

### Requirement: App Store 不读取进程参数

App Store 渠道 SHALL NOT 为容器行名读取其他进程的启动参数。`/usr/local/` 上的 container runtime SHALL 仍可上榜，名称使用可执行文件名。

#### Scenario: 沙盒渠道的行名

- **WHEN** App Store 版显示一个位于 `/usr/local/` 的 container runtime
- **THEN** 行名是可执行文件名
- **AND** 不为此读取该进程的启动参数
