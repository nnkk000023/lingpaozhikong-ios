import Foundation

/// 离线演示与体验模式内置数据（无需登录或实车，即可体验全车 UI、33 色车漆切换与座舱交互）
public enum DemoVehicleFixtures {
    public static let demoVehicles: [Vehicle] = [
        Vehicle(
            vin: "LPZ000C16DEMO2026",
            carType: "C16",
            hvacCapability: HvacCapability(minTemp: 16, maxTemp: 32, minFan: 1, maxFan: 9),
            vehicleName: "零跑 C16 · 尊享六座",
            year: "2026",
            outColor: "tianmu_gray",
            powertrain: .reev,
            isShared: false,
            rightList: ["380"],
            abilities: ["seatHeating", "seatVentilation", "steeringWheelHeating", "fridge"]
        ),
        Vehicle(
            vin: "LPZ000D19DEMO2026",
            carType: "D19",
            hvacCapability: HvacCapability(minTemp: 16, maxTemp: 32, minFan: 1, maxFan: 9),
            vehicleName: "零跑 D19 · 旗舰七座",
            year: "2026",
            outColor: "pine_valley_green",
            powertrain: .bev,
            isShared: false,
            rightList: [],
            abilities: ["seatHeating", "seatVentilation", "fridge"]
        ),
        Vehicle(
            vin: "LPZ000LAFA5DEMO26",
            carType: "Lafa5",
            hvacCapability: HvacCapability(minTemp: 16, maxTemp: 32, minFan: 1, maxFan: 9),
            vehicleName: "零跑 Lafa5 · 灵动两厢",
            year: "2026",
            outColor: "speed_orange",
            powertrain: .bev,
            isShared: false,
            rightList: [],
            abilities: ["seatHeating"]
        )
    ]

    public static func makeDemoTelemetry(isReev: Bool = true) -> VehicleTelemetry {
        VehicleTelemetry(
            soc: 78,
            preciseSoc: 78.4,
            fuelSoc: isReev ? 64.0 : nil,
            chargeState: 0,
            chargeRemainTimeMinutes: 0,
            batteryCurrent: -0.4,
            batteryVoltage: 368.5,
            dcInputFastCharge: false,
            acInputSlowCharge: false,
            minBatteryTemp: 22.0,
            healthyChargeEnabled: true,
            healthyChargeTargetSoc: 90,
            chargeScheduleEnabled: true,
            chargeScheduleStart: "23:00",
            chargeScheduleEnd: "07:00",
            chargeScheduleCycles: "1,2,3,4,5,6,7",
            chargeScheduleCirculation: 1,
            chargeScheduleRecharge: false,
            electricRangeKm: 162,
            fuelRangeKm: isReev ? 584 : 0,
            combinedRangeKm: isReev ? 746 : 518,
            totalMileageKm: 12_486.0,
            speedKmh: 0,
            latitude: 30.2084,
            longitude: 120.2121,
            isLocked: true,
            driverDoorOpen: false,
            passengerDoorOpen: false,
            leftRearDoorOpen: false,
            rightRearDoorOpen: false,
            trunkOpen: false,
            hoodOpen: false,
            mirrorsFolded: true,
            leftFrontWindowOpening: 0,
            rightFrontWindowOpening: 0,
            leftRearWindowOpening: 0,
            rightRearWindowOpening: 0,
            sunroofOpening: 0,
            sentryModeOn: false,
            acOn: false,
            acTargetTemp: 24,
            interiorTemp: 23.5,
            acWindLevel: 3,
            recirculationIn: true,
            windshieldDefrostOn: false,
            rearMirrorHeatingOn: false,
            steeringWheelHeatingLevel: 0,
            driverSeatHeating: 0,
            driverSeatVentilation: 0,
            passengerSeatHeating: 0,
            passengerSeatVentilation: 0,
            leftRearSeatHeating: 0,
            leftRearSeatVentilation: 0,
            rightRearSeatHeating: 0,
            rightRearSeatVentilation: 0,
            leftFrontTirePressure: 248,
            rightFrontTirePressure: 249,
            leftRearTirePressure: 251,
            rightRearTirePressure: 250,
            leftFrontTireAlert: false,
            rightFrontTireAlert: false,
            leftRearTireAlert: false,
            rightRearTireAlert: false,
            fridgeOn: false,
            fridgeTargetTemp: 4,
            fridgeMode: "cold"
        )
    }

    public static let demoWeeklyMetrics: [DailyDrivingMetric] = [
        DailyDrivingMetric(dateLabel: "周一", mileageKm: 34.2, energyKwh: 5.1),
        DailyDrivingMetric(dateLabel: "周二", mileageKm: 41.8, energyKwh: 6.0),
        DailyDrivingMetric(dateLabel: "周三", mileageKm: 22.5, energyKwh: 3.4),
        DailyDrivingMetric(dateLabel: "周四", mileageKm: 56.0, energyKwh: 8.3),
        DailyDrivingMetric(dateLabel: "周五", mileageKm: 38.9, energyKwh: 5.6),
        DailyDrivingMetric(dateLabel: "周六", mileageKm: 82.4, energyKwh: 12.1),
        DailyDrivingMetric(dateLabel: "周日", mileageKm: 46.7, energyKwh: 6.7)
    ]

    public static let demoEnergyComposition = EnergyComposition(
        drivingKwh: 34.8,
        climateKwh: 6.4,
        batteryThermalKwh: 2.3,
        standbyAndOtherKwh: 3.7,
        rankPercentile: 86
    )

    public static let demoLocationWeather = VehicleLocationWeather(
        formattedAddress: "浙江省杭州市滨江区物联网街零跑科创园区",
        adcode: "330108",
        cityName: "杭州市",
        weatherText: "多云",
        temperatureCelsius: "22",
        windDirection: "东南",
        windPower: "3"
    )

    /// 离线演示模式下即时将远程控车命令回写至当前车况状态，便于零真车验证全部动画与 UI
    public static func applySimulatedCommand(_ command: ControlCommand, to telemetry: inout VehicleTelemetry) {
        switch command {
        case .unlock:
            telemetry.isLocked = false
            telemetry.mirrorsFolded = false
        case .lock:
            telemetry.isLocked = true
            telemetry.mirrorsFolded = true
        case .trunk(let open):
            telemetry.trunkOpen = open
        case .frunk(let open):
            telemetry.hoodOpen = open
        case .acOn:
            telemetry.acOn = true
            telemetry.acTargetTemp = 24
            telemetry.activeClimateMode = .cool
        case .acOff:
            telemetry.acOn = false
            telemetry.windshieldDefrostOn = false
            telemetry.activeClimateMode = .off
        case .quickCool:
            if telemetry.activeClimateMode == .quickCool && telemetry.acOn {
                telemetry.acOn = false
                telemetry.activeClimateMode = .off
            } else {
                telemetry.acOn = true
                telemetry.acTargetTemp = 18
                telemetry.acWindLevel = 7
                telemetry.windshieldDefrostOn = false
                telemetry.activeClimateMode = .quickCool
            }
        case .quickHeat:
            if telemetry.activeClimateMode == .quickHeat && telemetry.acOn {
                telemetry.acOn = false
                telemetry.activeClimateMode = .off
            } else {
                telemetry.acOn = true
                telemetry.acTargetTemp = 32
                telemetry.acWindLevel = 7
                telemetry.windshieldDefrostOn = false
                telemetry.activeClimateMode = .quickHeat
            }
        case .deodorize:
            if telemetry.activeClimateMode == .deodorize && telemetry.acOn {
                telemetry.acOn = false
                telemetry.activeClimateMode = .off
            } else {
                telemetry.acOn = true
                telemetry.recirculationIn = false
                telemetry.acWindLevel = 7
                telemetry.activeClimateMode = .deodorize
            }
        case .defrost:
            if telemetry.activeClimateMode == .defrost && telemetry.acOn {
                telemetry.acOn = false
                telemetry.windshieldDefrostOn = false
                telemetry.activeClimateMode = .off
            } else {
                telemetry.acOn = true
                telemetry.windshieldDefrostOn = true
                telemetry.activeClimateMode = .defrost
            }
        case .climate(let req):
            telemetry.acOn = true
            telemetry.acTargetTemp = Double(req.temperature)
            telemetry.acWindLevel = req.windLevel
            telemetry.recirculationIn = (req.circle == .internalLoop)
            telemetry.windshieldDefrostOn = req.windshieldDefrost
            if req.windshieldDefrost {
                telemetry.activeClimateMode = .defrost
            } else if req.temperature >= 26 {
                telemetry.activeClimateMode = .heat
            } else {
                telemetry.activeClimateMode = .cool
            }
        case .startCharging:
            telemetry.chargeState = 1
            telemetry.dcInputFastCharge = true
            telemetry.batteryCurrent = 132.5
            telemetry.batteryVoltage = 386.0
            telemetry.chargeRemainTimeMinutes = 24
            telemetry.minBatteryTemp = telemetry.minBatteryTemp ?? 22.0
            telemetry.avgBatteryTemp = 24.5
        case .stopCharging, .unlockCharger:
            telemetry.chargeState = 0
            telemetry.dcInputFastCharge = false
            telemetry.acInputSlowCharge = false
            telemetry.batteryCurrent = -0.3
            telemetry.chargeRemainTimeMinutes = 0
        case .window(let code):
            let opening = code == "0" ? 0 : (code == "2" ? 20 : 50)
            telemetry.leftFrontWindowOpening = opening
            telemetry.rightFrontWindowOpening = opening
            telemetry.leftRearWindowOpening = opening
            telemetry.rightRearWindowOpening = opening
        case .sunroof(let open):
            telemetry.sunroofOpening = open ? 100 : 0
        case .seatHeating(let role, let level):
            switch role {
            case .driver: telemetry.driverSeatHeating = level; if level > 0 { telemetry.driverSeatVentilation = 0 }
            case .passenger: telemetry.passengerSeatHeating = level; if level > 0 { telemetry.passengerSeatVentilation = 0 }
            case .rearLeft: telemetry.leftRearSeatHeating = level; if level > 0 { telemetry.leftRearSeatVentilation = 0 }
            case .rearRight: telemetry.rightRearSeatHeating = level; if level > 0 { telemetry.rightRearSeatVentilation = 0 }
            default: break
            }
        case .seatVentilation(let role, let level):
            switch role {
            case .driver: telemetry.driverSeatVentilation = level; if level > 0 { telemetry.driverSeatHeating = 0 }
            case .passenger: telemetry.passengerSeatVentilation = level; if level > 0 { telemetry.passengerSeatHeating = 0 }
            case .rearLeft: telemetry.leftRearSeatVentilation = level; if level > 0 { telemetry.leftRearSeatHeating = 0 }
            case .rearRight: telemetry.rightRearSeatVentilation = level; if level > 0 { telemetry.rightRearSeatHeating = 0 }
            default: break
            }
        case .steeringWheelHeating(let level):
            telemetry.steeringWheelHeatingLevel = level
        case .sentryMode(let on):
            telemetry.sentryModeOn = on
        case .mirrorHeating(let on):
            telemetry.rearMirrorHeatingOn = on
        case .fridge(let req):
            telemetry.fridgeOn = req.enable
            telemetry.fridgeTargetTemp = req.mode == .hot ? 50 : req.temperature
            telemetry.fridgeMode = req.mode.rawValue
        case .batteryPreheat, .horn, .sunshade, .slidingDoorLeft, .slidingDoorRight, .seatRowMode, .vehicleWake:
            break
        }
        telemetry.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }
}
