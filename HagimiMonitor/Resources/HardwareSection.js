/* 硬件模块块:把每个监控模块收进「主列 + 右栏规格」,并追加「本机」模块。
   由 StandaloneHTMLReportExporter 内联进报表主脚本,因此可以直接用模板里的
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

/* 规格行:标签左、值右;缺失值走 .missing 显示 “—”。 */
function hwRow(label, value) {
  var missing = value == null || value === "";
  return '<div class="hw-row">' +
    '<span class="k">' + hwEsc(label) + "</span>" +
    '<span class="v' + (missing ? " missing" : "") + '">' + (missing ? "—" : hwEsc(value)) + "</span></div>";
}

function hwGroupBlock(group) {
  return '<div class="hw-group"><div class="hw-group-name">' + hwEsc(group.name) + "</div>" +
    '<div class="hw-rows">' +
    group.facts.map(function (f) { return hwRow(f.label, f.value); }).join("") +
    "</div></div>";
}

function hwRailCard(spec) {
  // 分组由 App 侧选好随载荷下发(见 HardwareInventory.rails):报表不按名字猜,
  // 两侧改名不会再静默断链。
  var groups = ((DATA.hardware && DATA.hardware.rails) || {})[spec.id] || [];
  var card = el("aside", "hw-card");

  var blocks = groups.map(function (g) { return hwGroupBlock(g); });

  card.innerHTML =
    '<div class="hw-card-head"><span class="t">' + hwEsc(t("hwCardTitle")) + "</span>" +
    '<span class="src">' + hwEsc((DATA.meta && DATA.meta.device) || "") + "</span></div>" +
    (blocks.length
      ? blocks.join("")
      : '<div class="hw-group"><div class="hw-rows">' + hwRow(t("hwNoData"), null) + "</div></div>");
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
        group.facts.map(function (f) { return hwRow(f.label, f.value); }).join("") +
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
