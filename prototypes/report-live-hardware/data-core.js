/* 原型共用:图标 / 分组常量 / 左栏顺序 / 数值工具
   数值为演示夹具;字段命名对齐本项目的 kind.* 与 metric.* */

const ICON = {
  cpu: '<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M10 3v2M14 3v2M10 19v2M14 19v2M3 10h2M3 14h2M19 10h2M19 14h2"/>',
  gpu: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="10" cy="12" r="3"/><path d="M15 9.5h3M15 14.5h3"/>',
  memory: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 6v12M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
  disk: '<ellipse cx="12" cy="6.5" rx="7" ry="3"/><path d="M5 6.5v11c0 1.66 3.13 3 7 3s7-1.34 7-3v-11"/><path d="M5 12c0 1.66 3.13 3 7 3s7-1.34 7-3"/>',
  network: '<path d="M4.5 10a11 11 0 0 1 15 0M7.5 13.5a7 7 0 0 1 9 0"/><circle cx="12" cy="18" r="1.3"/>',
  power: '<path d="M9 3v6M15 3v6"/><path d="M6 9h12v3.5a6 6 0 0 1-12 0z"/><path d="M12 18.5V21"/>',
  device: '<rect x="4" y="5" width="16" height="11" rx="2"/><path d="M2 19.5h20"/>',
  display: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M8 20h8M12 16.5V20"/>',
  thermo: '<path d="M10.5 13V5a2 2 0 1 1 4 0v8a4 4 0 1 1-4 0z"/><path d="M12.5 9.5v5"/>',
  connect: '<path d="M9.5 14.5l5-5"/><path d="M11 6.5l1.3-1.3a3.9 3.9 0 0 1 5.5 5.5L16.5 12"/><path d="M13 17.5l-1.3 1.3a3.9 3.9 0 0 1-5.5-5.5L7.5 12"/>',
  system: '<path d="M12 3l7 2.8v6.1c0 4.4-2.9 7.5-7 9.1-4.1-1.6-7-4.7-7-9.1V5.8z"/><path d="M9.5 12.2l1.9 1.9 3.6-3.9"/>',
  fan: '<circle cx="12" cy="12" r="2.1"/><path d="M12 9.9V3.5M14.1 12h6.4M12 14.1v6.4M9.9 12H3.5"/>',
  dist: '<path d="M4 20V10M10 20V4M16 20v-7M22 20v-4"/>',
};

function icon(name, cls = 'ic') {
  return `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"
    stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[name] || ICON.cpu}</svg>`;
}

const MISSING = '<span class="missing">—</span>';
const ok = (v) => (v == null || v === '' ? MISSING : v);
const pad = (n) => String(n).padStart(2, '0');
/* 千分位用空格(与报表 fmtRPM 的可读性一致,但不跟随语言环境) */
const groupNum = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const fmtClock = (d = new Date()) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const fmtMinute = (d = new Date()) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

/* RAIL 是模块顺序的唯一来源:左栏条目、正文板块顺序、序号徽章都从它派生 */
const RAIL = [
  { id: 'cpu', label: 'CPU', icon: 'cpu' },
  { id: 'gpu', label: 'GPU', icon: 'gpu' },
  { id: 'memory', label: '内存', icon: 'memory' },
  { id: 'network', label: '网络', icon: 'network' },
  { id: 'disk', label: '磁盘', icon: 'disk' },
  { id: 'power', label: '电源', icon: 'power' },
  { id: 'machine', label: '本机', icon: 'device' },
];

/* 夹具曲线:seed 决定相位,围绕 base 摆动 */
function seedSeries(seed, base, amp, n = 60) {
  return Array.from({ length: n }, (_, i) => {
    const w = Math.sin((i + seed * 3) * 0.28) * amp + Math.sin((i + seed) * 0.83) * amp * 0.45;
    return Math.max(2, Math.min(96, base + w));
  });
}

/* 核心负载分布:5 档(与报表 distOption 同形) */
const DIST_BUCKETS = [0.42, 0.27, 0.16, 0.10, 0.05];
