## 更新内容

### 中文

#### 修复

- 修复菜单栏数值格式化遇到 NaN / Infinity 传感器读数时崩溃闪退的问题
- 修复钉选面板打开设置时误关悬浮面板、自身残留遮挡设置窗口的问题

#### 优化与体验

- 重构崩溃信号处理为纯 C 实现，规避 Swift 运行时在信号上下文中堆分配引发的潜在陷阱
- 增强发布脚本对 tag 名称的白名单校验，拦截非法字符注入与路径穿越，杜绝半成品发布
- 为硬件探针子进程增加超时后的 SIGKILL 兜底清理，杜绝僵尸进程与采样线程泄漏

### English

#### Fixes

- Fixed a crash in menu bar metric formatting when sensor readings are NaN or Infinity.
- Fixed the pinned panel failing to dismiss itself when opening Settings, which left it covering the settings window.

#### Improvements

- Refactored crash signal handling to a pure C implementation, avoiding Swift runtime allocation pitfalls inside signal contexts.
- Hardened the release script with tag name whitelist validation against injection and path traversal.
- Added SIGKILL fallback cleanup for timed-out hardware probe subprocesses, preventing zombie processes and sampler thread leaks.

