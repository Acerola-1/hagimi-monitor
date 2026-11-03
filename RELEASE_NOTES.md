## 更新内容

感谢 @twdlight 报告高负载提醒的时长显示问题（#136）。

### 修复

- 高负载提醒不再把持续时长显示成一串巨大数字。正文改为写明持续了多久、平均大约多少。

### 优化与体验

- 内存容量改为 GB/MB。
- 内存和温度提醒写明压力档位和已持续的时间；有 CPU 温度时写上度数。
- 风扇转速不再单独发通知。

### 目前已知的问题

#### 未修复

- Mac mini 无法正常显示能耗（#106）：手头没有对应设备，暂时无法验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86）：手头没有对应设备，暂时无法验证。

#### 正在修复

- Apple Watch 无法正常显示电量余量（#131）：已能读取连接数据，但取不到准确的电量读数。

### English

Thanks to @twdlight for reporting the high-load alert duration (#136).

- High-load alerts no longer show the duration as a huge number. The text now states how long it lasted and the average amount.
- Memory is shown in GB/MB.
- Memory and temperature alerts name the pressure level and how long it has lasted. A CPU temperature is included when a fresh reading exists.
- Fan speed no longer sends its own notification.

