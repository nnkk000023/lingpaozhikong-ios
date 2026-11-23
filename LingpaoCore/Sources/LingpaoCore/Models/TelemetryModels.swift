import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// 车况数字信号 ID 全量语义字典（精确对应反编译 `H30.a`）
public enum SignalDictionary {
    public static let idToSemanticKey: [String: String] = [
        // 电量与充电
        "47": "acInputSlowCharge",
        "1204": "soc",
        "100003": "preciseSoc",
        "3235": "fuelSoc",
        "1200": "chargeRemainTime",
        "1178": "batteryCurrent",
        "1177": "batteryVoltage",
        "1197": "dcInputFastCharge",
        "1149": "chargeState",
        "1181": "maxBatteryTemp",
        "1182": "minBatteryTemp",
        "1183": "avgBatteryTemp",
        "1186": "batteryThermalRequest",
        "3736": "chargeCompleted",
        "48": "healthyChargeEnabled",
        "3737": "chargeScheduleCancelledOnce",
        // 续航与行驶
        "3260": "expectedMileage",
        "2188": "liveRemainingRange",
        "3257": "electricRangeStandard",
        "3262": "rangeMode",
        "3256": "fuelRangeStandard",
        "3258": "combinedRangeStandard",
        "3259": "fuelRangeDynamic",
        "3261": "combinedRangeDynamic",
        "1319": "speed",
        "1318": "totalMileage",
        "1010": "gearStatus",
        "1944": "vehicleState",
        "1480": "parkingBrakeState",
        "6048": "speedLimit",
        "6047": "speedLimitUnit",
        "12054": "speedLimitActive",
        "3725": "latitude",
        "3724": "longitude",
        // 空调与玻璃除霜
        "1938": "acSwitch",
        "2183": "acSetting",
        "2184": "acSettingRight",
        "1349": "interiorTemp",
        "1943": "recirculationMode",
        "1945": "windshieldDefrost",
        "1946": "rearWindowHeating",
        "3713": "climateMode",
        "2669": "rapidCooling",
        "2681": "rapidHeating",
        "1939": "acOperateMode",
        "1941": "acAirVolume",
        "49": "leftMirrorHeating",
        "50": "rightMirrorHeating",
        // 车门、车窗、天窗与锁
        "1693": "driverWindowStatus",
        "1694": "rightFrontWindowStatus",
        "1695": "leftRearWindowStatus",
        "1696": "rightRearWindowStatus",
        "644": "leftFrontWindowOpening",
        "645": "leftRearWindowOpening",
        "865": "rightFrontWindowOpening",
        "866": "rightRearWindowOpening",
        "1298": "driverDoorLockStatus",
        "1277": "lbcmDriverDoorStatus",
        "1278": "rbcmDriverDoorStatus",
        "1279": "lbcmLeftRearDoorStatus",
        "1280": "rbcmRightRearDoorStatus",
        "1281": "bbcmBackDoorStatus",
        "1282": "hoodStatus",
        "1276": "fbcmHoodStatus",
        "1718": "sunroofOpening",
        "1724": "roofOpening",
        "1255": "vehicleSecurityActive",
        "3636": "sentryMode",
        "1256": "bcmKeyPositionOn1",
        "1257": "bcmKeyPositionOn2",
        "1258": "bcmKeyPositionOn3",
        // 胎压
        "2646": "leftFrontTirePressure",
        "2653": "rightFrontTirePressure",
        "2660": "leftRearTirePressure",
        "2667": "rightRearTirePressure",
        "2641": "leftFrontTirePressureState",
        "2648": "rightFrontTirePressureState",
        "2655": "leftRearTirePressureState",
        "2662": "rightRearTirePressureState",
        // 座椅与方向盘
        "2100": "driverSeatHeating",
        "2101": "driverSeatVentilation",
        "2118": "passengerSeatHeating",
        "2119": "passengerSeatVentilation",
        "1879": "leftRearSeatHeating",
        "3727": "leftRearSeatVentilation",
        "1880": "rightRearSeatHeating",
        "3728": "rightRearSeatVentilation",
        "1816": "steeringWheelHeating",
        "1624": "steeringWheelHeaterMinutes",
        // 车载冰箱
        "10707": "fridgeTargetTemp",
        "10708": "fridgeMode",
        "10709": "fridgeSwitch",
        "10711": "fridgeStyle",
        "10712": "fridgeFault",
        "11189": "fridgeParkDurationHours",
        "11190": "fridgeParkSwitch",
        "11191": "fridgeParkCycles",
        "11260": "fridgeParkEndTime"
    ]

    /// 将原始数字键 signalMap 转换为语义字段字典（未映射到的纯数字键按原键保留，忽略 `"2"` / `"3"`）
    public static func mapRawSignals(_ rawSignals: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in rawSignals {
            if let semantic = idToSemanticKey[key] {
                if result[semantic] == nil {
                    result[semantic] = value
                }
            } else if key != "2", key != "3", !key.isEmpty, key.allSatisfy(\.isNumber) {
                result[key] = value
            }
        }
        return result
    }
}

/// 空调当前运行模式（驱动座舱冷/暖流体动效与空调卡片状态主题）
public enum ClimateActiveMode: String, Codable, Equatable, Sendable {
    case off
    case cool
    case quickCool
    case heat
    case quickHeat
    case deodorize
    case defrost
}

/// 强类型全车实时状态模型
public struct VehicleTelemetry: Codable, Equatable, Sendable {
    // 电量与充电
    public var soc: Double
    public var preciseSoc: Double?
    public var fuelSoc: Double?
    public var chargeState: Int
    public var chargeRemainTimeMinutes: Int
    public var batteryCurrent: Double
    public var batteryVoltage: Double
    public var dcInputFastCharge: Bool
    public var acInputSlowCharge: Bool
    public var minBatteryTemp: Double?
    public var maxBatteryTemp: Double?
    public var avgBatteryTemp: Double?
    public var healthyChargeEnabled: Bool
    public var healthyChargeTargetSoc: Int
    public var chargeScheduleEnabled: Bool
    public var chargeScheduleStart: String
    public var chargeScheduleEnd: String
    public var chargeScheduleCycles: String
    public var chargeScheduleCirculation: Int
    public var chargeScheduleRecharge: Bool

    // 续航与行驶
    public var electricRangeKm: Double
    public var fuelRangeKm: Double
    public var combinedRangeKm: Double
    public var totalMileageKm: Double
    public var speedKmh: Double
    public var latitude: Double?
    public var longitude: Double?

    // 门锁与车身开关
    public var isLocked: Bool
    public var driverDoorOpen: Bool
    public var passengerDoorOpen: Bool
    public var leftRearDoorOpen: Bool
    public var rightRearDoorOpen: Bool
    public var trunkOpen: Bool
    public var hoodOpen: Bool
    public var mirrorsFolded: Bool
    public var leftFrontWindowOpening: Int
    public var rightFrontWindowOpening: Int
    public var leftRearWindowOpening: Int
    public var rightRearWindowOpening: Int
    public var sunroofOpening: Int
    public var sentryModeOn: Bool

    // 空调与座舱热舒适
    public var acOn: Bool
    public var activeClimateMode: ClimateActiveMode = .off
    public var acTargetTemp: Double
    public var interiorTemp: Double?
    public var acWindLevel: Int
    public var recirculationIn: Bool
    public var windshieldDefrostOn: Bool
    public var rearMirrorHeatingOn: Bool
    public var steeringWheelHeatingLevel: Int
    public var driverSeatHeating: Int
    public var driverSeatVentilation: Int
    public var passengerSeatHeating: Int
    public var passengerSeatVentilation: Int
    public var leftRearSeatHeating: Int
    public var leftRearSeatVentilation: Int
    public var rightRearSeatHeating: Int
    public var rightRearSeatVentilation: Int

    // 四轮胎压（kPa 与告警状态）
    public var leftFrontTirePressure: Double?
    public var rightFrontTirePressure: Double?
    public var leftRearTirePressure: Double?
    public var rightRearTirePressure: Double?
    public var leftFrontTireAlert: Bool
    public var rightFrontTireAlert: Bool
    public var leftRearTireAlert: Bool
    public var rightRearTireAlert: Bool

    // 车载冰箱
    public var fridgeOn: Bool
    public var fridgeTargetTemp: Int
    public var fridgeMode: String

    // 时间戳与原始信号字典（转字符串方便调试查看）
    public var updatedAtMs: Int64
    public var rawMappedStrings: [String: String]

    public init(
        soc: Double = 0,
        preciseSoc: Double? = nil,
        fuelSoc: Double? = nil,
        chargeState: Int = 0,
        chargeRemainTimeMinutes: Int = 0,
        batteryCurrent: Double = 0,
        batteryVoltage: Double = 0,
        dcInputFastCharge: Bool = false,
        acInputSlowCharge: Bool = false,
        minBatteryTemp: Double? = nil,
        maxBatteryTemp: Double? = nil,
        avgBatteryTemp: Double? = nil,
        healthyChargeEnabled: Bool = false,
        healthyChargeTargetSoc: Int = 90,
        chargeScheduleEnabled: Bool = false,
        chargeScheduleStart: String = "22:00",
        chargeScheduleEnd: String = "06:00",
        chargeScheduleCycles: String = "1,2,3,4,5,6,7",
        chargeScheduleCirculation: Int = 1,
        chargeScheduleRecharge: Bool = false,
        electricRangeKm: Double = 0,
        fuelRangeKm: Double = 0,
        combinedRangeKm: Double = 0,
        totalMileageKm: Double = 0,
        speedKmh: Double = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isLocked: Bool = true,
        driverDoorOpen: Bool = false,
        passengerDoorOpen: Bool = false,
        leftRearDoorOpen: Bool = false,
        rightRearDoorOpen: Bool = false,
        trunkOpen: Bool = false,
        hoodOpen: Bool = false,
        mirrorsFolded: Bool = true,
        leftFrontWindowOpening: Int = 0,
        rightFrontWindowOpening: Int = 0,
        leftRearWindowOpening: Int = 0,
        rightRearWindowOpening: Int = 0,
        sunroofOpening: Int = 0,
        sentryModeOn: Bool = false,
        acOn: Bool = false,
        activeClimateMode: ClimateActiveMode? = nil,
        acTargetTemp: Double = 24,
        interiorTemp: Double? = nil,
        acWindLevel: Int = 2,
        recirculationIn: Bool = true,
        windshieldDefrostOn: Bool = false,
        rearMirrorHeatingOn: Bool = false,
        steeringWheelHeatingLevel: Int = 0,
        driverSeatHeating: Int = 0,
        driverSeatVentilation: Int = 0,
        passengerSeatHeating: Int = 0,
        passengerSeatVentilation: Int = 0,
        leftRearSeatHeating: Int = 0,
        leftRearSeatVentilation: Int = 0,
        rightRearSeatHeating: Int = 0,
        rightRearSeatVentilation: Int = 0,
        leftFrontTirePressure: Double? = nil,
        rightFrontTirePressure: Double? = nil,
        leftRearTirePressure: Double? = nil,
        rightRearTirePressure: Double? = nil,
        leftFrontTireAlert: Bool = false,
        rightFrontTireAlert: Bool = false,
        leftRearTireAlert: Bool = false,
        rightRearTireAlert: Bool = false,
        fridgeOn: Bool = false,
        fridgeTargetTemp: Int = 4,
        fridgeMode: String = "cold",
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        rawMappedStrings: [String: String] = [:]
    ) {
        self.soc = soc
        self.preciseSoc = preciseSoc
        self.fuelSoc = fuelSoc
        self.chargeState = chargeState
        self.chargeRemainTimeMinutes = chargeRemainTimeMinutes
        self.batteryCurrent = batteryCurrent
        self.batteryVoltage = batteryVoltage
        self.dcInputFastCharge = dcInputFastCharge
        self.acInputSlowCharge = acInputSlowCharge
        self.minBatteryTemp = minBatteryTemp
        self.maxBatteryTemp = maxBatteryTemp
        self.avgBatteryTemp = avgBatteryTemp
        self.healthyChargeEnabled = healthyChargeEnabled
        self.healthyChargeTargetSoc = healthyChargeTargetSoc
        self.chargeScheduleEnabled = chargeScheduleEnabled
        self.chargeScheduleStart = chargeScheduleStart
        self.chargeScheduleEnd = chargeScheduleEnd
        self.chargeScheduleCycles = chargeScheduleCycles
        self.chargeScheduleCirculation = chargeScheduleCirculation
        self.chargeScheduleRecharge = chargeScheduleRecharge
        self.electricRangeKm = electricRangeKm
        self.fuelRangeKm = fuelRangeKm
        self.combinedRangeKm = combinedRangeKm
        self.totalMileageKm = totalMileageKm
        self.speedKmh = speedKmh
        self.latitude = latitude
        self.longitude = longitude
        self.isLocked = isLocked
        self.driverDoorOpen = driverDoorOpen
        self.passengerDoorOpen = passengerDoorOpen
        self.leftRearDoorOpen = leftRearDoorOpen
        self.rightRearDoorOpen = rightRearDoorOpen
        self.trunkOpen = trunkOpen
        self.hoodOpen = hoodOpen
        self.mirrorsFolded = mirrorsFolded
        self.leftFrontWindowOpening = leftFrontWindowOpening
        self.rightFrontWindowOpening = rightFrontWindowOpening
        self.leftRearWindowOpening = leftRearWindowOpening
        self.rightRearWindowOpening = rightRearWindowOpening
        self.sunroofOpening = sunroofOpening
        self.sentryModeOn = sentryModeOn
        self.acOn = acOn
        self.activeClimateMode = activeClimateMode ?? (acOn ? (acTargetTemp >= 26 ? .heat : .cool) : .off)
        self.acTargetTemp = acTargetTemp
        self.interiorTemp = interiorTemp
        self.acWindLevel = acWindLevel
        self.recirculationIn = recirculationIn
        self.windshieldDefrostOn = windshieldDefrostOn
        self.rearMirrorHeatingOn = rearMirrorHeatingOn
        self.steeringWheelHeatingLevel = steeringWheelHeatingLevel
        self.driverSeatHeating = driverSeatHeating
        self.driverSeatVentilation = driverSeatVentilation
        self.passengerSeatHeating = passengerSeatHeating
        self.passengerSeatVentilation = passengerSeatVentilation
        self.leftRearSeatHeating = leftRearSeatHeating
        self.leftRearSeatVentilation = leftRearSeatVentilation
        self.rightRearSeatHeating = rightRearSeatHeating
        self.rightRearSeatVentilation = rightRearSeatVentilation
        self.leftFrontTirePressure = leftFrontTirePressure
        self.rightFrontTirePressure = rightFrontTirePressure
        self.leftRearTirePressure = leftRearTirePressure
        self.rightRearTirePressure = rightRearTirePressure
        self.leftFrontTireAlert = leftFrontTireAlert
        self.rightFrontTireAlert = rightFrontTireAlert
        self.leftRearTireAlert = leftRearTireAlert
        self.rightRearTireAlert = rightRearTireAlert
        self.fridgeOn = fridgeOn
        self.fridgeTargetTemp = fridgeTargetTemp
        self.fridgeMode = fridgeMode
        self.updatedAtMs = updatedAtMs
        self.rawMappedStrings = rawMappedStrings
    }

    /// 实际显示百分比电量（优先高精度 `preciseSoc`）
    public var displaySoc: Double {
        let val = preciseSoc ?? soc
        return min(max(val, 0), 100)
    }

    /// 当前电池实时温度（优先取车端平均电池温度，其次取最高/最低温度均值，再次回落最低温度信号）
    public var currentBatteryTemp: Double? {
        if let avgBatteryTemp {
            return avgBatteryTemp
        }
        if let minBatteryTemp, let maxBatteryTemp {
            return (minBatteryTemp + maxBatteryTemp) / 2.0
        }
        return minBatteryTemp ?? maxBatteryTemp
    }

    /// 估算充放电功率（kW）
    public var chargePowerKw: Double {
        abs(batteryVoltage * batteryCurrent) / 1000.0
    }

    /// 是否处于充电连接/充电进行中状态
    public var isCharging: Bool {
        chargeState == 1 || chargeState == 2 || dcInputFastCharge || acInputSlowCharge
    }

    /// 任一车门/前备箱/后备箱未关闭
    public var hasOpenClosure: Bool {
        driverDoorOpen || passengerDoorOpen || leftRearDoorOpen || rightRearDoorOpen || trunkOpen || hoodOpen
    }

    /// 任一车窗未完全关闭
    public var hasOpenWindow: Bool {
        leftFrontWindowOpening > 0 || rightFrontWindowOpening > 0 || leftRearWindowOpening > 0 || rightRearWindowOpening > 0
    }

    /// 指定座椅的加热档位（0..3）
    public func heatingLevel(for role: SeatRole) -> Int {
        switch role {
        case .driver: return driverSeatHeating
        case .passenger: return passengerSeatHeating
        case .rearLeft: return leftRearSeatHeating
        case .rearRight: return rightRearSeatHeating
        default: return 0
        }
    }

    /// 指定座椅的通风档位（0..3）
    public func ventilationLevel(for role: SeatRole) -> Int {
        switch role {
        case .driver: return driverSeatVentilation
        case .passenger: return passengerSeatVentilation
        case .rearLeft: return leftRearSeatVentilation
        case .rearRight: return rightRearSeatVentilation
        default: return 0
        }
    }

    /// 从网关 `/signal/info/query` 返回的原始 `signalMap` 与 `config["3"]` 构造车况模型
    public static func decode(signalMap raw: [String: Any], chargeConfig: [String: Any]? = nil, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> VehicleTelemetry {
        let mapped = SignalDictionary.mapRawSignals(raw)

        func doubleVal(_ key: String) -> Double? {
            guard let v = mapped[key] else { return nil }
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let n = v as? NSNumber { return n.doubleValue }
            return nil
        }

        func intVal(_ key: String) -> Int? {
            if let d = doubleVal(key) { return Int(d.rounded()) }
            return nil
        }

        func boolVal(_ key: String) -> Bool? {
            guard let v = mapped[key] else { return nil }
            if let b = v as? Bool { return b }
            if let i = intVal(key) { return i != 0 }
            if let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                return s == "true" || s == "1" || s == "on"
            }
            return nil
        }

        var strDict: [String: String] = [:]
        for (k, v) in mapped {
            strDict[k] = String(describing: v)
        }

        let lockSignal = intVal("driverDoorLockStatus") ?? 1
        let locked = lockSignal == 1 || lockSignal == 2

        let acSwitch = boolVal("acSwitch") ?? false
        let acTemp = doubleVal("acSetting") ?? 24.0

        let elecRange = doubleVal("liveRemainingRange") ?? doubleVal("electricRangeStandard") ?? doubleVal("expectedMileage") ?? 0
        let fuelRange = doubleVal("fuelRangeDynamic") ?? doubleVal("fuelRangeStandard") ?? 0
        let combined = doubleVal("combinedRangeDynamic") ?? doubleVal("combinedRangeStandard") ?? (elecRange + fuelRange)

        let schedEnabled = (chargeConfig?["isEnable"] as? NSNumber)?.intValue == 1 || (chargeConfig?["isEnable"] as? String) == "1"
        let schedStart = (chargeConfig?["beginTime"] as? String) ?? "22:00"
        let schedEnd = (chargeConfig?["endTime"] as? String) ?? "06:00"
        let schedCycles = (chargeConfig?["cycles"] as? String) ?? "1,2,3,4,5,6,7"
        let schedCirc = (chargeConfig?["circulation"] as? NSNumber)?.intValue ?? 1
        let schedRech = (chargeConfig?["recharge"] as? NSNumber)?.intValue == 1
        let schedSoc = (chargeConfig?["percent"] as? NSNumber)?.intValue ?? 90

        let defrostOn = (intVal("windshieldDefrost") ?? 0) != 0
        let rapidCoolOn = (intVal("rapidCooling") ?? 0) != 0
        let rapidHeatOn = (intVal("rapidHeating") ?? 0) != 0
        let derivedClimateMode: ClimateActiveMode = {
            if !acSwitch { return .off }
            if rapidCoolOn { return .quickCool }
            if rapidHeatOn { return .quickHeat }
            if defrostOn { return .defrost }
            return acTemp >= 26 ? .heat : .cool
        }()

        return VehicleTelemetry(
            soc: doubleVal("soc") ?? 0,
            preciseSoc: doubleVal("preciseSoc"),
            fuelSoc: doubleVal("fuelSoc"),
            chargeState: intVal("chargeState") ?? 0,
            chargeRemainTimeMinutes: intVal("chargeRemainTime") ?? 0,
            batteryCurrent: doubleVal("batteryCurrent") ?? 0,
            batteryVoltage: doubleVal("batteryVoltage") ?? 0,
            dcInputFastCharge: boolVal("dcInputFastCharge") ?? false,
            acInputSlowCharge: boolVal("acInputSlowCharge") ?? false,
            minBatteryTemp: doubleVal("minBatteryTemp"),
            maxBatteryTemp: doubleVal("maxBatteryTemp"),
            avgBatteryTemp: doubleVal("avgBatteryTemp"),
            healthyChargeEnabled: boolVal("healthyChargeEnabled") ?? false,
            healthyChargeTargetSoc: min(max(schedSoc, 50), 100),
            chargeScheduleEnabled: schedEnabled,
            chargeScheduleStart: schedStart,
            chargeScheduleEnd: schedEnd,
            chargeScheduleCycles: schedCycles,
            chargeScheduleCirculation: schedCirc,
            chargeScheduleRecharge: schedRech,
            electricRangeKm: elecRange,
            fuelRangeKm: fuelRange,
            combinedRangeKm: combined,
            totalMileageKm: doubleVal("totalMileage") ?? 0,
            speedKmh: doubleVal("speed") ?? 0,
            latitude: doubleVal("latitude"),
            longitude: doubleVal("longitude"),
            isLocked: locked,
            driverDoorOpen: (intVal("lbcmDriverDoorStatus") ?? 0) != 0,
            passengerDoorOpen: (intVal("rbcmDriverDoorStatus") ?? 0) != 0,
            leftRearDoorOpen: (intVal("lbcmLeftRearDoorStatus") ?? 0) != 0,
            rightRearDoorOpen: (intVal("rbcmRightRearDoorStatus") ?? 0) != 0,
            trunkOpen: (intVal("bbcmBackDoorStatus") ?? 0) != 0,
            hoodOpen: (intVal("fbcmHoodStatus") ?? intVal("hoodStatus") ?? 0) != 0,
            mirrorsFolded: locked,
            leftFrontWindowOpening: intVal("leftFrontWindowOpening") ?? 0,
            rightFrontWindowOpening: intVal("rightFrontWindowOpening") ?? 0,
            leftRearWindowOpening: intVal("leftRearWindowOpening") ?? 0,
            rightRearWindowOpening: intVal("rightRearWindowOpening") ?? 0,
            sunroofOpening: intVal("sunroofOpening") ?? 0,
            sentryModeOn: (intVal("sentryMode") ?? 0) != 0,
            acOn: acSwitch,
            activeClimateMode: derivedClimateMode,
            acTargetTemp: acTemp,
            interiorTemp: doubleVal("interiorTemp"),
            acWindLevel: intVal("acAirVolume") ?? 2,
            recirculationIn: (intVal("recirculationMode") ?? 0) == 0,
            windshieldDefrostOn: (intVal("windshieldDefrost") ?? 0) != 0,
            rearMirrorHeatingOn: ((intVal("leftMirrorHeating") ?? 0) != 0) || ((intVal("rightMirrorHeating") ?? 0) != 0),
            steeringWheelHeatingLevel: intVal("steeringWheelHeating") ?? 0,
            driverSeatHeating: intVal("driverSeatHeating") ?? 0,
            driverSeatVentilation: intVal("driverSeatVentilation") ?? 0,
            passengerSeatHeating: intVal("passengerSeatHeating") ?? 0,
            passengerSeatVentilation: intVal("passengerSeatVentilation") ?? 0,
            leftRearSeatHeating: intVal("leftRearSeatHeating") ?? 0,
            leftRearSeatVentilation: intVal("leftRearSeatVentilation") ?? 0,
            rightRearSeatHeating: intVal("rightRearSeatHeating") ?? 0,
            rightRearSeatVentilation: intVal("rightRearSeatVentilation") ?? 0,
            leftFrontTirePressure: doubleVal("leftFrontTirePressure"),
            rightFrontTirePressure: doubleVal("rightFrontTirePressure"),
            leftRearTirePressure: doubleVal("leftRearTirePressure"),
            rightRearTirePressure: doubleVal("rightRearTirePressure"),
            leftFrontTireAlert: (intVal("leftFrontTirePressureState") ?? 0) != 0,
            rightFrontTireAlert: (intVal("rightFrontTirePressureState") ?? 0) != 0,
            leftRearTireAlert: (intVal("leftRearTirePressureState") ?? 0) != 0,
            rightRearTireAlert: (intVal("rightRearTirePressureState") ?? 0) != 0,
            fridgeOn: (intVal("fridgeSwitch") ?? 0) != 0,
            fridgeTargetTemp: intVal("fridgeTargetTemp") ?? 4,
            fridgeMode: (intVal("fridgeMode") ?? 0) == 1 ? "hot" : "cold",
            updatedAtMs: nowMs,
            rawMappedStrings: strDict
        )
    }
}

/// 面向 App Group（桌面小组件 / 灵动岛 / Siri 捷径）的轻量共享车况快照
public struct SharedVehicleSnapshot: Codable, Equatable, Sendable {
    public var vin: String
    public var vehicleName: String
    public var carType: String
    public var paintId: String
    public var soc: Double
    public var rangeKm: Double
    public var isLocked: Bool
    public var acOn: Bool
    public var interiorTemp: Double?
    public var isCharging: Bool
    public var chargePowerKw: Double
    public var chargeRemainMinutes: Int
    public var updatedAt: Date
    public var lastActionMessage: String?

    public init(
        vin: String,
        vehicleName: String,
        carType: String,
        paintId: String,
        soc: Double,
        rangeKm: Double,
        isLocked: Bool,
        acOn: Bool,
        interiorTemp: Double?,
        isCharging: Bool,
        chargePowerKw: Double,
        chargeRemainMinutes: Int,
        updatedAt: Date = Date(),
        lastActionMessage: String? = nil
    ) {
        self.vin = vin
        self.vehicleName = vehicleName
        self.carType = carType
        self.paintId = paintId
        self.soc = soc
        self.rangeKm = rangeKm
        self.isLocked = isLocked
        self.acOn = acOn
        self.interiorTemp = interiorTemp
        self.isCharging = isCharging
        self.chargePowerKw = chargePowerKw
        self.chargeRemainMinutes = chargeRemainMinutes
        self.updatedAt = updatedAt
        self.lastActionMessage = lastActionMessage
    }
}

/// App Group 共享快照读写器（支持测试传入内存 UserDefaults）
public enum SharedSnapshotStore {
    public static let appGroupIdentifier = "group.com.lingpao.personal"
    private static let storageKey = "lingpao.shared.vehicle.snapshot.v1"

    public static func save(_ snapshot: SharedVehicleSnapshot, defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)) {
        guard let defaults else { return }
        if let encoded = try? JSONEncoder().encode(snapshot) {
            defaults.set(encoded, forKey: storageKey)
        }
    }

    public static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)) -> SharedVehicleSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(SharedVehicleSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }
}

#if canImport(ActivityKit) && os(iOS)
/// 实时充电与空调监控灵动岛属性（主 App 与 Widget Extension 共享）
public struct ChargeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var soc: Int
        public var targetSoc: Int
        public var rangeKm: Int
        public var powerKw: Double
        public var remainMinutes: Int
        public var isCharging: Bool
        public var acOn: Bool
        public var interiorTemp: Double?

        public init(
            soc: Int,
            targetSoc: Int,
            rangeKm: Int,
            powerKw: Double,
            remainMinutes: Int,
            isCharging: Bool,
            acOn: Bool,
            interiorTemp: Double?
        ) {
            self.soc = soc
            self.targetSoc = targetSoc
            self.rangeKm = rangeKm
            self.powerKw = powerKw
            self.remainMinutes = remainMinutes
            self.isCharging = isCharging
            self.acOn = acOn
            self.interiorTemp = interiorTemp
        }
    }

    public var vehicleName: String
    public var carType: String

    public init(vehicleName: String, carType: String) {
        self.vehicleName = vehicleName
        self.carType = carType
    }
}
#endif
