# Proposal

## Why

Apple container 装在 `/usr/local`，内存 TOP 榜把它当成系统进程丢掉。每个容器的虚机内存其实已经归在对应的 `container-runtime-linux` 上，但行名都是同一个可执行文件名，看不出该重启哪一个。

## What Changes

- 共用的系统进程判定把路径前缀 `/usr/local/` 视为第三方，不再被 `/usr/` 吃掉。五个 TOP 榜一起生效。
- Direct 上，每个 `container-runtime-linux` 分组仍是一行；显示名改用该进程参数里的 `--uuid`（容器 ID）。虚机 XPC 的内存留在这一行里。
- 不增加「全部容器合计」，也不把多个容器并成一行。
- App Store 不做参数读取。分类修正因落在共用判定里，两个渠道都会不再隐藏 `/usr/local`；App Store 行名仍是可执行文件名。

## Capabilities

### New Capabilities

- `top-process-rows`: TOP 榜的系统进程路径判定，以及 Apple container 分组的一行一名。

### Modified Capabilities

无。既有 `monitor-panel` 的「按负责进程归并」仍然成立：虚机并入它自己的 runtime，独立容器保持分开。

## Impact

- `isSystemProcessPath` 及五类 TOP 采样（CPU、内存、GPU、磁盘、网络）的可见集合。
- Direct 的进程显示名回退。不新增探针进程，不读 launchd，不改内存口径，不加用户可见的固定文案。
- 需要补路径判定和容器名的测试。面板布局、TOP 5 截断、沙盒内存口径不变。
