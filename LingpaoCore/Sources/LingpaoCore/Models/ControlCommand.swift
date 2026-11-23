import Foundation

/// 空调风向与位置枚举
public enum ClimatePosition: String, Codable, Sendable {
    case all
    case windshield = "wshld"
}

/// 空调内外循环枚举
public enum ClimateRecirculation: String, Codable, Sendable {
    case internalLoop = "in"
    case externalLoop = "out"
}

/// 车载冰箱工作模式
public enum FridgeMode: String, Codable, CaseIterable, Sendable {
    case cold
    case hot
}

/// 车载冰箱功率风格
public enum FridgeStyle: String, Codable, CaseIterable, Sendable {
    case normal
    case turbo
}

/// 远程控车自定义空调指令载荷
public struct ClimateControlRequest: Equatable, Sendable {
    public var temperature: Int
    public var capability: HvacCapability
    public var windLevel: Int
    public var circle: ClimateRecirculation
    public var windshieldDefrost: Bool
    public var position: ClimatePosition
    public var customSummary: String?

    public init(
        temperature: Int,
        capability: HvacCapability = .default,
        windLevel: Int = 3,
        circle: ClimateRecirculation = .internalLoop,
        windshieldDefrost: Bool = false,
        position: ClimatePosition = .all,
        customSummary: String? = nil
    ) {
        self.temperature = temperature
        self.capability = capability
        self.windLevel = windLevel
        self.circle = circle
        self.windshieldDefrost = windshieldDefrost
        self.position = position
        self.customSummary = customSummary
    }
}

/// 车载冰箱控制参数
public struct FridgeControlRequest: Equatable, Sendable {
    public var enable: Bool
    public var mode: FridgeMode
    public var temperature: Int
    public var style: FridgeStyle
    public var parkEnable: Bool
    public var durationSeconds: Int
    public var cycles: String
    public var value: String

    public init(
        enable: Bool,
        mode: FridgeMode = .cold,
        temperature: Int = 4,
        style: FridgeStyle = .normal,
        parkEnable: Bool = false,
        durationSeconds: Int = 3600,
        cycles: String = "1",
        value: String = "false"
    ) {
        self.enable = enable
        self.mode = mode
        self.temperature = temperature
        self.style = style
        self.parkEnable = parkEnable
        self.durationSeconds = durationSeconds
        self.cycles = cycles
        self.value = value
    }
}

/// 完整 21 类远程控车指令负载对象（严格对齐 `AbstractC2139rp.i/j/k/l/m/n` 与规格书第 7 节）
public struct RemoteControlPayload: Equatable, Sendable {
    public let cmdid: String
    public let stateJSON: String
    public let summary: String

    public init(cmdid: String, stateJSON: String, summary: String) {
        self.cmdid = cmdid
        self.stateJSON = stateJSON
        self.summary = summary
    }
}

/// 类型安全远程控车指令枚举
public enum ControlCommand: Equatable, Sendable {
    case unlock
    case lock
    case slidingDoorLeft(open: Bool)
    case slidingDoorRight(open: Bool)
    case horn
    case trunk(open: Bool)
    case frunk(open: Bool)
    case batteryPreheat(on: Bool)
    case acOn
    case acOff
    case quickCool
    case quickHeat
    case deodorize
    case defrost
    case climate(ClimateControlRequest)
    case unlockCharger
    case startCharging
    case stopCharging
    case window(percentCode: String) // "0" 全关, "2" 通风, "5" 半开
    case sunshade(open: Bool)
    case sunroof(open: Bool)
    case seatHeating(role: SeatRole, level: Int)
    case seatVentilation(role: SeatRole, level: Int)
    case steeringWheelHeating(level: Int)
    case sentryMode(on: Bool)
    case mirrorHeating(on: Bool)
    case seatRowMode(twoRow: Bool)
    case fridge(FridgeControlRequest)
    case vehicleWake

    /// 构造并验证最终下发给 `/appremotectl` 的 `(cmdid, state, summary)`
    public func buildPayload() throws -> RemoteControlPayload {
        switch self {
        case .unlock:
            return RemoteControlPayload(cmdid: "110", stateJSON: "{\"value\":\"unlock\"}", summary: "解锁")
        case .lock:
            return RemoteControlPayload(cmdid: "110", stateJSON: "{\"value\":\"lock\"}", summary: "上锁")
        case .slidingDoorLeft(let open):
            return RemoteControlPayload(
                cmdid: "111",
                stateJSON: "{\"position\":\"secondRowDriverSide\",\"value\":\"\(open ? "100" : "0")\"}",
                summary: open ? "打开左侧滑门" : "关闭左侧滑门"
            )
        case .slidingDoorRight(let open):
            return RemoteControlPayload(
                cmdid: "111",
                stateJSON: "{\"position\":\"secondRowPassengerSide\",\"value\":\"\(open ? "100" : "0")\"}",
                summary: open ? "打开右侧滑门" : "关闭右侧滑门"
            )
        case .horn:
            return RemoteControlPayload(cmdid: "120", stateJSON: "{\"value\":\"true\"}", summary: "鸣笛寻车")
        case .trunk(let open):
            return RemoteControlPayload(
                cmdid: "130",
                stateJSON: "{\"value\":\"\(open ? "true" : "false")\"}",
                summary: open ? "打开后备箱" : "关闭后备箱"
            )
        case .frunk(let open):
            return RemoteControlPayload(
                cmdid: "131",
                stateJSON: "{\"value\":\"\(open ? "100" : "0")\"}",
                summary: open ? "打开前备箱" : "关闭前备箱"
            )
        case .batteryPreheat(let on):
            return RemoteControlPayload(
                cmdid: "160",
                stateJSON: "{\"value\":\"\(on ? "ptcon" : "ptcoff")\"}",
                summary: on ? "开启电池预热" : "关闭电池预热"
            )
        case .acOn:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"auto\",\"temperature\":\"24\",\"windlevel\":\"2\",\"mode\":\"nohotcold\",\"circle\":\"in\",\"wshld\":\"1\",\"position\":\"all\"}",
                summary: "开启空调"
            )
        case .acOff:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"off\",\"temperature\":\"24\",\"windlevel\":\"3\",\"mode\":\"nohotcold\",\"circle\":\"in\",\"wshld\":\"1\",\"position\":\"all\"}",
                summary: "关闭空调"
            )
        case .quickCool:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"manual\",\"temperature\":\"18\",\"windlevel\":\"7\",\"mode\":\"cold\",\"circle\":\"in\",\"wshld\":\"1\",\"position\":\"all\"}",
                summary: "极速降温"
            )
        case .quickHeat:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"manual\",\"temperature\":\"32\",\"windlevel\":\"7\",\"mode\":\"hot\",\"circle\":\"in\",\"wshld\":\"1\",\"position\":\"all\"}",
                summary: "极速升温"
            )
        case .deodorize:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"manual\",\"temperature\":\"24\",\"windlevel\":\"7\",\"mode\":\"nohotcold\",\"circle\":\"out\",\"wshld\":\"0\",\"position\":\"all\"}",
                summary: "快速除味"
            )
        case .defrost:
            return RemoteControlPayload(
                cmdid: "170",
                stateJSON: "{\"operate\":\"manual\",\"temperature\":\"24\",\"windlevel\":\"5\",\"mode\":\"cold\",\"circle\":\"out\",\"wshld\":\"1\",\"position\":\"wshld\"}",
                summary: "开启除雾"
            )
        case .climate(let req):
            guard req.temperature >= req.capability.minTemp && req.temperature <= req.capability.maxTemp else {
                throw ControlCommandError.outOfRange("空调温度超出当前车型能力范围（\(req.capability.minTemp)...\(req.capability.maxTemp)°C）")
            }
            guard req.windLevel >= 0 else {
                throw ControlCommandError.outOfRange("空调风量不能小于 0")
            }
            if let minFan = req.capability.minFan, req.windLevel < minFan {
                throw ControlCommandError.outOfRange("空调风量低于当前车型能力范围（最小 \(minFan) 档）")
            }
            if let maxFan = req.capability.maxFan, req.windLevel > maxFan {
                throw ControlCommandError.outOfRange("空调风量超出当前车型能力范围（最大 \(maxFan) 档）")
            }
            let mode = req.temperature >= 27 ? "hot" : "cold"
            let wshld = req.windshieldDefrost ? "1" : "0"
            let json = Self.encodeJSON([
                "operate": "manual",
                "temperature": String(req.temperature),
                "windlevel": String(req.windLevel),
                "mode": mode,
                "circle": req.circle.rawValue,
                "wshld": wshld,
                "position": req.position.rawValue
            ])
            let summary = req.customSummary ?? (req.windshieldDefrost ? "前挡除霜已开启" : "温度已调至 \(req.temperature)°C")
            return RemoteControlPayload(cmdid: "170", stateJSON: json, summary: summary)
        case .unlockCharger:
            return RemoteControlPayload(cmdid: "192", stateJSON: "{\"operation\":\"unlock\"}", summary: "解锁充电枪")
        case .startCharging:
            return RemoteControlPayload(cmdid: "193", stateJSON: "{\"value\":\"start\"}", summary: "开始充电")
        case .stopCharging:
            return RemoteControlPayload(cmdid: "193", stateJSON: "{\"value\":\"finish\"}", summary: "停止充电")
        case .window(let percentCode):
            let label = switch percentCode {
            case "0": "车窗全关"
            case "2": "车窗通风"
            default: "车窗半开"
            }
            return RemoteControlPayload(cmdid: "230", stateJSON: "{\"value\":\"\(percentCode)\"}", summary: label)
        case .sunshade(let open):
            return RemoteControlPayload(cmdid: "240", stateJSON: "{\"value\":\"\(open ? "10" : "0")\"}", summary: open ? "打开遮阳帘" : "关闭遮阳帘")
        case .sunroof(let open):
            return RemoteControlPayload(cmdid: "300", stateJSON: "{\"value\":\"\(open ? "1" : "0")\"}", summary: open ? "打开天窗" : "关闭天窗")
        case .seatHeating(let role, let level):
            guard let pos = role.controlPosition else {
                throw ControlCommandError.unsupportedSeat(role)
            }
            let clamped = min(max(level, 0), 3)
            let state = "{\"position\":\"\(pos)\",\"level\":\"\(clamped)\"}"
            let suffix = clamped == 0 ? "关闭" : "\(clamped)档"
            return RemoteControlPayload(cmdid: "301", stateJSON: state, summary: "\(role.displayName)加热\(suffix)")
        case .seatVentilation(let role, let level):
            guard let pos = role.controlPosition else {
                throw ControlCommandError.unsupportedSeat(role)
            }
            let clamped = min(max(level, 0), 3)
            let state = "{\"position\":\"\(pos)\",\"level\":\"\(clamped)\"}"
            let suffix = clamped == 0 ? "关闭" : "\(clamped)档"
            return RemoteControlPayload(cmdid: "370", stateJSON: state, summary: "\(role.displayName)通风\(suffix)")
        case .steeringWheelHeating(let level):
            let clamped = min(max(level, 0), 2)
            let label = switch clamped {
            case 0: "关闭"
            case 1: "弱档"
            default: "强档"
            }
            return RemoteControlPayload(cmdid: "320", stateJSON: "{\"level\":\"\(clamped)\"}", summary: "方向盘加热\(label)")
        case .sentryMode(let on):
            return RemoteControlPayload(cmdid: "400", stateJSON: "{\"operation\":\"\(on ? "on" : "off")\"}", summary: on ? "开启哨兵模式" : "关闭哨兵模式")
        case .mirrorHeating(let on):
            return RemoteControlPayload(cmdid: "440", stateJSON: "{\"value\":\"\(on ? "2" : "1")\"}", summary: on ? "开启后视镜加热" : "关闭后视镜加热")
        case .seatRowMode(let twoRow):
            return RemoteControlPayload(cmdid: "470", stateJSON: "{\"control\":\"\(twoRow ? "back" : "reset")\"}", summary: twoRow ? "二排模式" : "三排模式")
        case .fridge(let req):
            let clampedTemp = req.mode == .hot ? 50 : min(max(req.temperature, -6), 15)
            let validDuration = max(req.durationSeconds, 1800)
            let validCycles = req.cycles == "2" ? "2" : "1"
            let obj: [String: Any] = [
                "cycles": validCycles,
                "duration": validDuration,
                "enable": req.enable ? 1 : 0,
                "mode": req.mode.rawValue,
                "parkEnable": req.parkEnable ? 1 : 0,
                "style": req.style.rawValue,
                "temp": clampedTemp,
                "value": req.value
            ]
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            let json = String(data: data, encoding: .utf8) ?? "{}"
            let summary: String
            if req.enable {
                let modeDesc = req.mode == .hot ? "制热 50°C" : "制冷 \(clampedTemp)°C"
                let styleDesc = req.style == .turbo ? "急速" : "标准"
                summary = "开启车载冰箱（\(modeDesc) \(styleDesc)）"
            } else {
                summary = "关闭车载冰箱"
            }
            return RemoteControlPayload(cmdid: "500", stateJSON: json, summary: summary)
        case .vehicleWake:
            return RemoteControlPayload(cmdid: "710", stateJSON: "{\"value\":\"true\"}", summary: "拉取车端数据")
        }
    }

    private static func encodeJSON(_ dict: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

public enum ControlCommandError: Error, LocalizedError, Equatable {
    case outOfRange(String)
    case unsupportedSeat(SeatRole)

    public var errorDescription: String? {
        switch self {
        case .outOfRange(let msg):
            return msg
        case .unsupportedSeat(let role):
            return "\(role.displayName)暂不支持远程加热或通风控制"
        }
    }
}
