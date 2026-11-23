import Foundation

/// 动力类型（纯电 BEV / 增程 REEV）
public enum PowertrainType: String, Codable, CaseIterable, Sendable {
    case bev = "BEV"
    case reev = "REEV"

    public var displayName: String {
        switch self {
        case .bev: return "纯电"
        case .reev: return "增程"
        }
    }
}

/// 车身形态枚举
public enum CarBodyStyle: String, Codable, Sendable {
    case suv
    case sedan
    case hatchback
    case mpv
    case micro

    /// 用于车型展厅展示的中文车身形态标签
    public var displayName: String {
        switch self {
        case .suv: return "SUV"
        case .sedan: return "轿车"
        case .hatchback: return "两厢"
        case .mpv: return "MPV"
        case .micro: return "微车"
        }
    }
}

/// 座椅布局枚举（对应原包 `EnumC1499k10`）
public enum SeatLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case four = "2+2"
    case five = "2+3"
    case six = "2+2+2"
    case seven = "2+3+2"
    case mpvSeven = "2+2+3"

    public var id: String { rawValue }

    public var totalSeats: Int {
        switch self {
        case .four: return 4
        case .five: return 5
        case .six: return 6
        case .seven, .mpvSeven: return 7
        }
    }

    public var displayName: String {
        "\(totalSeats) 座 (\(rawValue))"
    }

    /// 对应 `seat_labels.png` 像素灰度标签列表
    public var seatRoles: [SeatRole] {
        switch self {
        case .four:
            return [.driver, .passenger, .rearLeft, .rearRight]
        case .five:
            return [.driver, .passenger, .rearLeft, .rearRight, .rearCenter]
        case .six:
            return [.driver, .passenger, .rearLeft, .rearRight, .thirdLeft, .thirdRight]
        case .seven:
            return [.driver, .passenger, .rearLeft, .rearRight, .rearCenter, .thirdLeft, .thirdRight]
        case .mpvSeven:
            return [.driver, .passenger, .rearLeft, .rearRight, .thirdLeft, .thirdRight, .thirdCenter]
        }
    }
}

/// 座椅编号与语义映射（对应 `seat_labels.png` 像素值 1~8）
public enum SeatRole: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case driver = 1
    case passenger = 2
    case rearLeft = 3
    case rearRight = 4
    case thirdLeft = 5
    case thirdRight = 6
    case rearCenter = 7
    case thirdCenter = 8

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .driver: return "主驾"
        case .passenger: return "副驾"
        case .rearLeft: return "二排左"
        case .rearRight: return "二排右"
        case .thirdLeft: return "三排左"
        case .thirdRight: return "三排右"
        case .rearCenter: return "二排中"
        case .thirdCenter: return "三排中"
        }
    }

    /// 对应远程控车接口 `cmdid="301"`/`"370"` 的 `position` 参数
    public var controlPosition: String? {
        switch self {
        case .driver: return "left_front"
        case .passenger: return "right_front"
        case .rearLeft: return "left_rear"
        case .rearRight: return "right_rear"
        default: return nil
        }
    }

    /// 对应车内特效图文件名中的位置前缀（例如 `seat_driver_heat.webp`）
    public var fxPrefix: String? {
        switch self {
        case .driver: return "driver"
        case .passenger: return "passenger"
        case .rearLeft: return "rear_left"
        case .rearRight: return "rear_right"
        default: return nil
        }
    }
}

/// 座舱车模上可直接点击交互的部件（座椅、方向盘、后视镜）
public enum CabinInteractiveTarget: Equatable, Hashable, Sendable {
    case seat(SeatRole)
    case steeringWheel
    case mirrors

    public var displayName: String {
        switch self {
        case .seat(let role): return role.displayName
        case .steeringWheel: return "方向盘"
        case .mirrors: return "外后视镜"
        }
    }
}

/// 车型资产档案与能力定义
public struct CarModelProfile: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let bodyStyle: CarBodyStyle
    public let supportedLayouts: [SeatLayout]
    public let defaultLayout: SeatLayout
    public let powerFoldMirrors: Bool

    public init(
        id: String,
        displayName: String,
        bodyStyle: CarBodyStyle,
        supportedLayouts: [SeatLayout],
        powerFoldMirrors: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.bodyStyle = bodyStyle
        self.supportedLayouts = supportedLayouts
        self.defaultLayout = supportedLayouts.first ?? .five
        self.powerFoldMirrors = powerFoldMirrors
    }

    /// 根据座椅布局返回内部资源文件名后缀（`_7` / `_5` / `""`）
    public func assetSuffix(for layout: SeatLayout) -> String {
        if id == "d19" && layout == .seven { return "_7" }
        if id == "c16" && layout == .five { return "_5" }
        return ""
    }

    public func resolveLayout(_ hint: String?) -> SeatLayout {
        guard let hint, !hint.isEmpty else { return defaultLayout }
        if let found = supportedLayouts.first(where: { $0.rawValue == hint || String($0.totalSeats) == hint }) {
            return found
        }
        return defaultLayout
    }
}

/// 全量内置 12 款零跑车型清单与匹配器（精确复刻 `AbstractC2289tf` 与 `WX`）
public enum CarModelCatalog {
    public static let allModels: [CarModelProfile] = [
        CarModelProfile(id: "a05", displayName: "A05", bodyStyle: .hatchback, supportedLayouts: [.five]),
        CarModelProfile(id: "a10", displayName: "A10", bodyStyle: .suv, supportedLayouts: [.five]),
        CarModelProfile(id: "b01", displayName: "B01", bodyStyle: .sedan, supportedLayouts: [.five]),
        CarModelProfile(id: "b10", displayName: "B10", bodyStyle: .suv, supportedLayouts: [.five]),
        CarModelProfile(id: "lafa5", displayName: "Lafa5", bodyStyle: .hatchback, supportedLayouts: [.five]),
        CarModelProfile(id: "c10", displayName: "C10", bodyStyle: .suv, supportedLayouts: [.five]),
        CarModelProfile(id: "c11", displayName: "C11", bodyStyle: .suv, supportedLayouts: [.five]),
        CarModelProfile(id: "c16", displayName: "C16", bodyStyle: .suv, supportedLayouts: [.six, .five]),
        CarModelProfile(id: "d19", displayName: "D19", bodyStyle: .suv, supportedLayouts: [.six, .seven]),
        CarModelProfile(id: "d99", displayName: "D99", bodyStyle: .mpv, supportedLayouts: [.mpvSeven]),
        CarModelProfile(id: "t03", displayName: "T03", bodyStyle: .micro, supportedLayouts: [.four], powerFoldMirrors: false),
        CarModelProfile(id: "c01", displayName: "C01", bodyStyle: .sedan, supportedLayouts: [.five])
    ]

    /// 按旗舰至主流顺序排列的全系 12 款车型（用于统一车型展厅网格展示）
    public static var showcaseModels: [CarModelProfile] {
        let order = ["c16", "d19", "d99", "c11", "c10", "c01", "b10", "b01", "lafa5", "a10", "a05", "t03"]
        let ordered = order.compactMap { id in allModels.first { $0.id == id } }
        let remaining = allModels.filter { !order.contains($0.id) }
        return ordered + remaining
    }

    private static let matchOrder = ["C01", "B01", "T03", "C11", "C16", "D99", "D19", "B05", "A05", "B10", "C10", "A10", "Lafa5"]

    /// 从车辆类型/车型名称字符串提取唯一规范车型名称（`B05` 自动归并至 `Lafa5`）
    public static func detectCarType(from text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var matched: [String] = []
        for candidate in matchOrder {
            let escaped = NSRegularExpression.escapedPattern(for: candidate)
            let pattern = "(?<![A-Za-z0-9])\(escaped)(?![0-9])"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                matched.append(candidate)
            }
        }
        let normalized = Set(matched.map { $0 == "B05" ? "Lafa5" : $0 })
        guard normalized.count == 1, let first = matched.first else { return nil }
        return first == "B05" ? "Lafa5" : first
    }

    public static func profile(for carTypeOrId: String?) -> CarModelProfile {
        if let raw = carTypeOrId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let exact = allModels.first(where: { $0.id == raw }) {
            return exact
        }
        let detected = detectCarType(from: carTypeOrId) ?? "C16"
        return allModels.first(where: { $0.displayName == detected })
            ?? allModels.first(where: { $0.id == "c16" })!
    }
}

/// 车漆色彩定义（ARGB 无符号 32 位整型）
public struct PaintColor: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let argb: UInt32

    public init(id: String, displayName: String, argb: UInt32) {
        self.id = id
        self.displayName = displayName
        self.argb = argb
    }

    public var red: Double { Double((argb >> 16) & 0xFF) / 255.0 }
    public var green: Double { Double((argb >> 8) & 0xFF) / 255.0 }
    public var blue: Double { Double(argb & 0xFF) / 255.0 }
    public var hexString: String {
        String(format: "#%06X", argb & 0x00FF_FFFF)
    }
}

/// 全部官方车型车漆色库（精确还原自反编译 `AbstractC2532wd0`）
public enum PaintCatalog {
    public static let defaultPaint = PaintColor(id: "default", displayName: "默认", argb: 0xFFCBD5E1)
    public static let photoelectricWhite = PaintColor(id: "photoelectric_white", displayName: "光电白", argb: 0xFFF5F5F0)
    public static let metalBlack = PaintColor(id: "metal_black", displayName: "金属黑", argb: 0xFF25282D)
    public static let seaweedGreen = PaintColor(id: "seaweed_green", displayName: "海苔绿", argb: 0xFF556A5A)
    public static let berryBlue = PaintColor(id: "berry_blue", displayName: "莓莓蓝", argb: 0xFF365B91)
    public static let morganPink = PaintColor(id: "morgan_pink", displayName: "摩根粉", argb: 0xFFC596A3)
    public static let tundraGray = PaintColor(id: "tundra_gray", displayName: "苔原灰", argb: 0xFF777B7C)
    public static let acornBrown = PaintColor(id: "acorn_brown", displayName: "橡果棕", argb: 0xFF745446)
    public static let galaxySilver = PaintColor(id: "galaxy_silver", displayName: "星河银", argb: 0xFFB9BEC1)
    public static let starryNightBlue = PaintColor(id: "starry_night_blue", displayName: "星夜蓝", argb: 0xFF1F3150)
    public static let liquidSilver = PaintColor(id: "liquid_silver", displayName: "液态银", argb: 0xFFC7CBD0)
    public static let cloudyPurple = PaintColor(id: "cloudy_purple", displayName: "云黛紫", argb: 0xFF776B8E)
    public static let windWheatGreen = PaintColor(id: "wind_wheat_green", displayName: "风禾青", argb: 0xFF6B8E83)
    public static let dawnPurple = PaintColor(id: "dawn_purple", displayName: "曦露紫", argb: 0xFF846B8D)
    public static let tianmuGray = PaintColor(id: "tianmu_gray", displayName: "天幕灰", argb: 0xFF626970)
    public static let cloudGold = PaintColor(id: "cloud_gold", displayName: "云栖金", argb: 0xFFB79B72)

    public static let modelPaints: [String: [PaintColor]] = [
        "A05": [metalBlack],
        "A10": [seaweedGreen, berryBlue, morganPink, tundraGray, acornBrown, galaxySilver],
        "B01": [photoelectricWhite, metalBlack, morganPink, tundraGray, galaxySilver, starryNightBlue, liquidSilver, cloudyPurple],
        "B10": [windWheatGreen, photoelectricWhite, metalBlack, morganPink, tundraGray, dawnPurple, galaxySilver, liquidSilver],
        "C01": [defaultPaint],
        "C10": [photoelectricWhite, metalBlack, tundraGray, tianmuGray, dawnPurple, cloudGold],
        "C11": [
            photoelectricWhite,
            metalBlack,
            PaintColor(id: "pine_mist_gray", displayName: "松岚灰", argb: 0xFFCFD9DF),
            galaxySilver,
            tianmuGray,
            cloudGold,
            PaintColor(id: "rime_beige", displayName: "雾凇米", argb: 0xFFD3C6B2)
        ],
        "C16": [
            photoelectricWhite,
            metalBlack,
            galaxySilver,
            tianmuGray,
            cloudGold,
            PaintColor(id: "starlight_purple", displayName: "星煜紫", argb: 0xFF765D8B)
        ],
        "D19": [
            photoelectricWhite,
            metalBlack,
            PaintColor(id: "metal_black_add_crown", displayName: "金属黑+银辉之冠", argb: 0xFF313338),
            liquidSilver,
            PaintColor(id: "pine_valley_green", displayName: "松谷绿", argb: 0xFF3E6655),
            PaintColor(id: "pine_valley_green_add_crown", displayName: "松谷绿+银辉之冠", argb: 0xFF4C725E),
            tianmuGray,
            PaintColor(id: "tianmu_gray_add_crown", displayName: "天幕灰+银辉之冠", argb: 0xFF70777E)
        ],
        "D99": [
            photoelectricWhite,
            metalBlack,
            PaintColor(id: "mirror_blue", displayName: "辰镜蓝", argb: 0xFF476B96),
            liquidSilver,
            tianmuGray
        ],
        "Lafa5": [
            PaintColor(id: "electric_yellow", displayName: "电掣黄", argb: 0xFFF0C438),
            PaintColor(id: "speed_orange", displayName: "风驰橙", argb: 0xFFE87B32),
            metalBlack,
            morganPink,
            galaxySilver,
            starryNightBlue,
            liquidSilver
        ],
        "T03": [
            PaintColor(id: "celadon_green", displayName: "豆青", argb: 0xFF9DB6A3),
            PaintColor(id: "macho_pink", displayName: "猛男粉", argb: 0xFFE5A3B2),
            PaintColor(id: "light_water_blue", displayName: "浅水蓝", argb: 0xFF8FC9D8),
            PaintColor(id: "ruyao_white", displayName: "汝窑白", argb: 0xFFE9E6DE),
            PaintColor(id: "deep_space_blue", displayName: "深空蓝", argb: 0xFF263A5B),
            PaintColor(id: "deep_gray", displayName: "深遂灰", argb: 0xFF4C535A),
            tianmuGray,
            PaintColor(id: "snowfield_white", displayName: "雪域白", argb: 0xFFF7F8F5)
        ]
    ]

    public static let byId: [String: PaintColor] = {
        var map: [String: PaintColor] = [defaultPaint.id: defaultPaint]
        for list in modelPaints.values {
            for item in list {
                map[item.id] = item
            }
        }
        return map
    }()

    /// 获取某款车型可选车漆列表（自动隐藏内部 `"default"` 占位项）
    public static func availablePaints(for carTypeOrId: String?) -> [PaintColor] {
        let profile = CarModelCatalog.profile(for: carTypeOrId)
        let list = modelPaints[profile.displayName] ?? modelPaints["C16"] ?? [liquidSilver]
        let filtered = list.filter { $0.id != "default" }
        return filtered.isEmpty ? [liquidSilver] : filtered
    }

    public static func resolvePaint(id: String?, carTypeOrId: String?) -> PaintColor {
        if let cleaned = id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleaned.isEmpty,
           let matched = byId[cleaned] {
            return matched
        }
        return availablePaints(for: carTypeOrId).first ?? liquidSilver
    }
}

/// 用户名下绑定车辆模型
public struct Vehicle: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { vin }
    public var vin: String
    public var carType: String
    public var hvacCapability: HvacCapability
    public var vehicleName: String
    public var year: String
    public var outColor: String
    public var powertrain: PowertrainType
    public var isShared: Bool
    public var rightList: [String]
    public var abilities: [String]

    public init(
        vin: String,
        carType: String,
        hvacCapability: HvacCapability = .default,
        vehicleName: String,
        year: String = "",
        outColor: String = "liquid_silver",
        powertrain: PowertrainType = .bev,
        isShared: Bool = false,
        rightList: [String] = [],
        abilities: [String] = []
    ) {
        self.vin = vin
        self.carType = carType
        self.hvacCapability = hvacCapability
        self.vehicleName = vehicleName
        self.year = year
        self.outColor = outColor
        self.powertrain = powertrain
        self.isShared = isShared
        self.rightList = rightList
        self.abilities = abilities
    }

    public var modelProfile: CarModelProfile {
        CarModelCatalog.profile(for: carType)
    }

    /// 是否支持增程油箱显示
    public var isRangeExtender: Bool {
        powertrain == .reev
    }
}
