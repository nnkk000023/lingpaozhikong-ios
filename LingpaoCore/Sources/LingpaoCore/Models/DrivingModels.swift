import Foundation

/// 预约空调表单参数模型
public struct ScheduledAcConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// 格式 `HH:mm`（如 `"08:00"`）
    public var startTimeHHMM: String
    /// 星期几列表，1=周一 .. 7=周日（提交服务端时 7 转换为 0）
    public var weekdays: [Int]
    public var temperature: Int
    public var windLevel: Int
    public var circleIn: Bool
    public var windshieldDefrost: Bool

    public init(
        enabled: Bool = false,
        startTimeHHMM: String = "08:00",
        weekdays: [Int] = [1, 2, 3, 4, 5],
        temperature: Int = 24,
        windLevel: Int = 3,
        circleIn: Bool = true,
        windshieldDefrost: Bool = false
    ) {
        self.enabled = enabled
        self.startTimeHHMM = startTimeHHMM
        self.weekdays = weekdays
        self.temperature = temperature
        self.windLevel = windLevel
        self.circleIn = circleIn
        self.windshieldDefrost = windshieldDefrost
    }
}

/// 预约电池预热配置模型
public struct ScheduledBatteryPreheatConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startTimeHHMM: String
    public var weekdays: [Int]

    public init(
        enabled: Bool = false,
        startTimeHHMM: String = "07:30",
        weekdays: [Int] = [1, 2, 3, 4, 5]
    ) {
        self.enabled = enabled
        self.startTimeHHMM = startTimeHHMM
        self.weekdays = weekdays
    }
}

/// 单日行驶里程与能耗数据点
public struct DailyDrivingMetric: Codable, Equatable, Identifiable, Sendable {
    public var id: String { dateLabel }
    public var dateLabel: String
    public var mileageKm: Double
    public var energyKwh: Double

    public init(dateLabel: String, mileageKm: Double, energyKwh: Double) {
        self.dateLabel = dateLabel
        self.mileageKm = mileageKm
        self.energyKwh = energyKwh
    }

    public var avgConsumptionPer100Km: Double {
        guard mileageKm > 0.1 else { return 0 }
        return (energyKwh / mileageKm) * 100.0
    }
}

/// 周能耗构成拆解
public struct EnergyComposition: Codable, Equatable, Sendable {
    public var drivingKwh: Double
    public var climateKwh: Double
    public var batteryThermalKwh: Double
    public var standbyAndOtherKwh: Double
    public var rankPercentile: Int

    public init(
        drivingKwh: Double = 0,
        climateKwh: Double = 0,
        batteryThermalKwh: Double = 0,
        standbyAndOtherKwh: Double = 0,
        rankPercentile: Int = 50
    ) {
        self.drivingKwh = drivingKwh
        self.climateKwh = climateKwh
        self.batteryThermalKwh = batteryThermalKwh
        self.standbyAndOtherKwh = standbyAndOtherKwh
        self.rankPercentile = rankPercentile
    }

    public var totalKwh: Double {
        max(0.01, drivingKwh + climateKwh + batteryThermalKwh + standbyAndOtherKwh)
    }
}

/// 停车环境底盘照片信息
public struct ChassisPhotoInfo: Codable, Equatable, Sendable {
    public var fileURL: String
    public var uploadTimeMs: Int64

    public init(fileURL: String, uploadTimeMs: Int64) {
        self.fileURL = fileURL
        self.uploadTimeMs = uploadTimeMs
    }
}

/// 逆地理编码与天气融合卡片模型
public struct VehicleLocationWeather: Codable, Equatable, Sendable {
    public var formattedAddress: String
    public var adcode: String
    public var cityName: String
    public var weatherText: String
    public var temperatureCelsius: String
    public var windDirection: String
    public var windPower: String

    public init(
        formattedAddress: String,
        adcode: String = "",
        cityName: String = "",
        weatherText: String = "",
        temperatureCelsius: String = "",
        windDirection: String = "",
        windPower: String = ""
    ) {
        self.formattedAddress = formattedAddress
        self.adcode = adcode
        self.cityName = cityName
        self.weatherText = weatherText
        self.temperatureCelsius = temperatureCelsius
        self.windDirection = windDirection
        self.windPower = windPower
    }
}
