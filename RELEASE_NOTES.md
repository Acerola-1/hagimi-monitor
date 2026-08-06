## 更新内容

### 修复

- 修复公网 IP 在部分网络环境返回错误或不稳定：改为多源 fallback 链（3322.net / ipinfo.io / checkip.amazonaws.com / ifconfig.me / icanhazip / ipify），并新增 inet_pton 严格校验，避免 Cloudflare HTML 错误页被误识别为 IP
- 修复电源模块功率流在 power 数据缺失时只显标题不出图，改为整体隐藏避免视觉断裂

### 优化与体验

- 网络进程排行从累计字节增量改为字节/秒速率，与 macOS 活动监视器等行业惯例一致

