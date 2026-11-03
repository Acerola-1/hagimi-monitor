## 更新内容

### 中文

#### 修复

- 进程排行不再把装在 `/usr/local` 下的程序当成系统进程藏起来。Apple 容器会单独列出，内存占用不再整批消失。

#### 优化与体验

- 深色面板压暗：平衡配色的行底不再发白，行内白罩、指标格和底部按钮都收淡，文字更清楚。
- 浅色面板压深文字，行内白罩和指标格收淡；网络、存储、电源主行上的读数底仍保持清楚的轮廓。
- 长按拖动排序时，浮起的卡片去掉亮色描边，边缘用淡出的阴影和面板接上。
- 面板隐藏后，不再继续查没人在看的温度、公网 IP 和蓝牙信息；重新打开时显示更稳。

#### 目前已知的问题

##### 正在修复

- Apple Watch 无法正常显示电量余量（#131）：已能读取连接数据，但取不到准确的电量读数。

##### 未修复

- Mac mini 无法正常显示能耗（#106）：手头没有对应设备，暂时无法验证。
- 开启代理软件 TUN 模式后网络显示未连接（#98）：本机开启 TUN 模式未出现该问题。
- MacBook Air M4 无法正常显示充电功率（#86）：手头没有对应设备，暂时无法验证。

### English

This release darkens the dark panel, deepens light-mode text, and softens the card that lifts while reordering.

#### Fixes

- Process rankings no longer hide programs installed under `/usr/local` by treating them as system processes. Apple containers are listed on their own, so their memory use no longer disappears as a batch.

#### Improvements

- Dark mode is dimmed: balanced row backgrounds are no longer washed out, and the white veil, metric chips, and footer buttons are lighter so the text reads more clearly.
- Light mode uses deeper text. The white veil and metric chips are lighter, while the reading wells on the Network, Storage, and Power rows keep a clear edge.
- While reordering with a long press, the lifted card no longer has a bright tinted outline. A soft shadow blends its edge into the panel.
- While the panel is hidden, the app stops checking temperature, public IP, and Bluetooth details that nothing is showing. Reopening the panel is more stable.

#### Known Issues

##### In progress

- Apple Watch does not show the correct battery level (#131): the connection data can be read, but not an accurate battery level.

##### Open

- Mac mini does not show power consumption (#106): no device available for verification yet.
- Network shows as disconnected after a proxy app enables TUN mode (#98): enabling TUN mode locally does not trigger it.
- MacBook Air M4 does not show charging power (#86): no device available for verification yet.

