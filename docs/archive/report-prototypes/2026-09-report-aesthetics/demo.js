"use strict";
/* 报表审美原型共享库:演示数据 + SVG 图表 + 页面骨架 + 交互装配。
   四个方案(a/b/c/d)共用同一份信息架构与数据,差异全部在各自的 <style> 里。
   所有图表颜色取自 CSS 变量(--c-cpu 等),换肤不改 JS。 */
window.Demo = (() => {

  /* ── 确定性伪随机:同一范围每次生成同一份数据,便于目测对比 ── */
  function rng(seed) {
    let a = seed >>> 0;
    return () => {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /* 随机游走序列:base 中位,amp 振幅,n 点数,带昼夜节律 */
  function walk(r, base, amp, n, opts) {
    opts = opts || {};
    const out = []; let v = base;
    for (let i = 0; i < n; i++) {
      const day = opts.daily ? Math.sin((i / n) * Math.PI * 2 * (opts.cycles || 1) - Math.PI / 2) * amp * 0.55 : 0;
      v += (r() - 0.5) * amp * 0.7;
      v = Math.max(opts.min ?? 0, Math.min(opts.max ?? 100, v));
      out.push(Math.max(opts.min ?? 0, Math.min(opts.max ?? 100, base + day + (v - base) * 0.6 + (r() - 0.5) * amp * 0.5)));
    }
    return out;
  }

  const RANGES = {
    today: { n: 24, seed: 11, days: 1, label: (i) => String(i).padStart(2, "0") + ":00", gran: "小时粒度", heatDays: 7 },
    week:  { n: 28, seed: 23, days: 7, label: (i) => ["周一","周二","周三","周四","周五","周六","周日"][Math.floor(i / 4)], gran: "6 小时粒度", heatDays: 7 },
    month: { n: 30, seed: 37, days: 30, label: (i) => "9/" + (i % 30 + 1), gran: "日粒度", heatDays: 28 },
  };

  /* 自定义范围:起止日期来自时间栏弹层,按跨度天数生成日粒度配置(2~31 天) */
  let customSpan = null;
  const dayMs = 864e5;
  function customCfg() {
    const end = customSpan ? customSpan.end : new Date();
    const start = customSpan ? customSpan.start : new Date(end.getTime() - 6 * dayMs);
    const days = Math.max(2, Math.min(31, Math.round((end - start) / dayMs) + 1));
    return {
      n: days, days, seed: 1000 + days * 7, gran: "日粒度", heatDays: 7,
      label: (i) => { const d = new Date(start.getTime() + i * dayMs); return (d.getMonth() + 1) + "/" + d.getDate(); },
    };
  }

  /* 逐日明细的日期文案:自定义范围按所选结束日倒推,其余固定落在 9 月 11 日(与演示数据口径一致) */
  function tableDay(rangeKey, i) {
    const end = rangeKey === "custom" && customSpan ? new Date(customSpan.end) : new Date(2026, 8, 11);
    end.setDate(end.getDate() - i);
    return (end.getMonth() + 1) + " 月 " + end.getDate() + " 日";
  }

  /* ── 演示数据:字段语义对齐真实报表(StatisticsReportBuilder) ── */
  function buildData(rangeKey) {
    const R = rangeKey === "custom" ? customCfg() : (RANGES[rangeKey] || RANGES.today);
    const r = rng(R.seed);
    const n = R.n;
    const labels = Array.from({ length: n }, (_, i) => R.label(i));
    const cycles = rangeKey === "today" ? 1 : Math.min(4, n / 7);

    const cpu = walk(r, 24, 30, n, { daily: true, cycles, max: 96 });
    const gpu = walk(r, 18, 26, n, { daily: true, cycles, max: 88 });
    const mem = walk(r, 58, 12, n, { min: 34, max: 91 });
    const memP = walk(r, 30, 18, n, { max: 86 });
    const down = walk(r, 42, 60, n, { max: 480 });
    const up = walk(r, 9, 14, n, { max: 92 });
    const dR = walk(r, 60, 90, n, { max: 820 });
    const dW = walk(r, 34, 60, n, { max: 640 });
    const power = walk(r, 15, 10, n, { min: 4, max: 58 });
    const batt = walk(r, 72, 16, n, { min: 18, max: 100 });
    const temp = walk(r, 46, 9, n, { min: 32, max: 84 });

    const avg = (a) => a.reduce((s, v) => s + v, 0) / a.length;
    const peak = (a) => Math.max.apply(null, a);
    const f1 = (v) => v.toFixed(1);

    /* 热力图:7 天 × 24 小时,工作时段偏热 */
    const heat = [];
    for (let d = 0; d < 7; d++) {
      const row = [];
      for (let h = 0; h < 24; h++) {
        const work = (h >= 9 && h <= 12) || (h >= 14 && h <= 19) ? 0.55 : h < 7 ? 0.06 : 0.22;
        row.push(Math.max(0, Math.min(1, work + (r() - 0.5) * 0.5)));
      }
      heat.push(row);
    }

    return {
      meta: { device: "Acerola 的 MacBook Pro", model: "MacBook Pro 14″ · M4 Pro", os: "macOS 27.0", days: R.days },
      gran: R.gran, heatDays: R.heatDays,
      labels, series: { cpu, gpu, mem, memP, down, up, dR, dW, power, batt, temp },
      score: { value: 82, level: "状态良好", dims: [
        { name: "CPU 负载", state: "good", raw: "平均 " + f1(avg(cpu)) + "%" },
        { name: "GPU 负载", state: "good", raw: "平均 " + f1(avg(gpu)) + "%" },
        { name: "内存压力", state: "warn", raw: "偏高 41 分钟" },
        { name: "散热", state: "good", raw: "峰值 " + Math.round(peak(temp)) + "°C" },
      ]},
      kpis: [
        { key: "cpu",   label: "CPU 平均",   value: f1(avg(cpu)) + "%",   sub: "峰值 " + f1(peak(cpu)) + "%",  spark: cpu },
        { key: "gpu",   label: "GPU 平均",   value: f1(avg(gpu)) + "%",   sub: "峰值 " + f1(peak(gpu)) + "%",  spark: gpu },
        { key: "mem",   label: "内存压力",   value: f1(avg(memP)) + "%",  sub: "占用 " + f1(avg(mem)) + "%",   spark: memP },
        { key: "net",   label: "网络下行",   value: f1(avg(down)) + " MB/s", sub: "上行 " + f1(avg(up)) + " MB/s", spark: down },
        { key: "disk",  label: "磁盘读取",   value: f1(avg(dR)) + " MB/s", sub: "峰值 " + Math.round(peak(dR)) + " MB/s", spark: dR },
        { key: "power", label: "平均功耗",   value: f1(avg(power)) + " W", sub: "峰值 " + f1(peak(power)) + " W", spark: power },
        { key: "batt",  label: "电池电量",   value: Math.round(avg(batt)) + "%", sub: "循环 214 · 健康 96%", spark: batt },
        { key: "thermal", label: "CPU 温度", value: f1(avg(temp)) + "°C", sub: "峰值 " + Math.round(peak(temp)) + "°C", spark: temp },
      ],
      pe: { labels: ["P0","P1","P2","P3","P4","P5","P6","P7","P8","P9","E0","E1","E2","E3"],
            values: Array.from({ length: 14 }, (_, i) => i < 10 ? 18 + r() * 46 : 6 + r() * 22) },
      dist: { labels: ["0–20%","20–40%","40–60%","60–80%","80–100%"],
              values: [38, 27, 18, 11, 6].map((v) => v + r() * 6) },
      apps: {
        cpu: [["Xcode", 34.2], ["Google Chrome", 18.7], ["Trae", 12.4], ["Affinity Photo", 9.8], ["Docker", 7.1]],
        mem: [["Google Chrome", 4.6], ["Xcode", 3.9], ["Docker", 2.8], ["微信", 1.4], ["Notion", 1.1]],
        gpu: [["Affinity Photo", 22.5], ["Google Chrome", 14.3], ["Final Cut Pro", 11.9], ["Trae", 6.2], ["Xcode", 4.8]],
        net: [["Google Chrome", 12.4], ["iCloud 同步", 8.1], ["Docker", 5.6], ["Apple Music", 3.2], ["App Store", 2.4]],
      },
      events: [
        { sev: "warn", time: "今天 14:32", title: "内存压力偏高", detail: "持续 41 分钟 · 已恢复" },
        { sev: "warn", time: "今天 11:05", title: "热压力上升为 Fair", detail: "CPU " + Math.round(peak(temp)) + "°C · 持续 12 分钟" },
        { sev: "info", time: "今天 09:58", title: "高负载时段开始", detail: "Xcode 编译 · CPU 峰值 " + f1(peak(cpu)) + "%" },
        { sev: "ok",   time: "昨天 22:41", title: "电池循环 214 次", detail: "健康度 96% · 状态正常" },
        { sev: "info", time: "昨天 16:20", title: "磁盘写入高峰", detail: "Docker 镜像构建 · 峰值 " + Math.round(peak(dW)) + " MB/s" },
      ],
      insights: [
        { tone: "cpu", title: "负载习惯", body: "上午 9–12 点是最重的使用时段,编译与浏览器贡献了 62% 的 CPU 时间。" },
        { tone: "mem", title: "内存趋势", body: "内存压力在过去一周缓慢上行,建议关注 Chrome 标签页数量与 Docker 常驻镜像。" },
        { tone: "net", title: "网络使用", body: "下行流量集中在工作日白天,周末显著回落;上行以 iCloud 同步为主。" },
      ],
      table: Array.from({ length: rangeKey === "today" ? 7 : Math.min(10, R.days) }, (_, i) => ({
        day: rangeKey === "today" ? "今天 " + String(8 + i * 2).padStart(2, "0") + ":00" : tableDay(rangeKey, i),
        cpuAvg: f1(10 + r() * 30), cpuPeak: f1(50 + r() * 45), memAvg: f1(45 + r() * 25), memP: f1(15 + r() * 45),
        down: f1(2 + r() * 14), up: f1(0.4 + r() * 3), dR: Math.round(80 + r() * 400), dW: Math.round(40 + r() * 260),
        ac: r() > 0.45 ? "✓" : "—", power: f1(9 + r() * 14), cover: Math.round(68 + r() * 30) + "%",
      })),
      heat,
      specs: {
        cpu: { groups: [{ name: "处理器", rows: [["芯片", "Apple M4 Pro"], ["核心", "14 核 · 10P + 4E"], ["制程", "第二代 3 纳米"]] }],
               live: [["使用率", 24, "%"], ["热压力", 22, "%"], ["进程数", 412, ""], ["空闲", 76, "%"]] },
        gpu: { groups: [{ name: "图形处理器", rows: [["核心", "20 核 GPU"], ["架构", "Apple GPU · 动态缓存"], ["显存", "统一内存共享"]] }],
               live: [["利用率", 18, "%"], ["显存占用", 3.2, " GB"], ["渲染器", 31, "%"], ["分块器", 24, "%"]] },
        mem: { groups: [{ name: "统一内存", rows: [["容量", "24 GB"], ["规格", "LPDDR5X · 273 GB/s"]] }],
               live: [["已用", 13.8, " GB"], ["压缩", 1.9, " GB"], ["交换", 0.4, " GB"], ["压力", 30, "%"]] },
        net: { groups: [{ name: "网络", rows: [["无线", "Wi-Fi 6E"], ["蓝牙", "5.3"], ["接口", "en0"]] }],
               live: [["下行", 42, " MB/s"], ["上行", 9, " MB/s"], ["信号", -52, " dBm"]] },
        disk: { groups: [{ name: "存储", rows: [["卷", "Macintosh HD"], ["容量", "512 GB · APFS"], ["接口", "NVMe"]] }],
               live: [["已用", 318, " GB"], ["可用", 194, " GB"], ["读取", 60, " MB/s"], ["写入", 34, " MB/s"]] },
        power: { groups: [{ name: "电源", rows: [["电池", "70 Wh"], ["适配器", "96 W USB-C"], ["循环", "214 次"]] }],
               live: [["电量", 72, "%"], ["状态", "—", "放电中"], ["电池温度", 31.5, "°C"]] },
      },
      machine: [
        { id: "overview", name: "概览", sub: "整机档案", groups: [
          { name: "设备", rows: [["型号", "MacBook Pro 14″"], ["芯片", "Apple M4 Pro"], ["序列号", "C02XL·····J13"]] },
          { name: "系统", rows: [["macOS", "27.0 (25A354)"], ["内核", "Darwin 26.0.0"], ["启动", "3 天前"]] } ]},
        { id: "cpu", name: "处理器", sub: "M4 Pro · 14 核", groups: [
          { name: "核心拓扑", rows: [["性能核", "10 × 4.5 GHz"], ["能效核", "4 × 2.6 GHz"], ["神经网络引擎", "16 核"]] },
          { name: "缓存", rows: [["L2(性能)", "10 MB"], ["L2(能效)", "4 MB"]] } ]},
        { id: "gpu", name: "显卡", sub: "20 核 Apple GPU", groups: [
          { name: "图形", rows: [["核心", "20 核"], ["特性", "硬件光追 · 网格着色"], ["显存", "与统一内存共享"]] } ]},
        { id: "mem", name: "内存", sub: "24 GB 统一内存", groups: [
          { name: "规格", rows: [["容量", "24 GB"], ["类型", "LPDDR5X"], ["带宽", "273 GB/s"]] } ]},
        { id: "storage", name: "存储", sub: "512 GB NVMe", groups: [
          { name: "宗卷", rows: [["Macintosh HD", "512 GB · APFS"], ["已用", "318 GB"], ["可用", "194 GB"]] } ]},
        { id: "display", name: "显示器", sub: "Liquid Retina XDR", groups: [
          { name: "内建", rows: [["尺寸", "14.2 英寸"], ["分辨率", "3024 × 1964"], ["刷新率", "ProMotion 120 Hz"], ["亮度", "峰值 1600 nit"]] } ]},
        { id: "battery", name: "电源", sub: "70 Wh 锂聚合物", groups: [
          { name: "电池", rows: [["容量", "70 Wh"], ["循环计数", "214"], ["最大容量", "96%"], ["适配器", "96 W USB-C"]] } ]},
        { id: "thermal", name: "传感器", sub: "温度与风扇", groups: [
          { name: "读数", rows: [["CPU 二极管", "46.2°C"], ["GPU 二极管", "41.8°C"], ["风扇", "0 RPM(停转)"]] } ]},
      ],
    };
  }

  /* ── 基础工具 ── */
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
  let uid = 0;

  const MODULE_COLOR = (key) => cssVar("--c-" + key) || cssVar("--accent");

  /* ── 平滑折线路径(Catmull-Rom → 贝塞尔) ── */
  function smoothPath(pts) {
    if (pts.length < 2) return "";
    if (pts.length < 3) return "M" + pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join("L");
    let d = `M${pts[0][0].toFixed(1)},${pts[0][1].toFixed(1)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
      const c1x = p1[0] + (p2[0] - p0[0]) / 6, c1y = p1[1] + (p2[1] - p0[1]) / 6;
      const c2x = p2[0] - (p3[0] - p1[0]) / 6, c2y = p2[1] - (p3[1] - p1[1]) / 6;
      d += `C${c1x.toFixed(1)},${c1y.toFixed(1)},${c2x.toFixed(1)},${c2y.toFixed(1)},${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
    }
    return d;
  }

  function niceMax(v) {
    const steps = [10, 20, 25, 40, 50, 60, 80, 100, 125, 150, 200, 250, 400, 500, 800, 1000];
    for (const s of steps) if (v <= s * 0.92) return s;
    return Math.ceil(v / 100) * 100;
  }

  /* 画线动画:描边从 0 长出 */
  function drawIn(path) {
    if (reduceMotion || !path.getTotalLength) return;
    const len = path.getTotalLength();
    path.style.strokeDasharray = len; path.style.strokeDashoffset = len;
    path.getBoundingClientRect();
    path.style.transition = "stroke-dashoffset 1.1s cubic-bezier(.3,.7,.3,1)";
    path.style.strokeDashoffset = "0";
  }

  /* ── 折线/面积图(多序列 + 悬浮十字线 + 提示) ── */
  function lineChart(node, cfg) {
    node._cfg = { type: "line", cfg };
    const W = Math.max(280, node.clientWidth), H = Math.max(160, node.clientHeight);
    const pad = { l: 40, r: 14, t: 14, b: 24 };
    const iw = W - pad.l - pad.r, ih = H - pad.t - pad.b;
    const max = cfg.max ?? niceMax(Math.max.apply(null, cfg.series.flatMap((s) => s.values)));
    const n = cfg.labels.length;
    const X = (i) => pad.l + (iw * i) / (n - 1);
    const Y = (v) => pad.t + ih - (ih * v) / max;

    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("width", "100%"); svg.setAttribute("height", "100%");

    const gridColor = cssVar("--chart-grid"), labelColor = cssVar("--chart-label");
    for (let g = 0; g <= 4; g++) {
      const y = pad.t + (ih * g) / 4;
      const ln = document.createElementNS(NS, "line");
      ln.setAttribute("x1", pad.l); ln.setAttribute("x2", W - pad.r);
      ln.setAttribute("y1", y); ln.setAttribute("y2", y);
      ln.setAttribute("stroke", gridColor); ln.setAttribute("stroke-width", g === 4 ? 1.2 : 1);
      if (g !== 4) ln.setAttribute("stroke-dasharray", "2 5");
      svg.appendChild(ln);
      const tx = document.createElementNS(NS, "text");
      tx.setAttribute("x", pad.l - 8); tx.setAttribute("y", y + 3.5);
      tx.setAttribute("text-anchor", "end"); tx.setAttribute("class", "axis-y");
      tx.setAttribute("fill", labelColor);
      tx.textContent = Math.round(max * (4 - g) / 4);
      svg.appendChild(tx);
    }
    const tickEvery = Math.ceil(n / 7);
    // 末点兜底仅在与最后规则刻度不同文案时追加,避免周模式末端重复"周日"
    const lastTick = Math.floor((n - 1) / tickEvery) * tickEvery;
    cfg.labels.forEach((lb, i) => {
      if (i % tickEvery !== 0 && (i !== n - 1 || cfg.labels[lastTick] === lb)) return;
      const tx = document.createElementNS(NS, "text");
      tx.setAttribute("x", X(i)); tx.setAttribute("y", H - 7);
      tx.setAttribute("text-anchor", "middle"); tx.setAttribute("class", "axis-x");
      tx.setAttribute("fill", labelColor); tx.textContent = lb;
      svg.appendChild(tx);
    });

    cfg.series.forEach((s) => {
      const pts = s.values.map((v, i) => [X(i), Y(v)]);
      const d = smoothPath(pts);
      if (s.area !== false) {
        const gid = "g" + (++uid);
        const grad = document.createElementNS(NS, "linearGradient");
        grad.setAttribute("id", gid); grad.setAttribute("x1", 0); grad.setAttribute("y1", 0); grad.setAttribute("x2", 0); grad.setAttribute("y2", 1);
        const c = s.color;
        [["0%", 0.20], ["100%", 0.01]].forEach(([off, op]) => {
          const stop = document.createElementNS(NS, "stop");
          stop.setAttribute("offset", off); stop.setAttribute("stop-color", c); stop.setAttribute("stop-opacity", op);
          grad.appendChild(stop);
        });
        svg.appendChild(grad);
        const area = document.createElementNS(NS, "path");
        area.setAttribute("d", d + `L${X(n - 1)},${Y(0)}L${X(0)},${Y(0)}Z`);
        area.setAttribute("fill", `url(#${gid})`);
        svg.appendChild(area);
      }
      const path = document.createElementNS(NS, "path");
      path.setAttribute("d", d); path.setAttribute("fill", "none");
      path.setAttribute("stroke", s.color); path.setAttribute("stroke-width", s.width || 2);
      path.setAttribute("stroke-linecap", "round");
      if (s.dash) path.setAttribute("stroke-dasharray", s.dash);
      svg.appendChild(path); drawIn(path);
    });

    /* 悬浮十字线 */
    const cross = document.createElementNS(NS, "line");
    cross.setAttribute("stroke", cssVar("--chart-cross")); cross.setAttribute("stroke-width", 1);
    cross.setAttribute("y1", pad.t); cross.setAttribute("y2", pad.t + ih);
    cross.style.opacity = 0; svg.appendChild(cross);
    const dots = cfg.series.map((s) => {
      const c = document.createElementNS(NS, "circle");
      c.setAttribute("r", 3.4); c.setAttribute("fill", s.color);
      c.setAttribute("stroke", cssVar("--card")); c.setAttribute("stroke-width", 1.6);
      c.style.opacity = 0; svg.appendChild(c); return c;
    });

    const tip = el("div", "tip");
    node.innerHTML = ""; node.appendChild(svg); node.appendChild(tip);
    svg.addEventListener("mousemove", (e) => {
      const rect = svg.getBoundingClientRect();
      const mx = ((e.clientX - rect.left) / rect.width) * W;
      const i = Math.max(0, Math.min(n - 1, Math.round(((mx - pad.l) / iw) * (n - 1))));
      cross.setAttribute("x1", X(i)); cross.setAttribute("x2", X(i)); cross.style.opacity = 1;
      let rows = "";
      cfg.series.forEach((s, si) => {
        dots[si].setAttribute("cx", X(i)); dots[si].setAttribute("cy", Y(s.values[i])); dots[si].style.opacity = 1;
        rows += `<div class="tip-row"><i style="background:${s.color}"></i>${esc(s.name)}<b>${cfg.fmt ? cfg.fmt(s.values[i]) : s.values[i].toFixed(1)}</b></div>`;
      });
      tip.innerHTML = `<div class="tip-title">${esc(cfg.labels[i])}</div>` + rows;
      tip.style.opacity = 1;
      const flip = X(i) > W * 0.62;
      tip.style.left = (flip ? rect.width * (X(i) / W) - tip.offsetWidth - 14 : rect.width * (X(i) / W) + 14) + "px";
      tip.style.top = "12px";
    });
    svg.addEventListener("mouseleave", () => {
      cross.style.opacity = 0; dots.forEach((d) => (d.style.opacity = 0)); tip.style.opacity = 0;
    });
  }

  /* ── 柱状图(支持逐根着色) ── */
  function barChart(node, cfg) {
    node._cfg = { type: "bar", cfg };
    const W = Math.max(260, node.clientWidth), H = Math.max(140, node.clientHeight);
    const pad = { l: 30, r: 8, t: 12, b: 22 };
    const iw = W - pad.l - pad.r, ih = H - pad.t - pad.b;
    const max = niceMax(Math.max.apply(null, cfg.values));
    const n = cfg.values.length;
    const bw = Math.min(26, (iw / n) * 0.62);
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("width", "100%"); svg.setAttribute("height", "100%");
    const gridColor = cssVar("--chart-grid"), labelColor = cssVar("--chart-label");
    for (let g = 0; g <= 2; g++) {
      const y = pad.t + (ih * g) / 2;
      const ln = document.createElementNS(NS, "line");
      ln.setAttribute("x1", pad.l); ln.setAttribute("x2", W - pad.r); ln.setAttribute("y1", y); ln.setAttribute("y2", y);
      ln.setAttribute("stroke", gridColor); if (g !== 2) ln.setAttribute("stroke-dasharray", "2 5");
      svg.appendChild(ln);
    }
    const tip = el("div", "tip");
    cfg.values.forEach((v, i) => {
      const x = pad.l + (iw * (i + 0.5)) / n - bw / 2;
      const h = Math.max(2, (ih * v) / max);
      const rect = document.createElementNS(NS, "rect");
      rect.setAttribute("x", x); rect.setAttribute("y", pad.t + ih - h);
      rect.setAttribute("width", bw); rect.setAttribute("height", h);
      rect.setAttribute("rx", Math.min(5, bw / 2.6));
      rect.setAttribute("fill", cfg.colors ? cfg.colors[i] : cfg.color || cssVar("--accent"));
      rect.style.transformOrigin = `${x + bw / 2}px ${pad.t + ih}px`;
      if (!reduceMotion) {
        rect.style.transform = "scaleY(0)";
        rect.style.transition = `transform .7s ${0.02 * i}s cubic-bezier(.3,.9,.3,1)`;
      }
      rect.addEventListener("mouseenter", () => {
        tip.innerHTML = `<div class="tip-title">${esc(cfg.labels[i])}</div><div class="tip-row"><b>${cfg.fmt ? cfg.fmt(v) : v.toFixed(1)}</b></div>`;
        tip.style.opacity = 1;
        tip.style.left = Math.min(W - 90, Math.max(4, x + bw / 2 - 40)) + "px"; tip.style.top = "8px";
      });
      rect.addEventListener("mouseleave", () => (tip.style.opacity = 0));
      svg.appendChild(rect);
      requestAnimationFrame(() => (rect.style.transform = "scaleY(1)"));
      if (n <= 16) {
        const tx = document.createElementNS(NS, "text");
        tx.setAttribute("x", pad.l + (iw * (i + 0.5)) / n); tx.setAttribute("y", H - 7);
        tx.setAttribute("text-anchor", "middle"); tx.setAttribute("class", "axis-x");
        tx.setAttribute("fill", labelColor); tx.textContent = cfg.labels[i];
        svg.appendChild(tx);
      }
    });
    node.innerHTML = ""; node.appendChild(svg); node.appendChild(tip);
  }

  /* ── 健康评分环 ── */
  function ringChart(node, value) {
    const NS = "http://www.w3.org/2000/svg";
    const Rr = 52, C = 2 * Math.PI * Rr;
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 128 128");
    const track = document.createElementNS(NS, "circle");
    track.setAttribute("cx", 64); track.setAttribute("cy", 64); track.setAttribute("r", Rr);
    track.setAttribute("fill", "none"); track.setAttribute("stroke", cssVar("--ring-track")); track.setAttribute("stroke-width", 9);
    svg.appendChild(track);
    const arc = document.createElementNS(NS, "circle");
    arc.setAttribute("cx", 64); arc.setAttribute("cy", 64); arc.setAttribute("r", Rr);
    arc.setAttribute("fill", "none"); arc.setAttribute("stroke", cssVar("--ring-arc"));
    arc.setAttribute("stroke-width", 9); arc.setAttribute("stroke-linecap", "round");
    arc.setAttribute("transform", "rotate(-90 64 64)");
    arc.setAttribute("stroke-dasharray", C); arc.setAttribute("stroke-dashoffset", C);
    svg.appendChild(arc);
    node.innerHTML = ""; node.appendChild(svg);
    const target = C * (1 - value / 100);
    if (reduceMotion) { arc.setAttribute("stroke-dashoffset", target); return; }
    requestAnimationFrame(() => {
      arc.style.transition = "stroke-dashoffset 1.2s cubic-bezier(.25,.9,.35,1) .15s";
      arc.setAttribute("stroke-dashoffset", target);
    });
  }

  /* ── KPI 火花线 ── */
  function sparkline(node, values, color) {
    const NS = "http://www.w3.org/2000/svg";
    const W = 120, H = 30;
    const max = Math.max.apply(null, values), min = Math.min.apply(null, values);
    const span = Math.max(1e-6, max - min);
    const pts = values.map((v, i) => [(W * i) / (values.length - 1), H - 3 - ((H - 8) * (v - min)) / span]);
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("preserveAspectRatio", "none");
    const area = document.createElementNS(NS, "path");
    area.setAttribute("d", smoothPath(pts) + `L${W},${H}L0,${H}Z`);
    area.setAttribute("fill", color); area.setAttribute("opacity", 0.13);
    svg.appendChild(area);
    const line = document.createElementNS(NS, "path");
    line.setAttribute("d", smoothPath(pts)); line.setAttribute("fill", "none");
    line.setAttribute("stroke", color); line.setAttribute("stroke-width", 1.7);
    line.setAttribute("stroke-linecap", "round");
    svg.appendChild(line);
    node.innerHTML = ""; node.appendChild(svg);
  }

  /* ── 热力图(7×24,DOM 格子,色温来自 --heat) ── */
  function heatmap(node, matrix) {
    const grid = el("div", "heat-grid");
    const days = ["一", "二", "三", "四", "五", "六", "日"];
    grid.appendChild(el("span", "heat-corner"));
    for (let h = 0; h < 24; h++) {
      if (h % 3 === 0) grid.appendChild(el("span", "heat-h", String(h).padStart(2, "0")));
      else grid.appendChild(el("span", "heat-h"));
    }
    matrix.forEach((row, d) => {
      grid.appendChild(el("span", "heat-d", days[d]));
      row.forEach((v, h) => {
        const cell = el("i", "heat-cell");
        cell.style.opacity = 0.06 + v * 0.94;
        cell.title = `周${days[d]} ${String(h).padStart(2, "0")}:00 · 活跃度 ${(v * 100) | 0}%`;
        grid.appendChild(cell);
      });
    });
    node.innerHTML = ""; node.appendChild(grid);
  }

  /* ── 应用排行行 ── */
  function rankList(node, items, colorKey, fmt) {
    const list = el("div", "rank-list");
    const max = Math.max.apply(null, items.map((it) => it[1]));
    items.forEach((it, i) => {
      const row = el("div", "rank-row");
      row.appendChild(el("span", "rank-no", "0" + (i + 1)));
      const tile = el("span", "rank-tile", esc(it[0][0]));
      tile.style.setProperty("--tile-h", (it[0].charCodeAt(0) * 47) % 360);
      row.appendChild(tile);
      row.appendChild(el("span", "rank-name", esc(it[0])));
      const bar = el("span", "rank-bar");
      const fill = el("i");
      fill.style.width = (8 + (it[1] / max) * 92) + "%";
      fill.style.background = MODULE_COLOR(colorKey);
      bar.appendChild(fill); row.appendChild(bar);
      row.appendChild(el("span", "rank-val", fmt(it[1])));
      list.appendChild(row);
    });
    node.innerHTML = ""; node.appendChild(list);
  }

  /* ── 规格右栏(静态组 + LIVE 组,data-live 供演示走秒刷新) ── */
  function specCard(node, spec, device) {
    const card = el("div");
    let html = `<div class="spec-head"><span class="t">硬件规格</span><span class="src">${esc(device)}</span></div>`;
    spec.groups.forEach((g) => {
      html += `<div class="spec-group"><div class="spec-group-name">${esc(g.name)}</div><div class="spec-rows">` +
        g.rows.map(([k, v]) => `<div class="spec-row"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`).join("") +
        `</div></div>`;
    });
    html += `<div class="spec-group"><div class="spec-group-name">运行状态<span class="rt"><span class="live-dot"></span>LIVE</span></div><div class="spec-rows">` +
      spec.live.map((lv, i) => `<div class="spec-row"><span class="k">${esc(lv[0])}</span><span class="v" data-live="${node.id}-${i}">—</span></div>`).join("") +
      `</div></div>`;
    card.innerHTML = html;
    node.innerHTML = ""; node.appendChild(card);
  }

  /* LIVE 演示走秒:围绕基准值轻微游走 */
  const liveState = new Map();
  function liveTick(data) {
    Object.entries(data.specs).forEach(([mod, spec]) => {
      spec.live.forEach((lv, i) => {
        const key = `spec-${mod}-${i}`;
        if (!liveState.has(key)) liveState.set(key, lv[1]);
        let v = liveState.get(key);
        v += (Math.random() - 0.5) * Math.abs(lv[1]) * 0.14;
        /* 负值基准(如信号 dBm)保持负值游走,正值不低于 0 */
        v = lv[1] < 0 ? Math.min(-20, v) : Math.max(0, v);
        liveState.set(key, v);
        const node = document.querySelector(`[data-live="${key}"]`);
        if (!node) return;
        node.textContent = typeof lv[1] === "number" && lv[1] % 1 !== 0
          ? v.toFixed(1) + lv[2]
          : typeof lv[1] === "number" ? Math.round(v) + lv[2] : lv[2];
      });
    });
  }

  /* ── 本机模块:分类页签 + 规格面板 ── */
  function machineModule(node, categories) {
    const tabs = el("nav", "m-tabs");
    const pane = el("div", "m-pane");
    const render = (cat) => {
      const count = cat.groups.reduce((s, g) => s + g.rows.length, 0);
      pane.innerHTML =
        `<div class="m-pane-head"><h3>${esc(cat.name)}</h3><span class="sub">${esc(cat.sub)}</span><span class="count">${count} 项</span></div>` +
        `<div class="m-pane-grid">` + cat.groups.map((g) =>
          `<div class="m-group"><h4>${esc(g.name)}</h4>` +
          g.rows.map(([k, v]) => `<div class="spec-row"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`).join("") +
          `</div>`).join("") + `</div>`;
    };
    categories.forEach((cat, i) => {
      const tab = el("button", "m-tab", esc(cat.name));
      tab.type = "button";
      if (i === 0) tab.classList.add("active");
      tab.addEventListener("click", () => {
        tabs.querySelectorAll(".m-tab").forEach((t) => t.classList.remove("active"));
        tab.classList.add("active"); render(cat);
      });
      tabs.appendChild(tab);
    });
    render(categories[0]);
    node.innerHTML = ""; node.appendChild(tabs); node.appendChild(pane);
  }

  /* ── 页面骨架:四个方案共用同一信息架构 ──
     结构修复:目录第一位是「总览」(默认落地),尾部消息归入「消息与洞察」。 */
  function scaffold() {
    const modules = [
      { id: "cpu", name: "CPU", sub: "使用率 · 核心 · 分布" },
      { id: "gpu", name: "GPU", sub: "利用率 · 分布 · 显存" },
      { id: "mem", name: "内存", sub: "占用 · 压力 · 交换" },
      { id: "net", name: "网络", sub: "下行 · 上行 · 每日流量" },
      { id: "disk", name: "磁盘", sub: "读写速率 · 每日总量" },
      { id: "power", name: "电源", sub: "功耗 · 电量 · 电池健康" },
    ];
    const navGroup = (label, links) =>
      `<div class="rail-group"><div class="rail-eyebrow">${label}</div>` +
      links.map(([id, name, badge]) =>
        `<a href="#sec-${id}" data-spy="sec-${id}"><span class="rail-dot"></span><span class="rail-label">${name}</span>${badge ? `<span class="rail-badge">${badge}</span>` : ""}</a>`).join("") +
      `</div>`;

    /* 用追加而非覆盖:保留方案页<body>里预置的装饰层(如极光环) */
    document.body.insertAdjacentHTML("beforeend", `
    <div class="shell">
      <header class="top">
        <div class="brand">
          <span class="mark"><svg viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" class="mark-bg"/><path d="M7 20 L12 12 L16 17 L20 9 L25 20" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg></span>
          <span class="brand-text"><div class="kicker">DIAGNOSTIC TELEMETRY DOSSIER</div><h1>系统监控报告</h1></span>
        </div>
        <div class="meta-chips" id="meta-chips"></div>
      </header>
      <div class="workspace">
        <aside class="rail">
          <nav class="rail-nav">
            ${navGroup("总览", [["overview", "总览"]])}
            ${navGroup("监测数据", modules.map((m) => [m.id, m.name]))}
            ${navGroup("分析", [["apps", "应用排行"], ["messages", "消息与洞察", "5"], ["table", "逐日明细"]])}
            ${navGroup("本机", [["machine", "本机信息查询"]])}
          </nav>
        </aside>
        <main class="main">
          <div class="filters">
            <span class="filter-title">时间范围</span>
            <div class="ranges" id="ranges">
              <button data-range="today" class="active">今日</button>
              <button data-range="week">近 7 天</button>
              <button data-range="month">近 30 天</button>
              <button data-range="custom">自定义</button>
              <div class="custom-pop" id="custom-pop" hidden>
                <label>起始日期<input type="date" id="cust-start"></label>
                <label>结束日期<input type="date" id="cust-end"></label>
                <button class="cust-apply" id="cust-apply">应用</button>
              </div>
            </div>
            <span class="filter-gran" id="filter-gran"></span>
            <div class="nav-progress" id="nav-progress"></div>
          </div>
          <div class="scroll" id="scroller">
            <div class="content" id="content">
              <section id="sec-overview" class="mod" data-nav>
                <div class="mod-head"><span class="idx">01</span><h2>总览</h2><span class="sub">健康评分 · 关键指标 · 全局走势</span></div>
                <div class="ov-grid">
                  <div class="card score-card">
                    <div class="card-head"><h3>健康评分</h3><span class="hint">四维加权</span></div>
                    <div class="score-body">
                      <div class="score-ring"><div id="ch-ring" class="ring"></div>
                        <div class="score-center"><span class="score-num" id="score-num"></span><span class="score-level" id="score-level"></span></div>
                      </div>
                      <div class="score-dims" id="score-dims"></div>
                    </div>
                  </div>
                  <div class="kpi-grid" id="kpi"></div>
                </div>
                <div class="card">
                  <div class="card-head"><h3>全局概览</h3><span class="hint" data-gran></span></div>
                  <div class="chart tall" id="ch-overview"></div>
                </div>
                <div class="card">
                  <div class="card-head"><h3>每周热力</h3>
                    <span class="hint heat-legend">低<span class="heat-scale"></span>高</span></div>
                  <div class="heat" id="ch-heat"></div>
                </div>
              </section>
              ${modules.map((m, i) => `
              <section id="sec-${m.id}" class="mod" data-nav>
                <div class="mod-head"><span class="idx">0${i + 2}</span><h2>${m.name}</h2><span class="sub">${m.sub}</span><span class="count">3 项</span></div>
                <div class="mod-body">
                  <div class="mod-main">
                    <div class="card"><div class="card-head"><h3 data-title="${m.id}-main"></h3><span class="hint" data-gran></span></div><div class="chart" id="ch-${m.id}"></div></div>
                    <div class="card-pair">
                      <div class="card"><div class="card-head"><h3 data-title="${m.id}-sub1"></h3></div><div class="chart short" id="ch-${m.id}-a"></div></div>
                      <div class="card"><div class="card-head"><h3 data-title="${m.id}-sub2"></h3></div><div class="chart short" id="ch-${m.id}-b"></div></div>
                    </div>
                  </div>
                  <aside class="spec" id="spec-${m.id}"></aside>
                </div>
              </section>`).join("")}
              <section id="sec-apps" class="mod" data-nav>
                <div class="mod-head"><span class="idx">08</span><h2>应用排行</h2><span class="sub">按资源消耗排序</span></div>
                <div class="apps-grid">
                  <div class="card"><div class="card-head"><h3>CPU 时间</h3></div><div id="apps-cpu"></div></div>
                  <div class="card"><div class="card-head"><h3>内存占用</h3></div><div id="apps-mem"></div></div>
                  <div class="card"><div class="card-head"><h3>GPU 时间</h3></div><div id="apps-gpu"></div></div>
                  <div class="card"><div class="card-head"><h3>网络流量</h3></div><div id="apps-net"></div></div>
                </div>
              </section>
              <section id="sec-messages" class="mod" data-nav>
                <div class="mod-head"><span class="idx">09</span><h2>消息与洞察</h2><span class="sub">系统通报 · 趋势观察</span><span class="count" id="msg-count"></span></div>
                <div class="card">
                  <div class="card-head"><h3>系统通报</h3><span class="hint">按时间倒序</span></div>
                  <div class="events" id="events"></div>
                </div>
                <div class="insights" id="insights"></div>
              </section>
              <section id="sec-table" class="mod" data-nav>
                <div class="mod-head"><span class="idx">10</span><h2>逐日明细</h2><span class="sub">聚合统计表</span></div>
                <div class="card"><div class="tbl-wrap" id="tbl"></div></div>
              </section>
              <section id="sec-machine" class="mod" data-nav>
                <div class="mod-head"><span class="idx">11</span><h2>本机信息查询</h2><span class="sub">硬件档案 · 静态规格</span><span class="count">8 类</span></div>
                <div class="card machine" id="machine"></div>
              </section>
              <footer>HagimiMonitor 生成于本机 · 所有数据保留在本地<small>原型演示数据 · 不读取真实采样</small></footer>
            </div>
          </div>
        </main>
      </div>
      <button class="to-top" id="to-top" aria-label="回到顶部">↑</button>
    </div>`);
  }

  /* ── 渲染:数据 → 骨架 ── */
  const TITLES = {
    "cpu-main": "使用率走势", "cpu-sub1": "性能核 / 能效核", "cpu-sub2": "负载分布",
    "gpu-main": "利用率走势", "gpu-sub1": "负载分布", "gpu-sub2": "显存占用",
    "mem-main": "内存占用", "mem-sub1": "内存压力", "mem-sub2": "交换与压缩",
    "net-main": "网络吞吐", "net-sub1": "下行分布", "net-sub2": "上行分布",
    "disk-main": "读写速率", "disk-sub1": "读取分布", "disk-sub2": "写入分布",
    "power-main": "功耗与电量", "power-sub1": "功耗分布", "power-sub2": "电池健康",
  };

  function render(data) {
    /* 顶栏元信息 */
    const chips = $("meta-chips"); chips.innerHTML = "";
    [data.meta.device, data.meta.model, data.meta.os, data.meta.days + " 天数据"].forEach((text) => {
      chips.appendChild(el("span", "chip", esc(text)));
    });
    document.querySelectorAll("[data-gran]").forEach((n) => (n.textContent = data.gran));
    $("filter-gran").textContent = data.gran;
    Object.entries(TITLES).forEach(([k, v]) => {
      const n = document.querySelector(`[data-title="${k}"]`); if (n) n.textContent = v;
    });

    /* 总览:评分 + KPI */
    $("score-num").textContent = data.score.value;
    $("score-level").textContent = data.score.level;
    ringChart($("ch-ring"), data.score.value);
    const dims = $("score-dims"); dims.innerHTML = "";
    data.score.dims.forEach((d) => {
      const b = el("span", "dim dim-" + d.state, `<i></i>${esc(d.name)}<em>${esc(d.raw)}</em>`);
      dims.appendChild(b);
    });
    const kpi = $("kpi"); kpi.innerHTML = "";
    data.kpis.forEach((k) => {
      const card = el("div", "kpi");
      card.innerHTML = `<div class="kpi-top"><span class="kpi-label" style="color:${MODULE_COLOR(k.key)}">${k.label}</span></div>
        <div class="kpi-value">${k.value}</div><div class="kpi-sub">${k.sub}</div><div class="kpi-spark"></div>`;
      sparkline(card.querySelector(".kpi-spark"), k.spark, MODULE_COLOR(k.key));
      kpi.appendChild(card);
    });

    /* 总览图 + 热力图 */
    const pct = (v) => v.toFixed(1) + "%";
    lineChart($("ch-overview"), { labels: data.labels, fmt: pct, max: 100, series: [
      { name: "CPU", color: MODULE_COLOR("cpu"), values: data.series.cpu },
      { name: "GPU", color: MODULE_COLOR("gpu"), values: data.series.gpu },
      { name: "内存", color: MODULE_COLOR("mem"), values: data.series.mem },
    ]});
    heatmap($("ch-heat"), data.heat);

    /* 硬件模块 */
    const s = data.series;
    lineChart($("ch-cpu"), { labels: data.labels, fmt: pct, max: 100, series: [{ name: "CPU", color: MODULE_COLOR("cpu"), values: s.cpu }] });
    barChart($("ch-cpu-a"), { labels: data.pe.labels, values: data.pe.values, fmt: pct,
      colors: data.pe.labels.map((l) => MODULE_COLOR(l[0] === "P" ? "cpu" : "mem")) });
    barChart($("ch-cpu-b"), { labels: data.dist.labels, values: data.dist.values, fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("cpu") });

    lineChart($("ch-gpu"), { labels: data.labels, fmt: pct, max: 100, series: [{ name: "GPU", color: MODULE_COLOR("gpu"), values: s.gpu }] });
    barChart($("ch-gpu-a"), { labels: data.dist.labels, values: data.dist.values.slice().reverse(), fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("gpu") });
    lineChart($("ch-gpu-b"), { labels: data.labels, fmt: (v) => v.toFixed(1) + " GB", series: [{ name: "显存", color: MODULE_COLOR("gpu"), values: s.gpu.map((v) => v / 24 + 1.2) }] });

    lineChart($("ch-mem"), { labels: data.labels, fmt: pct, max: 100, series: [
      { name: "占用", color: MODULE_COLOR("mem"), values: s.mem },
      { name: "压力", color: MODULE_COLOR("thermal"), values: s.memP, area: false, dash: "5 4" } ] });
    lineChart($("ch-mem-a"), { labels: data.labels, fmt: pct, max: 100, series: [{ name: "压力", color: MODULE_COLOR("mem"), values: s.memP }] });
    barChart($("ch-mem-b"), { labels: ["压缩", "交换", "可用", "已用"], values: [1.9, 0.4, 9.8, 13.8], fmt: (v) => v.toFixed(1) + " GB", color: MODULE_COLOR("mem") });

    lineChart($("ch-net"), { labels: data.labels, fmt: (v) => v.toFixed(0) + " MB/s", series: [
      { name: "下行", color: MODULE_COLOR("net"), values: s.down },
      { name: "上行", color: MODULE_COLOR("mem"), values: s.up } ] });
    barChart($("ch-net-a"), { labels: data.dist.labels, values: [12, 26, 34, 19, 9], fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("net") });
    barChart($("ch-net-b"), { labels: data.dist.labels, values: [34, 30, 18, 12, 6], fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("mem") });

    lineChart($("ch-disk"), { labels: data.labels, fmt: (v) => v.toFixed(0) + " MB/s", series: [
      { name: "读取", color: MODULE_COLOR("disk"), values: s.dR },
      { name: "写入", color: MODULE_COLOR("thermal"), values: s.dW, area: false } ] });
    barChart($("ch-disk-a"), { labels: data.dist.labels, values: [22, 30, 24, 15, 9], fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("disk") });
    barChart($("ch-disk-b"), { labels: data.dist.labels, values: [30, 28, 20, 13, 9], fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("thermal") });

    lineChart($("ch-power"), { labels: data.labels, series: [
      { name: "功耗", color: MODULE_COLOR("power"), values: s.power, fmt: undefined },
      { name: "电量", color: MODULE_COLOR("batt"), values: s.batt, area: false, dash: "5 4" } ],
      fmt: (v) => v.toFixed(1) });
    barChart($("ch-power-a"), { labels: data.dist.labels, values: [28, 30, 22, 13, 7], fmt: (v) => v.toFixed(0) + "%", color: MODULE_COLOR("power") });
    lineChart($("ch-power-b"), { labels: data.labels, fmt: pct, max: 100, series: [{ name: "健康度", color: MODULE_COLOR("batt"), values: s.batt.map(() => 95 + Math.random() * 1.5) }] });

    /* 规格右栏 */
    Object.entries(data.specs).forEach(([mod, spec]) => specCard($("spec-" + mod), spec, data.meta.model));

    /* 本机 */
    machineModule($("machine"), data.machine);

    /* 应用排行 */
    rankList($("apps-cpu"), data.apps.cpu, "cpu", (v) => v.toFixed(1) + "%");
    rankList($("apps-mem"), data.apps.mem, "mem", (v) => v.toFixed(1) + " GB");
    rankList($("apps-gpu"), data.apps.gpu, "gpu", (v) => v.toFixed(1) + "%");
    rankList($("apps-net"), data.apps.net, "net", (v) => v.toFixed(1) + " GB");

    /* 消息与洞察 */
    $("msg-count").textContent = data.events.length + " 条通报";
    const ev = $("events"); ev.innerHTML = "";
    data.events.forEach((e) => {
      ev.appendChild(el("div", "event sev-" + e.sev,
        `<i></i><span class="e-time">${esc(e.time)}</span><span class="e-what">${esc(e.title)}</span><span class="e-detail">${esc(e.detail)}</span>`));
    });
    const ins = $("insights"); ins.innerHTML = "";
    data.insights.forEach((it) => {
      const card = el("div", "insight");
      card.style.setProperty("--ins", MODULE_COLOR(it.tone));
      card.innerHTML = `<div class="ins-t">${esc(it.title)}</div><div class="ins-v">${esc(it.body)}</div>`;
      ins.appendChild(card);
    });

    /* 明细表 */
    const cols = [["day", "日期"], ["cpuAvg", "CPU 均"], ["cpuPeak", "CPU 峰"], ["memAvg", "内存均"], ["memP", "内存压力"],
      ["down", "下行 GB"], ["up", "上行 GB"], ["dR", "磁盘读"], ["dW", "磁盘写"], ["ac", "AC"], ["power", "功耗均"], ["cover", "覆盖"]];
    $("tbl").innerHTML = `<table><thead><tr>${cols.map((c) => `<th>${c[1]}</th>`).join("")}</tr></thead><tbody>` +
      data.table.map((row) => `<tr>${cols.map((c, i) => `<td class="${i === 0 ? "day" : ""}">${row[c[0]]}</td>`).join("")}</tr>`).join("") +
      `</tbody></table>`;

    liveTick(data);
  }

  /* ── 交互装配:滚动监听 / 进度 / 进场 / 回顶 / 范围切换 ── */
  function chrome(onRange) {
    const scroller = $("scroller");
    const links = Array.from(document.querySelectorAll("[data-spy]"));
    const secs = links.map((l) => $(l.getAttribute("data-spy"))).filter(Boolean);
    const progress = $("nav-progress");

    let ticking = false;
    let settleTimer = 0;
    const spy = () => {
      ticking = false;
      const line = scroller.getBoundingClientRect().top + 26;
      let current = secs[0];
      secs.forEach((sec) => { if (sec.getBoundingClientRect().top <= line) current = sec; });
      links.forEach((l) => l.classList.toggle("active", l.getAttribute("data-spy") === (current && current.id)));
    };
    scroller.addEventListener("scroll", () => {
      const max = scroller.scrollHeight - scroller.clientHeight;
      progress.style.width = (max > 0 ? (scroller.scrollTop / max) * 100 : 0) + "%";
      if (!ticking) { ticking = true; requestAnimationFrame(spy); }
      // 揭示动画(translateY)期间 getBoundingClientRect 含位移,滚动停稳后复核一次高亮
      clearTimeout(settleTimer);
      settleTimer = setTimeout(spy, 720);
    }, { passive: true });
    window.addEventListener("resize", spy);
    spy();

    links.forEach((l) => l.addEventListener("click", (e) => {
      e.preventDefault();
      const sec = $(l.getAttribute("data-spy"));
      if (sec) sec.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    }));

    if ("IntersectionObserver" in window && !reduceMotion) {
      const io = new IntersectionObserver((entries) => entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add("shown"); io.unobserve(en.target); }
      }), { threshold: 0.04 });
      document.querySelectorAll(".mod").forEach((sec) => { sec.classList.add("reveal"); io.observe(sec); });
    }

    const toTop = $("to-top");
    scroller.addEventListener("scroll", () => toTop.classList.toggle("show", scroller.scrollTop > 700), { passive: true });
    toTop.addEventListener("click", () => scroller.scrollTo({ top: 0, behavior: reduceMotion ? "auto" : "smooth" }));

    /* 自定义范围弹层:默认近 7 天,起止倒置时自动交换;应用后按跨度重建数据 */
    const pop = $("custom-pop"), cS = $("cust-start"), cE = $("cust-end");
    const fmtDate = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    const todayD = new Date();
    cE.value = fmtDate(todayD);
    cS.value = fmtDate(new Date(todayD.getTime() - 6 * dayMs));
    cS.max = cE.max = fmtDate(todayD);
    $("cust-apply").addEventListener("click", () => {
      if (!cS.value || !cE.value) return;
      let s = new Date(cS.value + "T00:00:00"), e = new Date(cE.value + "T00:00:00");
      if (s > e) { const t = s; s = e; e = t; }
      customSpan = { start: s, end: e };
      pop.hidden = true;
      document.querySelectorAll("#ranges button").forEach((x) => x.classList.remove("active"));
      document.querySelector('[data-range="custom"]').classList.add("active");
      onRange("custom");
    });

    document.querySelectorAll("#ranges button").forEach((b) => b.addEventListener("click", () => {
      if (b.getAttribute("data-range") === "custom") { pop.hidden = !pop.hidden; return; }
      pop.hidden = true;
      if (b.classList.contains("active")) return;
      document.querySelectorAll("#ranges button").forEach((x) => x.classList.remove("active"));
      b.classList.add("active");
      onRange(b.getAttribute("data-range"));
    }));
  }

  /* ── 启动 ── */
  function boot() {
    scaffold();
    let data = buildData("today");
    render(data);
    chrome((range) => { data = buildData(range); render(data); });
    setInterval(() => liveTick(data), 2200);

    /* 尺寸变化时按缓存配置重绘图表 */
    const redraw = (node) => { const c = node._cfg; if (!c) return;
      (c.type === "line" ? lineChart : barChart)(node, c.cfg); };
    const ro = new ResizeObserver((entries) => entries.forEach((en) => redraw(en.target)));
    document.querySelectorAll(".chart").forEach((c) => ro.observe(c));
  }

  return { boot };
})();
