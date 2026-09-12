import Foundation

/// 报表硬件文案解析:短键 → `stats.r.<key>`。与报表框架文案、JS 的 `t()`
/// 同一命名空间与解析路径。键缺失返回键本身——裸键名上屏一眼可见,
/// 比静默错译好排查(测试也据此拦缺失键)。
func hwText(_ key: String) -> String {
    Bundle.main.localizedString(forKey: "stats.r.\(key)", value: nil, table: nil)
}

/// 规格行的显示标签。
///
/// 硬件文案的本地化键一律是**短键**(如 `hwLabelProductName`),真实键为
/// `stats.r.<key>`,与报表框架文案同一命名空间;文本解析统一发生在
/// `StatisticsReportBuilder` 的编码层——采集层与测试只认 key,不断言文本
/// (测试宿主语言不固定,文本断言会在英文环境翻车)。
enum HardwareLabel: Sendable, Equatable {
    /// 静态文案。
    case key(String)
    /// 带插值的文案:条目含 %@ 占位,args 依序填充(如「USB（%@ 台设备）」)。
    case keyed(String, [String])
    /// 动态数据本身作标签(蓝牙/USB 设备名、SMC 键名),不经本地化。
    case text(String)

    /// 解析成显示文本。lookup 输入短键,返回本地化文本。
    func resolve(_ lookup: (String) -> String) -> String {
        switch self {
        case .key(let key):
            return lookup(key)
        case .keyed(let key, let args):
            return String(format: lookup(key), arguments: args)
        case .text(let text):
            return text
        }
    }

    /// 短键(`text` 返 nil)。railSpec 选组与测试断言用它,不用显示文本。
    var key: String? {
        switch self {
        case .key(let key), .keyed(let key, _): return key
        case .text: return nil
        }
    }
}

/// 硬件清单的数据模型。
///
/// 报表的「本机」模块要按分类展示几百条规格,分类之间结构一致:
/// 分类 → 分组 → 规格行(标签 + 值)。所以模型只做三层,不引入第四层。
///
/// `value` 为 nil 表示这一条**读不到**(键不存在、系统未提供、权限不足),
/// 由渲染端显示 `—`。绝不用 0 / "未知" / 空串兜底——缺失与零是两回事。
/// `value` 里系统透传的原始文本(system_profiler 返回值)跟随系统语言,
/// 不再本地化;只有采集层自己拼的枚举文案(是/否/支持…)在构造点解析。
struct HardwareFact: Sendable, Equatable {
    let label: HardwareLabel
    let value: String?
}

struct HardwareFactGroup: Sendable, Equatable {
    /// 稳定标识。railSpec 按它选组,不按组名——组名已本地化,不能当契约。
    /// 多实例组(多块卷、多台显示器)共享同一个 id,匹配按等值即可。
    let id: String
    let name: HardwareLabel
    let facts: [HardwareFact]

    init(id: String, name: HardwareLabel, facts: [HardwareFact]) {
        self.id = id
        self.name = name
        self.facts = facts
    }
}

struct HardwareCategory: Sendable, Equatable, Identifiable {
    /// 稳定标识(与报表左栏/分类菜单的 key 对齐),如 `cpu` / `storage` / `system`。
    let id: String
    /// 展示名与副标题的文案短键(真实键 `stats.r.<key>`),编码层解析。
    let nameKey: String
    let subtitleKey: String
    let groups: [HardwareFactGroup]

    /// 该分类的规格条数,用于菜单上的「N 项」与空态判断。
    var factCount: Int { groups.reduce(0) { $0 + $1.facts.count } }
}

/// 一次完整采集的结果。
///
/// 采集是**一次性**的:只在打开报表或用户手动刷新时跑,不跟每秒采样
/// (16 个 system_profiler DataType 本机实测约 2.1 秒,不能挂在采样路径上)。
struct HardwareInventory: Sendable, Equatable {
    let categories: [HardwareCategory]
    /// 每个监控模块右栏要展示的分组:模块 id(cpu/gpu/memory/network/disk/power)→ 分组。
    ///
    /// **选择在 Swift 侧完成**,报表 JS 只负责渲染。早先 JS 按组名做前缀匹配,
    /// 分组名与其消费者分处两种语言、两套文件,改一侧就静默断链且无人测得到;
    /// 现在按组 id 等值匹配,`HardwareInventoryReaderTests` 锁住每个模块都能选到分组。
    let rails: [String: [HardwareFactGroup]]
    let capturedAt: Date
}
