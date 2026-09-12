import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 硬件清单装配器的实测测试。
///
/// 断言只依赖**这台机器必然成立的事实**(芯片名非空、物理核数 > 0、系统版本形如
/// macOS …),不锁死具体机型——换一台 Mac 跑仍应通过。完整真实清单由
/// `dumpInventory` 打印,便于人工核对。
///
/// 文案断言全部走**键**(`HardwareLabel.key`),不走显示文本:采集层的标签是
/// 本地化键,文本在编码层才解析,且测试宿主语言不固定。
// 串行执行:每个用例都会触发一次硬件采集,而采集要并发拉起十几个
// system_profiler 进程。swift-testing 默认并行跑用例,多个采集互抢资源会让
// 部分 DataType 超时返空(实测踩到过:分类整块消失)。生产路径只采集一次,
// 不存在这个竞争,所以这里只需要串行化测试。
@Suite("硬件清单装配", .serialized)
struct HardwareInventoryReaderTests {

    private func inventory() -> HardwareInventory {
        HardwareInventoryReader().capture()
    }

    private func category(_ id: String, in inventory: HardwareInventory) -> HardwareCategory? {
        inventory.categories.first { $0.id == id }
    }

    /// 按文案键取值。
    private func value(_ labelKey: String, in group: HardwareFactGroup) -> String? {
        group.facts.first { $0.label.key == labelKey }?.value
    }

    /// 跨分组查找:同一分类里字段分属不同组(如 CPU 的缓存单独一组),
    /// 断言只关心「这一条读没读到」,不该依赖它落在哪一组。
    private func value(_ labelKey: String, in category: HardwareCategory) -> String? {
        category.groups.flatMap(\.facts).first { $0.label.key == labelKey }?.value
    }

    @Test func categoriesFollowTheReportMenuOrder() {
        // 顺序即报表「本机」菜单的顺序;传感器只在 SMC 可读时出现(直连渠道),
        // 位置固定在「电源与电池」之后,所以按有无分别断言。
        let ids = inventory().categories.map(\.id)
        let expected = ["this-mac", "cpu", "gpu", "memory", "storage", "display", "power", "connectivity", "system"]
        if ids.contains("sensors") {
            var withSensors = expected
            withSensors.insert("sensors", at: 7)
            #expect(ids == withSensors)
        } else {
            #expect(ids == expected)
        }
    }

    /// 每个模块的右栏分组都必须选得到。分组选择在 Swift 侧按**组 id**完成,
    /// 报表 JS 只渲染;改组名或组结构时这条测试会先炸,而不是让右栏静默变空。
    @Test func everyModuleRailResolvesGroups() {
        let inventory = inventory()
        for module in ["cpu", "gpu", "memory", "network", "disk", "power"] {
            let groups = inventory.rails[module]
            #expect(groups != nil, "模块 \(module) 的右栏没有选到任何分组")
            #expect((groups?.isEmpty == false), "模块 \(module) 的右栏分组为空")
            let facts = (groups ?? []).flatMap(\.facts)
            #expect(facts.contains { $0.value != nil }, "模块 \(module) 的右栏一条值都没读到")
        }
    }

    /// 右栏分组必须来自它该来的分类(抽查两条,防止 railSpec 写错分类 id 或组 id)。
    @Test func moduleRailComesFromItsOwnCategory() {
        let inventory = inventory()
        #expect(inventory.rails["cpu"]?.contains { $0.id == "processor" } == true)
        #expect(inventory.rails["disk"]?.contains { $0.id == "volume" } == true)
    }

    /// 采集层的标签必须是**已声明的文案键**:解析成显示文本发生在编码层,
    /// 这里拦的是「键拼错/xcstrings 缺键」。判定依据是生产行为本身——
    /// `hwText` 对缺失键返回键本身,所以「解析结果 ≠ 键」即键已声明。
    /// 动态标签(设备名、SMC 键名)是 `text`,没有键,跳过。
    @Test func allLabelKeysAreDeclaredInCatalog() {
        for category in inventory().categories {
            #expect(hwText(category.nameKey) != category.nameKey,
                    "分类键缺失 \(category.nameKey)")
            #expect(hwText(category.subtitleKey) != category.subtitleKey,
                    "副标题键缺失 \(category.subtitleKey)")
            for group in category.groups {
                #expect(group.name.key.map { hwText($0) != $0 } ?? true,
                        "组键缺失 \(String(describing: group.name.key))")
                for fact in group.facts {
                    #expect(fact.label.key.map { hwText($0) != $0 } ?? true,
                            "标签键缺失 \(String(describing: fact.label.key))")
                }
            }
        }
    }

    /// 每个分类都必须有实质内容:不能出现「分类在、但一条都读不到」——
    /// 那说明数据源整体失效,与个别键缺失是两回事。
    @Test func everyCategoryHasReadableFacts() {
        for category in inventory().categories {
            #expect(category.factCount > 3, "分类 \(category.id) 内容过少")
            let readable = category.groups.flatMap(\.facts).filter { $0.value != nil }
            #expect(readable.count > 3, "分类 \(category.id) 几乎没有读到的值")
        }
    }

    @Test func thisMacIdentityIsReadable() throws {
        let group = try #require(category("this-mac", in: inventory())?.groups.first)
        #expect(value("hwLabelProductName", in: group) != nil)
        #expect(value("hwLabelModelId", in: group) != nil, "hw.model 应可读")
        #expect(value("hwLabelSerialNumber", in: group) != nil)
    }

    @Test func cpuTopologyIsSane() throws {
        let cpu = try #require(category("cpu", in: inventory()))
        #expect(value("hwLabelChip", in: cpu) != nil)

        let physical = try #require(value("hwLabelPhysicalCores", in: cpu).flatMap(Int.init))
        let logical = try #require(value("hwLabelLogicalCores", in: cpu).flatMap(Int.init))
        #expect(physical > 0)
        #expect(logical >= physical)

        // Apple Silicon 上 hw.nperflevels 必然 >= 1,「性能核 · 能效核」应有值
        #expect(value("hwLabelPeCores", in: cpu) != nil)
        // 缓存来自 hw.perflevel{n},两簇都应读到 → 两个值用「·」并列
        #expect(value("hwLabelL2", in: cpu)?.contains("·") == true)
        #expect(value("hwLabelL1I", in: cpu)?.contains("·") == true)
    }

    @Test func memoryInstalledCarriesUnit() throws {
        let group = try #require(category("memory", in: inventory())?.groups.first)
        let installed = try #require(value("hwLabelInstalled", in: group))
        #expect(installed.contains("GB"))
    }

    @Test func systemVersionLooksLikeMacOS() throws {
        let group = try #require(category("system", in: inventory())?.groups.first)
        let version = try #require(value("hwLabelOsVersion", in: group))
        #expect(version.hasPrefix("macOS"))
        #expect(value("hwLabelUptime", in: group) != nil, "kern.boottime 应可换算")
    }

    /// 人工核对用:打印完整清单(键名形态,文本由编码层解析)。跑测试时在日志里看。
    @Test func dumpInventoryForReview() {
        let inventory = inventory()
        var lines: [String] = ["=== 硬件清单（采集于 \(inventory.capturedAt)）==="]
        for category in inventory.categories {
            lines.append("")
            lines.append("[\(category.id)] \(category.nameKey) · \(category.factCount) 项")
            for group in category.groups {
                lines.append("  -- \(group.name.resolve { $0 }) --")
                for fact in group.facts {
                    lines.append("    \(fact.label.resolve { $0 }) = \(fact.value ?? "—")")
                }
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
