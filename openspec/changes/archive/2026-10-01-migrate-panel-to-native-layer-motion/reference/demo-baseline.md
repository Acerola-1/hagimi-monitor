# Demo 技术参考记录

登记日期：2026-09-30。正式工作区基线提交：`54ddc51492fc0ebc408f0a325cd8395594aded97`。本记录用于识别已经认可的运动与 CPU 组件版本，未修改、删除或替换 Demo 源文件、运行产物及现有证据。源码目前是工作区已有的未提交文件，本次不自动提交。

## 认可版本与用途

- 当前参考入口：`NativeCPUMotionDemo.swift`，通过 `install_native_cpu.py` 在隔离源码副本中复用正式 CPU 组件；独立应用为 `tmp/panel-motion-demo/HagimiCPUNativeDemo.app`。
- 参考重点：固定容量透明窗口、完整自然尺寸内容、系统图层弹簧、统一揭示/后续行/圆角轮廓/描边/阴影、中途反转续接，以及原版 CPU 实时组件的集成。
- `Demo.swift`、`build.sh`、配色准备脚本与快照仅是早期静态运动实验。旧辅助生成器 `make_native_cpu.py` 不作为当前认可版本的重建入口，不应覆盖当前 native 源码。
- 正式迁移不复制 Demo 的硬编码容量/高度/位置、独立身份、设置导入、精简采样、测试控制窗或空操作按钮。

## 保留源码

| 仓库相对路径 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `prototypes/panel-motion-demo/NativeCPUMotionDemo.swift` | 21137 | `7f895eab6c0a6cf601487301855300e8b409d68cd00b72b5a84991f7052c1631` |
| `prototypes/panel-motion-demo/install_native_cpu.py` | 8849 | `351e9477bd9d31b4253972f1dcd9e2b1f4e77216b3699ea4dd6ebf826c40e002` |
| `prototypes/panel-motion-demo/README.md` | 5672 | `e3c353b72b978c6f7e6d2710306023ec3914e156246c33c357573fdb8fe7758f` |
| `prototypes/panel-motion-demo/Demo.swift` | 27732 | `a6b18a42fa5f4466cdf691c113e5c2f6dfcb2fa82ac40c3bd225664031f690cc` |
| `prototypes/panel-motion-demo/build.sh` | 1615 | `a93173a15a2cfc5c6e4919af44de719d017cb6d5aeee655add9d85a4faba4d6e` |
| `prototypes/panel-motion-demo/prepare_skin.py` | 764 | `0f7af29884693238cdaa8ff657ec62cf535295d137ded55a7a388f951b4bb80e` |
| `prototypes/panel-motion-demo/snapshot.json` | 5937 | `396eeff3f14c27d1d817cd141e90749d801509d32630a4506fe961de909ed232` |

## 现有实机证据与运行产物

下列文件已核对存在，当前仍位于忽略目录 `tmp/`。这是一份保留清单，不代表这些临时文件已经纳入长期版本控制；任务 1.1 必须补稳定参考目录及不依赖临时 checkout 的重建说明，清理临时目录前先保留所需证据。

| 仓库相对路径 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `tmp/panel-motion-demo/native-final-light.png` | 200537 | `ad538e84dee4c2a45ce053c90ae2f33fc46b81dfdb75a6b67e65f879413b9125` |
| `tmp/panel-motion-demo/native-final-dark.png` | 200280 | `6c481c9afb8072b447169c03ba25c32efce655df0d5f6f97a008418f62598b23` |
| `tmp/panel-motion-demo/native-final-reverse.mp4` | 8544887 | `8fdd2bba1c005f94e807b84ca4d63d84d8a4788569887ba1302a3decceb56d49` |
| `tmp/panel-motion-demo/native-cpu-live.app.log` | 6142 | `1ea66824ce74705ef2783c55ac75c464bbd560e6a34906e419b0da91aae4ee05` |
| `tmp/panel-motion-demo/native-cpu-dark-busy.app.log` | 5822 | `4197f1e7ef5cf30cfb6808ca4bd027112a086e6822d5673bdafea9e15fad23c9` |
| `tmp/panel-motion-demo/native-cpu-dark-busy.mp4` | 28195938 | `e87f175e62dccb79951b6b9d572331247ea12d46cbe52b3d5794f10d920832e5` |
| `tmp/panel-motion-demo/build-native-direct.log` | 174556 | `7b4e2540c4353466b879316ba62226f09ec4324db310dd061fdf94fcb194b9a3` |
| `tmp/panel-motion-demo/build-native-appstore.log` | 164156 | `d788215c8c09de6c6632b56ffe157c7fc1e3f1d72e4f4a807dbc00726f6e39fe` |
| `tmp/panel-motion-demo/HagimiCPUNativeDemo.app/Contents/MacOS/HagimiMonitorDirect` | 24610224 | `51e6972a91fd7239635106b3ff86d776e843e536430a2d506560b0537daeb1a5` |

## 证据边界

- 组件版普通/CPU-GPU 压力轮各记录 24 次展开收起，含快速反转，保持真实采样；这两轮是过程证据。最终同步安装版 CPU 指标排列后另有浅/深截图及连续反转录像，不假定不同轮次二进制完全相同。
- 构建日志记录两渠道 Release 成功，不等于完整产品验收。
- 最终截图和录像包含真实白色页面背景。未登记早期被其他窗口遮挡的画面作为视觉证据。
- 目前没有全模块、封顶滚动、完整无障碍或固定透明窗口跨应用事件的验收证据。原型 CPU 数字与早期静态宿主布局次数不能作为正式全量收益。
- 原安装版未被 Demo 替换；正式集成在本 change 的任务中另行实施。
