import XCTest
@testable import LingpaoCore

final class TelemetryAndCommandTests: XCTestCase {
    func testSignalDictionaryAndTelemetryDecoding() {
        let rawSignals: [String: Any] = [
            "1204": 82,
            "100003": 82.5,
            "2188": 188,
            "1298": 1, // locked
            "1938": 1, // acSwitch on
            "2183": 23.5,
            "1349": 25.0,
            "2646": 248,
            "2100": 2, // driverSeatHeating = 2
            "10709": 1, // fridgeSwitch = 1
            "10707": 5
        ]
        let chargeConfig: [String: Any] = [
            "isEnable": 1,
            "beginTime": "23:00",
            "endTime": "06:30",
            "percent": 85
        ]

        let telemetry = VehicleTelemetry.decode(signalMap: rawSignals, chargeConfig: chargeConfig)
        XCTAssertEqual(telemetry.displaySoc, 82.5)
        XCTAssertEqual(telemetry.electricRangeKm, 188)
        XCTAssertTrue(telemetry.isLocked)
        XCTAssertTrue(telemetry.acOn)
        XCTAssertEqual(telemetry.acTargetTemp, 23.5)
        XCTAssertEqual(telemetry.interiorTemp, 25.0)
        XCTAssertEqual(telemetry.leftFrontTirePressure, 248)
        XCTAssertEqual(telemetry.driverSeatHeating, 2)
        XCTAssertTrue(telemetry.fridgeOn)
        XCTAssertEqual(telemetry.fridgeTargetTemp, 5)
        XCTAssertTrue(telemetry.chargeScheduleEnabled)
        XCTAssertEqual(telemetry.healthyChargeTargetSoc, 85)
    }

    func testAllRemoteCommandsProduceExpectedCmdidAndJSON() throws {
        let unlock = try ControlCommand.unlock.buildPayload()
        XCTAssertEqual(unlock.cmdid, "110")
        XCTAssertEqual(unlock.stateJSON, "{\"value\":\"unlock\"}")

        let sliding = try ControlCommand.slidingDoorLeft(open: true).buildPayload()
        XCTAssertEqual(sliding.cmdid, "111")
        XCTAssertTrue(sliding.stateJSON.contains("secondRowDriverSide"))

        let climate = try ControlCommand.climate(
            ClimateControlRequest(
                temperature: 22,
                capability: HvacCapability(minTemp: 16, maxTemp: 32, minFan: 1, maxFan: 9),
                windLevel: 4,
                circle: .externalLoop,
                windshieldDefrost: true,
                position: .windshield
            )
        ).buildPayload()
        XCTAssertEqual(climate.cmdid, "170")
        let climateDict = try JSONSerialization.jsonObject(with: Data(climate.stateJSON.utf8)) as? [String: String]
        XCTAssertEqual(climateDict?["temperature"], "22")
        XCTAssertEqual(climateDict?["mode"], "cold")
        XCTAssertEqual(climateDict?["wshld"], "1")

        let seat = try ControlCommand.seatVentilation(role: .passenger, level: 3).buildPayload()
        XCTAssertEqual(seat.cmdid, "370")
        XCTAssertEqual(seat.stateJSON, "{\"position\":\"right_front\",\"level\":\"3\"}")

        let fridge = try ControlCommand.fridge(
            FridgeControlRequest(enable: true, mode: .hot, temperature: 10, style: .turbo, parkEnable: true, durationSeconds: 600)
        ).buildPayload()
        XCTAssertEqual(fridge.cmdid, "500")
        let fridgeObj = try JSONSerialization.jsonObject(with: Data(fridge.stateJSON.utf8)) as? [String: Any]
        XCTAssertEqual(fridgeObj?["temp"] as? Int, 50) // 制热模式固定 50
        XCTAssertEqual(fridgeObj?["duration"] as? Int, 1800) // 最低 1800 秒

        XCTAssertThrowsError(try ControlCommand.seatHeating(role: .rearCenter, level: 1).buildPayload())
    }

    func testCarModelAndPaintCatalogMatching() {
        XCTAssertEqual(CarModelCatalog.detectCarType(from: "2026款 零跑B05 运动版"), "Lafa5")
        XCTAssertEqual(CarModelCatalog.detectCarType(from: "C16 REEV 200 尊享版"), "C16")
        let d19 = CarModelCatalog.profile(for: "D19")
        XCTAssertEqual(d19.assetSuffix(for: .seven), "_7")
        XCTAssertFalse(CarModelCatalog.profile(for: "T03").powerFoldMirrors)

        let c16Paints = PaintCatalog.availablePaints(for: "C16")
        XCTAssertTrue(c16Paints.contains(where: { $0.id == "starlight_purple" && $0.argb == 0xFF765D8B }))

        // 验证全系 12 款车型展厅列表完整且无重复，车身形态显示名映射正确
        let showcase = CarModelCatalog.showcaseModels
        XCTAssertEqual(showcase.count, 12)
        XCTAssertEqual(Set(showcase.map(\.id)).count, 12)
        XCTAssertEqual(CarBodyStyle.suv.displayName, "SUV")
        XCTAssertEqual(CarBodyStyle.sedan.displayName, "轿车")
        XCTAssertEqual(CarBodyStyle.hatchback.displayName, "两厢")
        XCTAssertEqual(CarBodyStyle.mpv.displayName, "MPV")
        XCTAssertEqual(CarBodyStyle.micro.displayName, "微车")
    }

    func testBalancedGridAndCurrentBatteryTempAndPreferences() throws {
        // 验证 1~9 个按钮的均衡排布绝无悬空孤格
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 1, maxColumns: 3), [1])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 4, maxColumns: 3), [2, 2])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 5, maxColumns: 3), [3, 2])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 7, maxColumns: 3), [3, 2, 2])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 8, maxColumns: 3), [3, 3, 2])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 6, maxColumns: 4), [3, 3])
        XCTAssertEqual(BalancedGridPartitioner.partition(count: 5, maxColumns: 4), [3, 2])

        // 验证当前电池温度优先级（1183 avgBatteryTemp > 1181/1182 均值 > minBatteryTemp）
        let t1 = VehicleTelemetry.decode(signalMap: ["1182": "19", "1181": "25", "1183": "22.5"])
        XCTAssertEqual(t1.currentBatteryTemp, 22.5)
        let t2 = VehicleTelemetry.decode(signalMap: ["1182": "18", "1181": "24"])
        XCTAssertEqual(t2.currentBatteryTemp, 21.0)
        let t3 = VehicleTelemetry.decode(signalMap: ["1182": "20"])
        XCTAssertEqual(t3.currentBatteryTemp, 20.0)

        // 验证布局偏好序列化、分组重命名（「定时预约」）与方向盘加热移入车身控制
        var prefs = ControlLayoutPreferences.default(for: "C11")
        XCTAssertEqual(CabinControlGroupID.comfortSchedule.displayName, "定时预约")
        XCTAssertTrue(prefs.bodyHardwareActions.contains(.steeringWheelHeat))
        prefs.cabinGroupOrder = [.bodyHardware, .climate, .comfortSchedule]
        prefs.bodyHardwareActions.removeAll { $0 == .frunkToggle }
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ControlLayoutPreferences.self, from: encoded)
        XCTAssertEqual(decoded.cabinGroupOrder, [.bodyHardware, .climate, .comfortSchedule])
        XCTAssertFalse(decoded.bodyHardwareActions.contains(.frunkToggle))

        // 验证空调活跃模式切换
        var simTelemetry = DemoVehicleFixtures.makeDemoTelemetry(isReev: true)
        DemoVehicleFixtures.applySimulatedCommand(.quickCool, to: &simTelemetry)
        XCTAssertEqual(simTelemetry.activeClimateMode, .quickCool)
        XCTAssertTrue(simTelemetry.acOn)
        DemoVehicleFixtures.applySimulatedCommand(.quickCool, to: &simTelemetry)
        XCTAssertEqual(simTelemetry.activeClimateMode, .off)
        XCTAssertFalse(simTelemetry.acOn)
    }
}
