/* 硬件模块块:把每个监控模块收进「主列 + 右栏规格」,并追加「本机」模块。
   由 StatisticsReportBuilder 内联进报表主脚本,因此可以直接用模板里的
   $ / el / sf / I / DATA 与 reduceMotion,不需要另建通信层。 */

/* 模块 → 右栏规格:anchor 是要收进主列的板块 id,groups 是该模块要展示的硬件分组。
   分组名按**前缀**匹配——磁盘的卷组名带卷名(「卷 · Macintosh HD」),写全名没法匹配。 */
var HW_MODULES = [
  { id: "cpu", label: "kCpu", icon: "cpu", members: ["sec-cpu"], absorbInner: true },
  { id: "gpu", label: "kGpu", icon: "gpu", members: ["sec-gpu"], absorbInner: true },
  { id: "memory", label: "kMem", icon: "mem", members: ["sec-mem"] },
  { id: "network", label: "railNet", icon: "net", members: ["sec-net", "sec-net-daily"] },
  { id: "disk", label: "railDisk", icon: "disk", members: ["sec-disk", "sec-disk-daily"] },
  { id: "power", label: "railPower", icon: "power", members: ["sec-power", "sec-batt"] }
];

/* 本机分类的图标:sf-* 类名由生成端按 SF Symbols 内联。 */
var HW_CATEGORY_ICON = {
  "this-mac": "device", cpu: "cpu", gpu: "gpu", memory: "mem", storage: "disk",
  display: "display", power: "batt", sensors: "thermal", connectivity: "net", system: "os"
};

function hwCategories() {
  return (DATA.hardware && DATA.hardware.categories) || [];
}

function hwCategory(id) {
  return hwCategories().filter(function (c) { return c.id === id; })[0] || null;
}

function hwEsc(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/* 规格行:标签左、值右;缺失值走 .missing 显示 “—”。
   scope + dataLabel 供实时推送按 (分类, 行键) 定位到具体一行;
   dataLabel 缺省时与显示文本相同(静态规格行就是文本,live 行是短键)。 */
function hwRow(scope, label, value, dataLabel) {
  var missing = value == null || value === "";
  var key = dataLabel || label;
  return '<div class="hw-row" data-hw-scope="' + hwEsc(scope) + '" data-hw-label="' + hwEsc(key) + '">' +
    '<span class="k">' + hwEsc(label) + "</span>" +
    '<span class="v' + (missing ? " missing" : "") + '">' + (missing ? "—" : hwEsc(value)) + "</span></div>";
}

function hwGroupBlock(scope, group) {
  return '<div class="hw-group"><div class="hw-group-name">' + hwEsc(group.name) + "</div>" +
    '<div class="hw-rows">' +
    group.facts.map(function (f) { return hwRow(scope, f.label, f.value); }).join("") +
    "</div></div>";
}

/* 每个模块右栏的「运行状态」组:这些行的值由 Swift 侧每秒推送(见
   window.__HAGIMI_HARDWARE_LIVE__)。数组元素是文案短键(stats.r.hwLive*),
   显示时经 t() 解析,data-hw-label 也存短键——推送与匹配走 key,不走显示文本,
   两种语言的界面上都能对上行。初始一律显示 “—”,等第一帧推送填上——
   宁可先空着,也不要拿快照的历史均值冒充实时读数。 */
var HW_LIVE_ROWS = {
  cpu: ["hwLiveCpuUsage", "hwLiveThermal", "hwLiveProcessCount", "hwLiveIdle"],
  gpu: ["hwLiveGpuUsage", "hwLiveGpuMemory", "hwLiveRenderer", "hwLiveTiler"],
  memory: ["hwLiveMemUsed", "hwLiveCompressed", "hwLiveSwap", "hwLivePressure"],
  network: ["hwLiveDownload", "hwLiveUpload", "hwLiveSignal"],
  disk: ["hwLiveDiskUsed", "hwLiveDiskFree", "hwLiveDiskRead", "hwLiveDiskWrite"],
  power: ["hwLiveBatteryLevel", "hwLiveBatteryState", "hwLiveBatteryTemp"]
};

function hwRailCard(spec) {
  // 分组由 App 侧选好随载荷下发(见 HardwareInventory.rails):报表不按名字猜,
  // 两侧改名不会再静默断链。
  var groups = ((DATA.hardware && DATA.hardware.rails) || {})[spec.id] || [];
  var card = el("aside", "hw-card");
  card.setAttribute("data-hw-scope", spec.id);

  var blocks = groups.map(function (g) { return hwGroupBlock(spec.id, g); });
  var liveLabels = HW_LIVE_ROWS[spec.id] || [];
  if (liveLabels.length) {
    blocks.push(
      '<div class="hw-group"><div class="hw-group-name">' + hwEsc(t("hwLiveGroup")) +
      '<span class="rt"><span class="dot"></span>' + hwEsc(t("hwLiveTag")) + "</span></div>" +
      '<div class="hw-rows">' +
      liveLabels.map(function (key) { return hwRow(spec.id, t(key), null, key); }).join("") +
      "</div></div>");
  }

  card.innerHTML =
    '<div class="hw-card-head"><span class="t">' + hwEsc(t("hwCardTitle")) + "</span>" +
    '<span class="src">' + hwEsc((DATA.meta && DATA.meta.device) || "") + "</span></div>" +
    (blocks.length
      ? blocks.join("")
      : '<div class="hw-group"><div class="hw-rows">' + hwRow(spec.id, t("hwNoData"), null) + "</div></div>");
  return card;
}

/* 把一个模块的若干板块收进「主列 + 右栏」,返回新建的模块块。 */
function hwBuildModule(spec, index) {
  var first = $(spec.members[0]);
  if (!first) return null;

  var nodes = spec.members.map(function (id) { return $(id); }).filter(Boolean);
  if (spec.absorbInner && nodes.length) {
    // CPU / GPU 的并列子卡是没有 id 的 section.inner-grid,紧跟在本模块主板块之后。
    var cursor = nodes[0].nextElementSibling;
    while (cursor && cursor.tagName === "SECTION" && cursor.classList.contains("inner-grid")) {
      nodes.push(cursor);
      cursor = cursor.nextElementSibling;
    }
  }

  // 「N 项」数的是**卡片数**,不是 DOM 板块数:一个 inner-grid 里可能并排两张卡。
  var cardCount = nodes.reduce(function (sum, node) {
    return sum + node.querySelectorAll(".card").length;
  }, 0);

  var block = el("section", "module-block");
  block.id = "mod-" + spec.id;
  // 模块头:石板墨大标题 + 卡片数
  block.innerHTML =
    '<div class="mod-head">' +
    "<h2>" + hwEsc(t(spec.label)) + "</h2>" +
    '<span class="meta">' + cardCount + " " + hwEsc(t("hwItemCount")) + "</span>" +
    "</div>";

  // 顺序很重要:必须**先把块插进文档、再把板块搬进主列**。
  // 反过来的话 `first` 已经不在原父节点下,`insertBefore(block, first)` 会报
  // 「新子节点包含父节点」,而且板块已经被搬离文档——整块模块会凭空消失。
  var body = el("div", "mod-body");
  var main = el("div", "mod-main");
  body.appendChild(main);
  body.appendChild(hwRailCard(spec));
  block.appendChild(body);

  var parent = first.parentNode;
  parent.insertBefore(block, first);
  nodes.forEach(function (node) { main.appendChild(node); });
  return block;
}

/* ── 本机模块:顶栏分类菜单 + 选中分类的详细规格 ── */
var hwActiveCategory = null;
/* 规格面板的已见最大高度(px):各分类内容长短不一,面板高度取历史最大值固定,
   切换分类时整块高度不再塌缩,滚动位置与模块头(顶部栏目)保持原位。 */
var hwPaneMaxHeight = 0;

function hwPane(category) {
  var pane = document.querySelector("#mod-machine .hw-pane");
  if (!pane || !category) return;
  var count = category.groups.reduce(function (sum, g) { return sum + g.facts.length; }, 0);
  pane.innerHTML =
    '<div class="hw-pane-head"><h3>' + hwEsc(category.name) + "</h3>" +
    '<span class="sub">' + hwEsc(category.subtitle) + "</span>" +
    '<span class="count">' + count + " " + hwEsc(t("hwItemCount")) + "</span></div>" +
    '<div class="hw-pane-grid">' +
    category.groups.map(function (group) {
      return '<div class="hw-pane-group"><h4>' + hwEsc(group.name) + "</h4>" +
        '<div class="hw-rows">' +
        group.facts.map(function (f) { return hwRow(category.id, f.label, f.value); }).join("") +
        "</div></div>";
    }).join("") + "</div>";
  // 渲染后同步测量并抬高固定高度(强制布局一次,切换频率低,开销可忽略)
  var height = pane.offsetHeight;
  if (height > hwPaneMaxHeight) {
    hwPaneMaxHeight = height;
    pane.style.minHeight = hwPaneMaxHeight + "px";
  }
}

function hwSelectCategory(id) {
  var category = hwCategory(id);
  if (!category) return;
  hwActiveCategory = id;
  document.querySelectorAll("#mod-machine .hw-tab").forEach(function (tab) {
    var on = tab.getAttribute("data-hw-category") === id;
    tab.classList.toggle("active", on);
    tab.setAttribute("aria-selected", on ? "true" : "false");
  });
  hwPane(category);
}

function hwBuildMachine(index) {
  var categories = hwCategories();
  if (!categories.length) return null;

  var block = el("section", "module-block");
  block.id = "mod-machine";
  block.innerHTML =
    '<div class="mod-head">' +
    "<h2>" + hwEsc(t("kThisMac")) + "</h2>" +
    '<span class="meta">' + categories.length + " " + hwEsc(t("hwCategoryCount")) + "</span>" +
    "</div>";

  var workbench = el("div", "hw-workbench");
  var tabs = el("nav", "hw-tabs");
  tabs.setAttribute("role", "tablist");
  categories.forEach(function (category) {
    var tab = el("button", "hw-tab");
    tab.type = "button";
    tab.setAttribute("role", "tab");
    tab.setAttribute("data-hw-category", category.id);
    tab.innerHTML = sf(HW_CATEGORY_ICON[category.id] || "device") +
      "<span>" + hwEsc(category.name) + "</span>";
    tab.addEventListener("click", function () { hwSelectCategory(category.id); });
    tabs.appendChild(tab);
  });
  var pane = el("div", "hw-pane");
  workbench.appendChild(tabs);
  workbench.appendChild(pane);
  block.appendChild(workbench);

  // 插在本机模块应在的位置:内容区末尾(分析板块之后、页脚之前),
  // 与左栏导航分组顺序「总览 / 监测数据 / 分析 / 本机信息查询」保持一致。
  var content = $("content");
  var footer = content && content.querySelector(":scope > footer");
  if (content && footer) {
    content.insertBefore(block, footer);
  } else if (content) {
    content.appendChild(block);
  } else {
    var power = $("mod-power");
    if (power && power.parentNode) power.parentNode.insertBefore(block, power.nextSibling);
  }
  hwSelectCategory(categories[0].id);
  return block;
}

/* 组装:先收模块,再追加本机。已有锚点缺失时整段静默跳过,报表照常可用。 */
function buildHardwareLayout() {
  if (!hwCategories().length) return;
  var index = 0;
  HW_MODULES.forEach(function (spec) {
    if (hwBuildModule(spec, ++index)) return;
    index -= 1;
  });
  hwBuildMachine(++index);
}

/* ── 实时推送入口 ──────────────────────────────────────────
   Swift 侧按 (作用域, 标签) 推送当前读数;作用域是模块 id 或本机分类 id。
   只更新列在 values 里的行:静态规格不会被碰,所以「规格 vs 读数」的区分是数据驱动的。 */
window.__HAGIMI_HARDWARE_LIVE__ = function (values) {
  if (!values) return;
  Object.keys(values).forEach(function (scope) {
    var readings = values[scope] || {};
    Object.keys(readings).forEach(function (label) {
      var selector = '[data-hw-scope="' + CSS.escape(scope) + '"][data-hw-label="' + CSS.escape(label) + '"]';
      document.querySelectorAll(selector).forEach(function (row) {
        var value = row.querySelector(".v");
        if (!value) return;
        var text = readings[label];
        var missing = text == null || text === "";
        value.textContent = missing ? "—" : text;
        value.classList.toggle("missing", missing);
      });
    });
  });
};
