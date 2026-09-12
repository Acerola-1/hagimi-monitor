/* 报表实时化 + 模块硬件规格区 + 本机分类菜单 —— 原型交互
   依赖 data-core.js / data-modules.js / data-machine.js。数值为演示夹具,不读取本机。 */

/* 序列按「名称」登记:内联子项里的 series 是另一批对象字面量,
   用 defs.indexOf(对象) 会查不到而拿到空数组,图表就画不出来 */
const seriesByName = {};
MODULES.forEach((m) => {
  const defs = [...m.sections, ...m.inner].flatMap((s) => s.series || []);
  const names = [...new Set(defs.map((d) => d.name))];
  seriesByName[m.id] = {};
  names.forEach((n, i) => {
    seriesByName[m.id][n] = seedSeries(m.seed + i * 2, m.base + i * 7, Math.max(3, m.amp - i * 5));
  });
});
const seriesFor = (m, s) => (s.series || []).map((sd) => seriesByName[m.id][sd.name]);

const state = { live: true, variant: 'side', w: 1240, fit: true, machineTab: 'm-self', tabs: 'strip', range: '今日', ticks: 0, sources: false };

/* ── 图表 ── */
function chartSVG(series, height = 300, width = 600) {
  const n = (series[0] || []).length || 2;
  const x = (i) => (i * width) / (n - 1);
  const y = (v) => height - 10 - (v / 100) * (height - 30);
  const paths = series.map((vals, si) => {
    const d = vals.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
    const area = si === 0 ? `<path class="area" d="${d} L${width},${height} L0,${height}Z"/>` : '';
    return area + `<path class="line s${si}" d="${d}" vector-effect="non-scaling-stroke"/>`;
  }).join('');
  const grid = [0.2, 0.45, 0.7, 0.95]
    .map((f) => `<line class="axis" x1="0" x2="${width}" y1="${(height * f).toFixed(1)}" y2="${(height * f).toFixed(1)}"/>`).join('');
  return `<svg class="chart" style="height:${height}px" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img">${grid}${paths}</svg>`;
}

/* 核心负载分布:5 档柱(与报表 distOption 同形)
   刻度用 HTML 行而不是 <text>:preserveAspectRatio="none" 会把文字横向压扁 */
function distSVG(values, height = 300) {
  const h = height, w = 600, max = Math.max(...values) || 1;
  const bw = w / values.length;
  const bars = values.map((v, i) => {
    const bh = ((v / max) * (h - 16)).toFixed(1);
    return `<rect class="bar s${Math.min(i, 2)}" x="${(i * bw + bw * 0.18).toFixed(1)}" y="${(h - 8 - bh).toFixed(1)}"
      width="${(bw * 0.64).toFixed(1)}" height="${bh}" rx="4"/>`;
  }).join('');
  return `<svg class="chart" style="height:${h}px" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" role="img">
    <line class="axis" x1="0" x2="${w}" y1="${h - 8}" y2="${h - 8}"/>${bars}</svg>`;
}
const DIST_LABELS = ['0–20%', '20–40%', '40–60%', '60–80%', '80–100%'];

const AXIS_LABELS = ['00:00', '03:00', '06:00', '09:00', '12:00', '15:00', '18:00', '21:00', '现在'];

/* ── 规格行 / 分组 ── */
/* 数据来源标注:工具条开关打开时才渲染,默认关(不干扰目测视觉) */
const ST_LABEL = { ok: '已有', new: '需新读', na: '不可得', mix: '混合' };
const srcTag = (s) => `<span class="src-tag st-${s.st}" title="${s.src}">${ST_LABEL[s.st] || s.st}</span>`;
const srcLine = (id, g) => {
  if (!state.sources) return '';
  const s = sourceFor(id, g.name);
  return s ? `<div class="src-line">${srcTag(s)}<code>${s.src}</code></div>` : '';
};

function specRows(rows, live, id, groupName) {
  return `<div class="spec-rows">${rows.map(([k, v]) => {
    const rowSrc = state.sources ? sourceForRow(id, groupName, k) : null;
    return `<div class="spec-row" data-label="${k}"${live ? ` data-live="1" data-base="${String(v).replace(/"/g, '')}"` : ''}>
      <span class="k">${k}${rowSrc ? srcTag(rowSrc) : ''}</span><span class="v">${ok(v)}</span></div>`;
  }).join('')}</div>`;
}
const specGroup = (g, id) => `<div class="spec-group" data-group="${g.name}">
  <div class="spec-group-name">${g.name}${g.live ? '<span class="rt"><span class="dot"></span>实时</span>' : ''}</div>
  ${srcLine(id, g)}
  ${specRows(g.rows, g.live, id, g.name)}</div>`;

function specCard(m) {
  const summary = m.groups[0].rows.slice(0, 3).map(([k, v]) => `${k} ${v}`).join(' · ');
  return `<aside class="spec-card card" data-spec="${m.id}">
    <div class="spec-head">
      <span class="t">硬件与配置</span>
      <span class="src">读取于 <span data-src-time>—</span></span>
      <button class="spec-copy" data-copy="${m.id}">复制</button>
    </div>
    <div class="spec-summary">${summary}</div>
    <div class="spec-body">${m.groups.map((g) => specGroup(g, m.id)).join('')}</div>
  </aside>`;
}

/* ── 模块块:主列铺开真实子项(整行卡 + 两列并排),右栏规格 ── */
function chartCard(m, s, key) {
  const series = seriesFor(m, s);
  const h = s.short ? 260 : 300;
  const body = s.dist ? distSVG(DIST_BUCKETS.map((b) => b * 100), h) : chartSVG(series, h);
  const legend = s.dist ? '' : `<span class="legend">${(s.series || []).map((sd, i) =>
    `<span><i class="s${i}"></i>${sd.name}</span>`).join('')}</span>`;
  const last = series[0] ? series[0][series[0].length - 1] : null;
  return `<div class="card chart-box">
    <div class="sec-head"><h2>${s.title}</h2><span class="hint">${s.hint || ''}</span>${legend}</div>
    ${!s.dist && last != null ? `<div class="chart-total"><strong data-total="${key}">${last.toFixed(1)}</strong><span>${m.unit}</span></div>` : ''}
    <div data-chart="${key}">${body}</div>
    <div class="chart-labels${s.dist ? ' even' : ''}">${(s.dist ? DIST_LABELS : AXIS_LABELS)
      .map((x) => `<span>${x}</span>`).join('')}</div>
  </div>`;
}

const moduleBlock = (m, indexLabel) => `<section class="module-block" id="${m.id}">
  <div class="mod-head">
    <span class="icon-chip">${icon(m.icon)}</span>
    <h2>${m.name}</h2><span class="sub">${m.sub}</span>
    <span class="meta">${m.sections.length + m.inner.length} 项</span>
    <span class="index">${indexLabel}</span>
  </div>
  <div class="mod-body">
    <div class="mod-main">
      ${m.sections.map((s, i) => chartCard(m, s, `${m.id}-s${i}`)).join('')}
      ${m.inner.length ? `<div class="inner-grid">${m.inner.map((s, i) => chartCard(m, s, `${m.id}-i${i}`)).join('')}</div>` : ''}
    </div>
    ${specCard(m)}
  </div>
</section>`;

/* ── 本机:顶栏分类菜单 + 选中分类的详细规格 ── */
const machineTab = (c) => `<button class="mtab${c.id === state.machineTab ? ' active' : ''}" data-mtab="${c.id}"
  role="tab" aria-selected="${c.id === state.machineTab}">${icon(c.icon)}<span>${c.name}</span></button>`;

function machinePane() {
  const c = MACHINE.find((x) => x.id === state.machineTab) || MACHINE[0];
  const cells = c.groups.map((g) => `<div class="card mpane-group">
      <div class="mc-head">${icon(c.icon)}<h3>${g.name}</h3>${
      g.live ? '<span class="rt"><span class="dot"></span>实时</span>' : ''}</div>
      ${srcLine(c.id, g)}
      ${specRows(g.rows, g.live, c.id, g.name)}
    </div>`).join('');
  return `<div class="machine-pane" id="machine-pane"
      data-cat="${c.id}" data-catname="${c.name}">
    <div class="mpane-head">
      <h3>${c.name}</h3><span class="sub">${c.sub}</span>
      <span class="count">${c.groups.reduce((n, g) => n + g.rows.length, 0)} 项规格</span>
    </div>
    <div class="mpane-grid">${cells}</div>
  </div>`;
}

function machineBlock(indexLabel) {
  const tabs = MACHINE.map(machineTab).join('');
  const c = MACHINE.find((x) => x.id === state.machineTab) || MACHINE[0];
  const menu = `<div class="mtab-menu">
      <label>分类</label>
      <select id="mtab-select">${MACHINE.map((x) =>
        `<option value="${x.id}"${x.id === state.machineTab ? ' selected' : ''}>${x.name}</option>`).join('')}</select>
      <span class="sub">${c.sub}</span>
    </div>`;
  const strip = `<nav class="machine-tabs" role="tablist">${tabs}</nav>`;
  const side = `<nav class="machine-tabs side" role="tablist">${tabs}</nav>`;
  const body = state.tabs === 'menu' ? menu : state.tabs === 'side' ? side : strip;
  return `<section class="module-block" id="machine">
  <div class="mod-head">
    <span class="icon-chip">${icon('device')}</span>
    <h2>本机</h2><span class="sub">10 类硬件清单 · 规格可切换</span>
    <span class="meta">${MACHINE.reduce((n, x) => n + x.groups.reduce((a, g) => a + g.rows.length, 0), 0)} 项</span>
    <span class="index">${indexLabel}</span>
  </div>
  <div class="machine-workbench" data-tabs="${state.tabs}">
    ${body}
    ${machinePane()}
  </div>
</section>`;
}

/* RAIL 是顺序的唯一来源:左栏、正文板块、序号徽章都从它派生 */
function orderedBlocks() {
  return RAIL.map((r, i) => {
    const label = pad(i + 1);
    if (r.id === 'machine') return machineBlock(label);
    const m = MODULES.find((x) => x.id === r.id);
    return m ? moduleBlock(m, label) : '';
  }).join('');
}

function widthBudget() {
  const stage = document.querySelector('.stage');
  const wrap = document.querySelector('.stage-wrap');
  stage.style.zoom = state.fit ? Math.min(1, (wrap.clientWidth - 36) / stage.offsetWidth) : 1;
  const z = parseFloat(stage.style.zoom) || 1;
  const w = (el) => (el ? el.getBoundingClientRect().width / z : 0);
  const content = stage.querySelector('.content');
  const inner = w(content) - 26 * 2;
  const main = Math.round(w(stage.querySelector('.mod-main')));
  const spec = Math.round(w(stage.querySelector('.mod-body .spec-card')));
  const box = document.querySelector('#wb');
  if (!box) return;
  box.innerHTML = `<span>窗口 <b>${state.w}</b> px</span><span>内容内宽 <b>${Math.round(inner)}</b> px</span>
    <span>主列 <b>${main}</b> px</span>
    <span>规格栏 <b>${spec}</b> px</span>
    <span>主列占 <b>${inner ? Math.round((main / inner) * 100) : 0}%</b></span>
    <span>本机分类 <b>${(MACHINE.find((x) => x.id === state.machineTab) || {}).name || ''}</b>（${state.tabs === 'strip' ? '顶栏' : state.tabs === 'menu' ? '下拉' : '左栏'}）</span>`;
}

function render() {
  const stage = document.querySelector('.stage');
  stage.dataset.w = state.w;
  stage.dataset.variant = state.variant;
  const rail = RAIL.map((r) => `<a href="#${r.id}" data-jump="${r.id}">${icon(r.icon)}<span>${r.label}</span></a>`).join('');
  document.querySelector('.shell').innerHTML = `
    <header class="top">
      <div class="brand"><span class="mark"></span>
        <div><div class="kicker">HAGIMI / DIAGNOSTIC DOSSIER</div><h1>硬件全景报表</h1></div>
      </div>
      <div class="meta-chips">
        <span class="chip">Mac16,1</span><span class="chip">Apple M4</span><span class="chip">24 GB</span>
        <span class="chip" id="mode-chip">${state.live ? '实时 · 每秒追加' : '快照 · 定于 ' + fmtMinute()}</span>
      </div>
    </header>
    <div class="workspace">
      <aside class="rail"><div class="eyebrow">模块</div>
        <nav class="module-nav">${rail}</nav>
        <div class="rail-footer"><span class="status-dot"></span>全部数据保存在本机<small>Mac16,1 · macOS 27.0</small></div>
      </aside>
      <main class="main">
        <div class="filters">
          <span class="filter-title">时间范围</span>
          <div class="range-controls">
            <div class="ranges">${['今日', '近 7 天', '近 30 天', '近一年'].map((r) =>
              `<button data-range="${r}" class="${r === state.range ? 'active' : ''}"${
                state.live && r !== '今日' ? ' disabled' : ''}>${r}</button>`).join('')}</div>
            <button class="live-toggle" id="live-toggle" aria-pressed="${state.live}">
              <span class="dot"></span>${state.live ? '实时' : '已暂停'}</button>
          </div>
          <div class="nav-progress" id="nav-progress"></div>
        </div>
        <div class="scroll" id="scroller"><div class="content">
          <div class="lead"><span class="tag">原型 v3</span>
            <div><b>本轮改动：</b>每个监控模块按正式报表的真实子项铺开（CPU/GPU/电源 = 1 整行 + 2 并排，
              网络/磁盘 = 1 整行 + 1 短条，内存 = 仅 1 整行），可以看出「模块有多个项目」时的实际布局；
              「本机」改为<b>顶栏分类菜单</b>（10 类可切换），不再把明细铺在一页。<br>
              右栏宽度：<b>1240 / 1280 → 300pt</b>，<b>1040 → 260pt</b>，<b>860 → 下移到图表下方</b>。
              本机分类菜单形态可在工具条切换（顶栏 / 下拉 / 左栏）。</div>
          </div>
          ${orderedBlocks()}
          <div class="footnote">布局原型 · 所有数值为演示夹具，不代表本机读数。<br>
            正式实现：模板与 ECharts 复用现有报表，Swift 侧每秒把当前分钟桶增量推入 DOM；导出仍走既有快照路径。</div>
        </div></div>
      </main>
    </div>`;
  bindStage();
  widthBudget();
  document.querySelectorAll('[data-src-time]').forEach((e) => (e.textContent = fmtClock()));
}

/* ── 实时:曲线追加 + 运行状态/传感器刷新 ── */
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const rndf = (n) => Math.random() * n;
/* 归在实时分组里但本身是固定值的行:硬件上限与数量不随采样变化 */
const STATIC_IN_LIVE = new Set(['转速下限', '转速上限', '风扇数量']);

const LIVE = {
  热压力: () => pick(['正常', '正常', '正常', '热压力 1']),
  进程数: () => String(600 + Math.floor(rndf(20))),
  空闲占比: () => `${(72 + rndf(5)).toFixed(1)}%`,
  显存占用: () => `${(4.5 + rndf(0.7)).toFixed(2)} GB`,
  时钟态: () => pick(['低', '中', '高']),
  核心温度: () => `${(43 + rndf(4)).toFixed(1)} ℃`,
  GPU功耗: () => `${(1.2 + rndf(1.6)).toFixed(1)} W`,
  压缩内存: () => `${(1.2 + rndf(0.5)).toFixed(2)} GB`,
  可用: () => `${(15 + rndf(1.4)).toFixed(1)} GB`,
  信号强度: () => `−${46 + Math.floor(rndf(5))} dBm`,
  噪声: () => `−${90 + Math.floor(rndf(4))} dBm`,
  信噪比: () => `${44 + Math.floor(rndf(3))} dB`,
  电池温度: () => `${(31 + rndf(1.4)).toFixed(1)} ℃`,
  整机功耗: () => `${(17 + rndf(4)).toFixed(1)} W`,
  CPU功耗: () => `${(2.6 + rndf(1.6)).toFixed(1)} W`,
  读速率: () => `${(180 + rndf(600)).toFixed(0)} MB/s`,
  写速率: () => `${(60 + rndf(300)).toFixed(0)} MB/s`,
  风扇1: () => pick(['0 RPM · 停转', '0 RPM · 停转', '0 RPM · 停转', '2 340 RPM']),
  风扇2: () => `${(1140 + rndf(120)).toFixed(0)} RPM`,
};

function updateChart(m, s, key) {
  const holder = document.querySelector(`[data-chart="${key}"]`);
  if (!holder) return;
  const h = s.short ? 260 : 300;
  holder.innerHTML = s.dist ? distSVG(DIST_BUCKETS.map((b) => b * 100), h) : chartSVG(seriesFor(m, s), h);
  const total = document.querySelector(`[data-total="${key}"]`);
  const first = seriesFor(m, s)[0];
  if (total && first) total.textContent = first[first.length - 1].toFixed(1);
}

function tick() {
  if (document.hidden) return;
  state.ticks += 1;
  MODULES.forEach((m) => {
    const store = seriesByName[m.id];
    Object.keys(store).forEach((name, i) => {
      const arr = store[name];
      const last = arr[arr.length - 1];
      // 向移动目标回归而不是自由游走,避免长时间运行后漂到不合理区间
      const target = m.base + i * 7 + Math.sin(state.ticks * 0.09 + i * 1.7) * m.amp * 0.75
        + (Math.random() - 0.5) * m.amp * 0.45;
      arr.push(Math.max(2, Math.min(96, last * 0.72 + target * 0.28)));
      if (arr.length > 60) arr.shift();
    });
    // 逐个子项更新自己的图与合计(每个子项有独立的 data-chart key)
    m.sections.forEach((s, i) => updateChart(m, s, `${m.id}-s${i}`));
    m.inner.forEach((s, i) => updateChart(m, s, `${m.id}-i${i}`));
  });
  document.querySelectorAll('.spec-row[data-live="1"]').forEach((row) => {
    const label = row.dataset.label.replace(/\s/g, '');
    const v = row.querySelector('.v');
    const raw = row.dataset.base || '';
    if (STATIC_IN_LIVE.has(label)) return;   // 硬件上限/数量等本来就不该变
    if (LIVE[label]) { v.textContent = LIVE[label](); return; }
    // 去千分位再解析:"6 800 RPM" 用 parseFloat 会读成 6
    const base = parseFloat(raw.replace(/[\s,]/g, ''));
    if (Number.isNaN(base)) return;
    if (raw.includes('℃')) v.textContent = `${(base + rndf(1.6) - 0.8).toFixed(1)} ℃`;
    else if (raw.includes('RPM')) v.textContent = `${groupNum(Math.round(base + rndf(120) - 60))} RPM`;
  });
  // 「最热」是派生值:取同组各键的最大值,不能各自独立抖动(否则会低于单键)
  document.querySelectorAll('.spec-row[data-label="最热"]').forEach((row) => {
    const group = row.closest('.mpane-group');
    if (!group) return;
    const temps = [...group.querySelectorAll('.spec-row[data-live="1"]')]
      .filter((r) => r.dataset.label !== '最热')
      .map((r) => parseFloat(r.querySelector('.v').textContent))
      .filter((n) => !Number.isNaN(n));
    if (temps.length) row.querySelector('.v').textContent = `${Math.max(...temps).toFixed(1)} ℃`;
  });
  const chip = document.querySelector('#mode-chip');
  if (chip && state.live) chip.textContent = `实时 · ${fmtClock()}`;
}

/* ── 交互 ── */
function bindStage() {
  const scroller = document.querySelector('#scroller');
  const progress = document.querySelector('#nav-progress');
  // 跳转落点用 rect 差算:offsetTop 会带上外层偏移与 zoom
  const jump = (id) => {
    const target = document.getElementById(id);
    if (!target) return;
    const z = parseFloat(document.querySelector('.stage').style.zoom) || 1;
    const delta = (target.getBoundingClientRect().top - scroller.getBoundingClientRect().top) / z;
    scroller.scrollTo({ top: Math.max(0, scroller.scrollTop + delta - 8), behavior: 'smooth' });
  };
  document.querySelectorAll('[data-jump]').forEach((a) => a.addEventListener('click', (e) => {
    e.preventDefault(); jump(a.dataset.jump);
  }));
  document.querySelector('#live-toggle')?.addEventListener('click', () => {
    state.live = !state.live;
    if (state.live) state.range = '今日';
    const top = scroller.scrollTop; render(); scroller.scrollTop = top;
  });
  document.querySelectorAll('[data-range]').forEach((b) => b.addEventListener('click', () => {
    if (b.disabled) return;
    state.range = b.dataset.range; state.live = state.range === '今日';
    const top = scroller.scrollTop; render(); scroller.scrollTop = top;
  }));
  // 本机分类:只换面板,不重建整页(否则会丢滚动位置)
  const swapPane = (id) => {
    state.machineTab = id;
    document.querySelectorAll('.mtab').forEach((t) => {
      const on = t.dataset.mtab === id;
      t.classList.toggle('active', on); t.setAttribute('aria-selected', String(on));
    });
    document.querySelector('#machine-pane').outerHTML = machinePane();
    widthBudget();
  };
  document.querySelectorAll('.mtab').forEach((t) => t.addEventListener('click', () => swapPane(t.dataset.mtab)));
  document.querySelector('#mtab-select')?.addEventListener('change', (e) => swapPane(e.target.value));
  document.querySelectorAll('[data-copy]').forEach((b) => b.addEventListener('click', async () => {
    const id = b.dataset.copy;
    const m = MODULES.find((x) => x.id === id);
    const text = m
      ? `[${m.name}] ${m.sub}\n` + m.groups.map((g) => `-- ${g.name} --\n` + g.rows.map(([k, v]) => `${k}: ${v}`).join('\n')).join('\n')
      : MACHINE.map((c) => `[${c.name}]\n` + c.groups.flatMap((g) => g.rows.map(([k, v]) => `${k}: ${v}`)).join('\n')).join('\n\n');
    try { await navigator.clipboard.writeText(text); b.textContent = '已复制'; }
    catch { b.textContent = '复制失败'; }
    setTimeout(() => (b.textContent = m ? '复制' : '复制全部'), 1400);
  }));
  let ticking = false;
  const spy = () => {
    ticking = false;
    const line = scroller.getBoundingClientRect().top + 28;
    let current = null;
    document.querySelectorAll('.module-block').forEach((s) => {
      if (s.getBoundingClientRect().top <= line) current = s.id;
    });
    document.querySelectorAll('.module-nav a').forEach((a) => a.classList.toggle('active', a.dataset.jump === current));
    const max = scroller.scrollHeight - scroller.clientHeight;
    if (progress) progress.style.width = (max > 0 ? (scroller.scrollTop / max) * 100 : 0) + '%';
  };
  scroller.addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(spy); } }, { passive: true });
  spy();
}

function bindProto() {
  document.querySelectorAll('[data-variant-btn]').forEach((b) => b.addEventListener('click', () => {
    state.variant = b.dataset.variantBtn;
    document.querySelectorAll('[data-variant-btn]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    const top = document.querySelector('#scroller')?.scrollTop || 0; render();
    const s = document.querySelector('#scroller'); if (s) s.scrollTop = top;
  }));
  document.querySelectorAll('[data-tabs-btn]').forEach((b) => b.addEventListener('click', () => {
    state.tabs = b.dataset.tabsBtn;
    document.querySelectorAll('[data-tabs-btn]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    const top = document.querySelector('#scroller')?.scrollTop || 0; render();
    const s = document.querySelector('#scroller'); if (s) s.scrollTop = top;
  }));
  document.querySelectorAll('[data-w-btn]').forEach((b) => b.addEventListener('click', () => {
    state.w = Number(b.dataset.wBtn);
    document.querySelectorAll('[data-w-btn]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    document.querySelector('.stage').dataset.w = state.w; widthBudget();
  }));
  document.querySelector('#fit-btn')?.addEventListener('click', (e) => {
    state.fit = !state.fit;
    e.target.setAttribute('aria-pressed', String(state.fit));
    widthBudget();
  });
  document.querySelector('#src-btn')?.addEventListener('click', (e) => {
    state.sources = !state.sources;
    e.target.setAttribute('aria-pressed', String(state.sources));
    const top = document.querySelector('#scroller')?.scrollTop || 0; render();
    const s = document.querySelector('#scroller'); if (s) s.scrollTop = top;
  });
  document.addEventListener('click', (e) => {
    if (e.target.closest('.spec-copy')) return;
    if (state.variant !== 'collapsed') return;
    const head = e.target.closest('.spec-head');
    if (head) head.closest('.spec-card').classList.toggle('open');
  });
}

function boot() {
  render(); bindProto();
  setInterval(tick, 1000);
  window.addEventListener('resize', widthBudget);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });
}
boot();
