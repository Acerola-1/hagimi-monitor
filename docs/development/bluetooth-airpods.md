# AirPods 身份、电量与展示

AirPods 沿用 BluetoothBatterySampler 的主线程合并发布入口。MAC 为系统设备身份，电源树/广播 UUID 单独保存，不能把 UUID 的十六进制字符当作 MAC。profiler 的同地址名称、同一会话的配对名称历史可以桥接连接后切换为通用 AirPods 名称的设备；名字不唯一时不学习绑定。

广播只补充系统连接或唯一已配对身份。打开充电仓但还没有音频连接时，也可由有效广播展示已配对 AirPods。附近陌生设备不进入列表，不对广播设备主动建立连接。已配对音频设备且蓝牙模块启用时，每 30 秒监听 8 秒；停用模块/关闭蓝牙停止。正式版本不保留临时原始蓝牙日志采集，也不进行诊断全服务枚举或设备元数据读取；原有通用诊断导出保持不变。

当前解析范围是系统已解密标记为真的 Apple 0x07/0x19、29 字节双耳格式，型号 0x2002、0x200F、0x2013、0x200E、0x2014。依据公开项目的协议分析及本项目采集验证独立实现；25 字节合盖格式、Max、其他型号与未解密载荷暂不解读。参考协议说明：[AirBattery BLEBattery.swift](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift)。目前真实日志回放验证的型号是 0x200F，其他登记型号仍需实机确认。

左右耳字段按方向位还原；低 7 位为 0–100 电量，高位为充电标记，0xff/非法百分比是缺失。每帧替换部件集合，缺失部件不从旧帧补回。广播有效期为 90 秒，过期/未来时间不参与合并；更早的广播不能覆盖更新的电源树部件快照。主电量取耳机部件最低值，充电仓独立展示，不能让盒的低电量变成耳机电量。真实 0% 保留。

蓝牙明细沿用 MonitorPanelTheme，三部件按整行展示，未知部件为破折号。设备名称允许换行，关键百分比不截断、不缩放。宽度归 BluetoothComponentSizing 管理，MetricWidthAuditTests 同时审计中英文标签和 100% 充电读数。AirPodsLayoutTests 通过正式 BluetoothDeviceList 的原生宿主输出最窄 300pt、明暗、中英文截图，不向监控数据源注入示例读数。

测试夹具 Fixtures/AirPodsBroadcasts.json 包含 59 条两渠道真实采集的电量字段，设备身份与无关尾部字节已匿名化。AirPodsRegressionTests 另验证三源重复身份、沙盒缺少 profiler/pmset、未连接开仓、同名歧义、真实零值、缺失部件、格式拒绝与过期读数。回放与原生布局验证不能替代开仓/取出单耳/取出双耳的实机验收。

Apple Watch 电量没有在本次范围内新增来源，缺失仍显示破折号。

## 本次验证（2026-10-11）

- App Store Debug 构建：通过，记录 `tmp/bluetooth-finalize/appstore-build.log`。
- Direct Debug 构建与 AirPods、宽度、面板几何/宿主回归：通过，记录 `tmp/bluetooth-finalize/direct-tests.log`。
- 现有蓝牙文件全部十个测试组：通过，记录 `tmp/bluetooth-finalize/direct-tests.log`。
- 59 条匿名真实广播回放：全部通过。
- 最窄面板中英文明暗原生宿主截图：检查通过，文件 `tmp/airpods-ui-review/`。
- 两版本地 Debug 应用已重启；源差异检查与静态 UI 审计通过。
- 朋友 build 2026101106 的两渠道日志已确认同一耳机没有重复显示、沙盒广播电量有效、主电量未包含充电仓。手表未开放标准电量服务，缺失仍保持破折号。
