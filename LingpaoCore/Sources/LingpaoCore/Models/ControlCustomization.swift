import Foundation

/// 主页「快捷控制」可选功能枚举（支持用户自由增删与排序）
public enum HomeQuickAction: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case lockToggle
    case climateToggle
    case horn
    case trunkToggle
    case frunkToggle
    case windowVent
    case windowClose
    case sentryToggle
    case mirrorHeat
    case quickCool
    case quickHeat
    case deodorize

    public var id: String { rawValue }

    /// 默认主页 4 个常用快捷控制项
    public static let defaults: [HomeQuickAction] = [
        .lockToggle,
        .climateToggle,
        .horn,
        .trunkToggle
    ]

    public var displayName: String {
        switch self {
        case .lockToggle: return "解锁 / 闭锁"
        case .climateToggle: return "开 / 关空调"
        case .horn: return "鸣笛寻车"
        case .trunkToggle: return "开 / 关尾箱"
        case .frunkToggle: return "开 / 关前备箱"
        case .windowVent: return "车窗通风"
        case .windowClose: return "车窗全关"
        case .sentryToggle: return "哨兵模式"
        case .mirrorHeat: return "后视镜加热"
        case .quickCool: return "极速降温"
        case .quickHeat: return "极速升温"
        case .deodorize: return "快速除味"
        }
    }

    public var staticIcon: String {
        switch self {
        case .lockToggle: return "lock.fill"
        case .climateToggle: return "fan.fill"
        case .horn: return "horn.blast.fill"
        case .trunkToggle: return "car.top.radiowaves.rear.right.fill"
        case .frunkToggle: return "car.top.radiowaves.front.fill"
        case .windowVent: return "car.top.door.front.left.open"
        case .windowClose: return "window.ceiling.closed"
        case .sentryToggle: return "eye.circle.fill"
        case .mirrorHeat: return "heat.waves"
        case .quickCool: return "snowflake"
        case .quickHeat: return "flame.fill"
        case .deodorize: return "wind"
        }
    }
}

/// 控车页面 3 个功能大卡片分组标识（支持排序）
public enum CabinControlGroupID: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case climate
    case bodyHardware
    case comfortSchedule

    public var id: String { rawValue }

    public static let defaultOrder: [CabinControlGroupID] = [
        .climate,
        .bodyHardware,
        .comfortSchedule
    ]

    public var displayName: String {
        switch self {
        case .climate: return "空调系统"
        case .bodyHardware: return "门窗与车身控制"
        case .comfortSchedule: return "定时预约"
        }
    }

    public var subtitle: String {
        switch self {
        case .climate: return "温度调节、风量、极速冷暖与除霜"
        case .bodyHardware: return "车窗、天窗、前后备箱、方向盘加热与后视镜"
        case .comfortSchedule: return "定时空调、电池预热、预约充电与冰箱"
        }
    }
}

/// 控车「空调系统」组可选快捷模式
public enum ClimateQuickAction: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case quickCool
    case quickHeat
    case deodorize
    case defrost

    public var id: String { rawValue }

    public static let defaults: [ClimateQuickAction] = [
        .quickCool,
        .quickHeat,
        .deodorize,
        .defrost
    ]

    public var displayName: String {
        switch self {
        case .quickCool: return "极速降温"
        case .quickHeat: return "极速升温"
        case .deodorize: return "快速除味"
        case .defrost: return "前挡除霜"
        }
    }

    public var icon: String {
        switch self {
        case .quickCool: return "snowflake"
        case .quickHeat: return "flame.fill"
        case .deodorize: return "wind"
        case .defrost: return "windshield.front.and.heat.waves"
        }
    }
}

/// 控车「门窗与车身控制」组可选功能（统一卡片规格，支持全系增删）
public enum BodyHardwareAction: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case windowVent
    case windowClose
    case windowHalf
    case sunroofOpen
    case sunroofClose
    case sunshadeOpen
    case sunshadeClose
    case frunkToggle
    case trunkToggle
    case sentryToggle
    case mirrorHeatingToggle
    case steeringWheelHeat
    case twoRowMode
    case threeRowMode
    case slidingDoorLeftOpen
    case slidingDoorLeftClose
    case slidingDoorRightOpen
    case slidingDoorRightClose

    public var id: String { rawValue }

    /// 根据车型档案生成合理的初始默认列表（含方向盘加热；六/七座车默认含二/三排模式；非 D99 默认隐藏侧滑门）
    public static func defaultActions(for carType: String) -> [BodyHardwareAction] {
        let prof = CarModelCatalog.profile(for: carType)
        var list: [BodyHardwareAction] = [
            .windowVent,
            .windowClose,
            .windowHalf,
            .sunroofOpen,
            .sunroofClose,
            .sunshadeOpen,
            .frunkToggle,
            .sentryToggle,
            .mirrorHeatingToggle,
            .steeringWheelHeat
        ]
        if prof.defaultLayout.totalSeats >= 6 {
            list.append(contentsOf: [.twoRowMode, .threeRowMode])
        }
        if prof.id == "d99" {
            list.append(contentsOf: [
                .slidingDoorLeftOpen,
                .slidingDoorLeftClose,
                .slidingDoorRightOpen,
                .slidingDoorRightClose
            ])
        }
        return list
    }

    public var displayName: String {
        switch self {
        case .windowVent: return "车窗通风"
        case .windowClose: return "车窗全关"
        case .windowHalf: return "车窗半开"
        case .sunroofOpen: return "打开天窗"
        case .sunroofClose: return "关闭天窗"
        case .sunshadeOpen: return "遮阳帘开"
        case .sunshadeClose: return "遮阳帘关"
        case .frunkToggle: return "前备箱开关"
        case .trunkToggle: return "尾箱开关"
        case .sentryToggle: return "哨兵模式"
        case .mirrorHeatingToggle: return "后视镜加热"
        case .steeringWheelHeat: return "方向盘加热"
        case .twoRowMode: return "二排模式"
        case .threeRowMode: return "三排模式"
        case .slidingDoorLeftOpen: return "左侧滑门开"
        case .slidingDoorLeftClose: return "左侧滑门关"
        case .slidingDoorRightOpen: return "右侧滑门开"
        case .slidingDoorRightClose: return "右侧滑门关"
        }
    }

    public var staticIcon: String {
        switch self {
        case .windowVent: return "car.top.door.front.left.open"
        case .windowClose: return "window.ceiling.closed"
        case .windowHalf: return "window.casement"
        case .sunroofOpen: return "sun.max.fill"
        case .sunroofClose: return "moon.zzz.fill"
        case .sunshadeOpen: return "blinds.horizontal.open"
        case .sunshadeClose: return "blinds.horizontal.closed"
        case .frunkToggle: return "car.top.radiowaves.front.fill"
        case .trunkToggle: return "car.top.radiowaves.rear.right.fill"
        case .sentryToggle: return "eye.circle.fill"
        case .mirrorHeatingToggle: return "heat.waves"
        case .steeringWheelHeat: return "steeringwheel"
        case .twoRowMode: return "rectangle.split.2x1"
        case .threeRowMode: return "rectangle.split.3x1"
        case .slidingDoorLeftOpen: return "arrow.left.to.line"
        case .slidingDoorLeftClose: return "arrow.right.to.line"
        case .slidingDoorRightOpen: return "arrow.right.to.line"
        case .slidingDoorRightClose: return "arrow.left.to.line"
        }
    }
}

/// 控车「定时预约」组可选预约任务项
public enum ComfortScheduleAction: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case acSchedule
    case batteryPreheat
    case chargeSchedule
    case fridge

    public var id: String { rawValue }

    /// 默认定时预约清单
    public static func defaultActions(for carType: String) -> [ComfortScheduleAction] {
        [.acSchedule, .batteryPreheat, .chargeSchedule, .fridge]
    }

    public var displayName: String {
        switch self {
        case .acSchedule: return "定时空调"
        case .batteryPreheat: return "电池预热"
        case .chargeSchedule: return "预约充电"
        case .fridge: return "车载冰箱"
        }
    }

    public var icon: String {
        switch self {
        case .acSchedule: return "clock.badge.checkmark"
        case .batteryPreheat: return "thermometer.sun.fill"
        case .chargeSchedule: return "ev.charger.fill"
        case .fridge: return "refrigerator.fill"
        }
    }
}

/// 用户主页与控车自定义布局偏好（支持排序、功增删与跨重启持久化）
public struct ControlLayoutPreferences: Codable, Equatable, Sendable {
    public var homeQuickActions: [HomeQuickAction]
    public var cabinGroupOrder: [CabinControlGroupID]
    public var climateQuickActions: [ClimateQuickAction]
    public var bodyHardwareActions: [BodyHardwareAction]
    public var comfortScheduleActions: [ComfortScheduleAction]

    public init(
        homeQuickActions: [HomeQuickAction] = HomeQuickAction.defaults,
        cabinGroupOrder: [CabinControlGroupID] = CabinControlGroupID.defaultOrder,
        climateQuickActions: [ClimateQuickAction] = ClimateQuickAction.defaults,
        bodyHardwareActions: [BodyHardwareAction] = BodyHardwareAction.defaultActions(for: "C16"),
        comfortScheduleActions: [ComfortScheduleAction] = ComfortScheduleAction.defaultActions(for: "C16")
    ) {
        self.homeQuickActions = homeQuickActions
        self.cabinGroupOrder = cabinGroupOrder
        self.climateQuickActions = climateQuickActions
        self.bodyHardwareActions = bodyHardwareActions
        self.comfortScheduleActions = comfortScheduleActions
    }

    public static func `default`(for carType: String = "C16") -> ControlLayoutPreferences {
        ControlLayoutPreferences(
            homeQuickActions: HomeQuickAction.defaults,
            cabinGroupOrder: CabinControlGroupID.defaultOrder,
            climateQuickActions: ClimateQuickAction.defaults,
            bodyHardwareActions: BodyHardwareAction.defaultActions(for: carType),
            comfortScheduleActions: ComfortScheduleAction.defaultActions(for: carType)
        )
    }
}

/// 均衡网格切分器：保证增删按钮后任意卡片数量都不出现悬空孤格，视觉均衡对称
public enum BalancedGridPartitioner {
    /// 返回每一行的元素个数列表，总和等于 `count`
    public static func partition(count: Int, maxColumns: Int) -> [Int] {
        guard count > 0, maxColumns > 0 else { return [] }
        if count <= maxColumns {
            return [count]
        }
        let rows = Int(ceil(Double(count) / Double(maxColumns)))
        let base = count / rows
        let remainder = count % rows
        return (0..<rows).map { idx in
            idx < remainder ? (base + 1) : base
        }
    }
}

/// 单次充电曲线采样点
public struct ChargeCurvePoint: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: Double { elapsedMinutes }
    public let elapsedMinutes: Double
    public let powerKw: Double
    public let soc: Double

    public init(elapsedMinutes: Double, powerKw: Double, soc: Double) {
        self.elapsedMinutes = elapsedMinutes
        self.powerKw = powerKw
        self.soc = soc
    }
}

/// 单次充电结束/手动停止总结报告模型
public struct ChargeSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleName: String
    public let carType: String
    public let startTime: Date
    public let endTime: Date
    public let durationMinutes: Int
    public let startSoc: Double
    public let endSoc: Double
    public let addedRangeKm: Double
    public let peakPowerKw: Double
    public let averagePowerKw: Double
    public let addedEnergyKwh: Double
    public let isCompletedNormally: Bool
    public let curvePoints: [ChargeCurvePoint]

    public init(
        id: UUID = UUID(),
        vehicleName: String,
        carType: String,
        startTime: Date,
        endTime: Date,
        durationMinutes: Int,
        startSoc: Double,
        endSoc: Double,
        addedRangeKm: Double,
        peakPowerKw: Double,
        averagePowerKw: Double,
        addedEnergyKwh: Double,
        isCompletedNormally: Bool,
        curvePoints: [ChargeCurvePoint]
    ) {
        self.id = id
        self.vehicleName = vehicleName
        self.carType = carType
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.addedRangeKm = addedRangeKm
        self.peakPowerKw = peakPowerKw
        self.averagePowerKw = averagePowerKw
        self.addedEnergyKwh = addedEnergyKwh
        self.isCompletedNormally = isCompletedNormally
        self.curvePoints = curvePoints
    }
}
