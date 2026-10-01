# 原生 CPU 技术参考

认可版本的源文件保持原样。`reference/source-baseline.tar.gz` 保存构建所需的正式源码、工程和测试基线，提交标识在 `source-baseline.commit`；当前源码可以继续演进，重建 Demo 不再依赖此前的临时 checkout。

从仓库根目录运行 `bash prototypes/panel-motion-demo/build-native-reference.sh`。构建入口解包该基线，再应用原版 CPU 组件适配和 `NativeCPUMotionDemo.swift`，生成独立 Bundle ID 的应用，输出位于 `tmp/panel-motion-reference/`。构建使用工程锁定的包版本；本地缺少依赖缓存时先按正常项目流程解析依赖。

旧的 `make_native_cpu.py` 是中间生成工具，不能用于重新生成当前认可版本。`Demo.swift` 与 `build.sh` 属于早期快照实验。

证据索引及源码哈希见 OpenSpec `migrate-panel-to-native-layer-motion/reference/demo-baseline.md`。正式迁移只吸收运动原理和组件复用方法，独立启动身份、测试控制窗、设置导入及精简 Store 不进入正式应用。
