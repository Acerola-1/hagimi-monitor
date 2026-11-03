# Design

## Context

见 proposal.md。系统进程判定是五类 TOP 榜共用的路径前缀；`/usr/` 会命中 `/usr/local/`。分组先按负责进程归并，再按宿主路径过滤。container 的虚机路径在 `/System` 下，内存在宿主为 runtime 的那一组里。container 1.6.1 的 runtime 参数是 `start --root <目录> --uuid <容器 ID>`。

## Goals / Non-Goals

**Goals:**

- 在现有判定上增加 `/usr/local/` 例外，且例外先于 `/usr/` 前缀生效。
- Direct 只为已进入展示结果、可执行文件名为 `container-runtime-linux` 的行解析容器 ID。
- 保持「先归组、再按宿主路径过滤」。

**Non-Goals:**

- 不改负责进程归组，不把多个容器收成一组，不加合计行。
- 不调用 `launchctl`，不读容器数据目录，不展示 `--root` 全路径。
- 不改内存口径，不为 App Store 增加参数读取，不为 network helper 或其他命令行进程改名。

## Decisions

1. **用前缀例外，不改系统前缀表，也不加白名单。** `isSystemProcessPath` 在匹配 `/usr/` 之前，对 `/usr/local/` 直接视为非系统。`/usr/libexec/containermanagerd` 仍是系统进程。白名单会把第三方放进「始终显示的系统应用」，以后每多一个 `/usr/local` 软件都要再加一条。改写整张前缀表则会放过 `/usr/` 下尚未列出的系统目录。
2. **容器 ID 来自该进程自己的参数。** Direct 用 `KERN_PROCARGS2` 只读这一行的参数，取 `--uuid` 的值。没有 `--uuid` 时，用 `--root` 的最后一段；两者都没有则保留可执行文件名。不解析 launchd 标签：1.6.1 的标签碰巧带容器 ID，但标签格式已经变过，而且要起子进程扫全表。
3. **只在截断后的展示行上读参数。** 名字不参与排序。每秒最多处理已经要显示的几行，且仅当可执行文件名匹配时才读。五个榜的显示名回退走同一个助手；App Store 编译掉参数读取。
4. **过滤键仍是宿主路径。** 虚机进程自身位于 `/System`。若先按每个进程的路径丢弃系统进程，容器行只会剩下 runtime 自身的少量内存。

## Risks / Trade-offs

- 责任进程归并失败时，虚机仍会被系统路径丢掉，榜上只剩 runtime 的小占用 → 不改变归并顺序，并用测试固定「宿主路径决定过滤」。
- 参数格式变化或读取失败 → 行继续出现，名称回退为可执行文件名。
- `/usr/local` 上的其他第三方会进入五个榜 → 这是分类修正的预期结果；占用不高的进程仍会被 TOP 5 截掉。
- 长容器 ID 在行内截断 → 沿用现有单行截断，不改指标宽度契约。

## Migration Plan

无偏好或数据迁移。回退就是去掉路径例外和 Direct 的参数解析。验证用纯函数测试，不要求本机正在跑容器。
