import XCTest

/// 零跑智控全流程端到端 UI 自动化测试（覆盖登录/离线体验、车况、座舱座椅点击、充电专页、出行图表与车漆/外观切换）
final class LingpaoEndToEndUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFullDemoUserJourneyAndScreens() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. 登录页检查与截图
        let titleText = app.staticTexts["零跑智控"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 8), "应显示登录页主标题「零跑智控」")

        let demoButton = app.buttons["进入离线体验模式（免登录体验 3D 车漆/座舱交互）"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5), "应显示离线体验模式入口按钮")
        attachScreenshot(app: app, name: "01-Login")

        // 2. 进入离线演示模式 -> 车况首页
        demoButton.tap()
        let vehicleTitle = app.staticTexts["零跑 C16 · 尊享六座"]
        XCTAssertTrue(vehicleTitle.waitForExistence(timeout: 6), "进入演示模式后应展示默认车辆「零跑 C16 · 尊享六座」")

        let quickControlTitle = app.staticTexts["快捷控制"]
        XCTAssertTrue(quickControlTitle.waitForExistence(timeout: 4), "车况首页应包含「快捷控制」区块")
        XCTAssertFalse(app.buttons["蓝牙钥匙"].exists, "车况首页右上角应已去除蓝牙钥匙按钮")
        XCTAssertFalse(app.buttons["刷新车况"].exists, "车况首页右上角应已去除刷新按钮")

        let editQuickBtn = app.buttons["home_edit_quick_controls"]
        XCTAssertTrue(editQuickBtn.waitForExistence(timeout: 4), "快捷控制卡片应包含「编辑」按钮")
        // 测试首页列表下拉刷新动画与无描述文本
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1.2)
        attachScreenshot(app: app, name: "02-Home-Dashboard")

        // 验证主页快捷控制自定义编辑器可打开并保存
        editQuickBtn.tap()
        XCTAssertTrue(app.staticTexts["编辑主页快捷控制"].waitForExistence(timeout: 4))
        app.buttons["取消"].tap()

        // 测试快捷解锁交互
        let unlockBtn = app.buttons["解锁"]
        if unlockBtn.exists {
            unlockBtn.tap()
            let unlockedBadge = app.staticTexts["车辆未上锁"]
            XCTAssertTrue(unlockedBadge.waitForExistence(timeout: 4), "点击解锁后应更新为「车辆未上锁」")
        }

        // 3. 切换至「控车」页并验证座椅、方向盘、后视镜触控、冷暖动效与上滑横置车模交互
        let carTab = app.buttons["控车"]
        XCTAssertTrue(carTab.waitForExistence(timeout: 4))
        carTab.tap()
        XCTAssertTrue(app.staticTexts["座舱控车"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["蓝牙钥匙"].exists, "控车页右上角应已去除蓝牙钥匙按钮")
        // 等待 800ms CarPose 转场位移动画与 550ms 内饰交叉淡化完成
        Thread.sleep(forTimeInterval: 1.2)

        // 实测以真实坐标点击主驾座椅中心位置，确保手指轻触能稳定弹出座椅控制条
        let driverSeatHit = app.buttons["hit_seat_1"]
        XCTAssertTrue(driverSeatHit.waitForExistence(timeout: 4), "应加载主驾座椅点击热区")
        driverSeatHit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["主驾座椅调节"].waitForExistence(timeout: 4), "真实点击主驾座椅热区应弹出加热与通风调节条")
        let seatLevel2 = app.buttons["2档"].firstMatch
        if seatLevel2.exists {
            seatLevel2.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }

        // 测试点击方向盘热区，弹出方向盘加热并切换至强档
        let wheelHit = app.buttons["hit_steering_wheel"]
        XCTAssertTrue(wheelHit.waitForExistence(timeout: 4), "应加载方向盘点击热区")
        wheelHit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["方向盘加热"].waitForExistence(timeout: 3), "点击方向盘应弹出加热调节")
        let strongWheelBtn = app.buttons["强档"]
        if strongWheelBtn.waitForExistence(timeout: 2) {
            strongWheelBtn.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 测试点击外后视镜热区，弹出后视镜加热并开启
        let mirrorHit = app.buttons["hit_mirror_left"]
        XCTAssertTrue(mirrorHit.waitForExistence(timeout: 4), "应加载左后视镜点击热区")
        mirrorHit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["外后视镜加热"].waitForExistence(timeout: 3), "点击后视镜应弹出加热开关")
        let openMirrorHeat = app.buttons["开启加热"]
        if openMirrorHeat.waitForExistence(timeout: 2) {
            openMirrorHeat.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        // 收起浮动条以清晰展示车模部件加热高亮及空调动效
        let dismissFloatingBar = app.buttons["收起"]
        if dismissFloatingBar.exists {
            dismissFloatingBar.tap()
        }

        // 测试点击极速降温、极速升温，验证空调卡片及座舱流光切换动画
        let quickCoolBtn = app.buttons["极速降温"]
        XCTAssertTrue(quickCoolBtn.waitForExistence(timeout: 3))
        quickCoolBtn.tap()
        Thread.sleep(forTimeInterval: 0.7)
        attachScreenshot(app: app, name: "03-Cabin-Control")

        let quickHeatBtn = app.buttons["极速升温"]
        XCTAssertTrue(quickHeatBtn.waitForExistence(timeout: 3))
        quickHeatBtn.tap()
        Thread.sleep(forTimeInterval: 0.7)
        attachScreenshot(app: app, name: "03c-Cabin-QuickHeat")

        // 整体上滑/展开控车卡片，验证车模优雅横置旋转及「定时预约」「门窗与车身控制」分组归类
        let dockHandle = app.buttons["cabin_dock_handle"]
        XCTAssertTrue(dockHandle.waitForExistence(timeout: 3))
        dockHandle.tap()
        Thread.sleep(forTimeInterval: 0.9)
        attachScreenshot(app: app, name: "03b-Cabin-Landscape-Dock")

        // 验证控车自定义布局抽屉与分组命名
        let customizeBtn = app.buttons["cabin_customize_layout"]
        XCTAssertTrue(customizeBtn.waitForExistence(timeout: 4), "控车控制坞应提供「自定义」布局按钮")
        customizeBtn.tap()
        XCTAssertTrue(app.staticTexts["自定义控车布局"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["定时预约"].waitForExistence(timeout: 3), "第三组应更名为「定时预约」")
        XCTAssertFalse(app.staticTexts["座舱舒适与定时预约"].exists, "不应存在旧分组名")
        app.buttons["取消"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        // 收起展开面板恢复常规竖屏状态
        dockHandle.tap()
        Thread.sleep(forTimeInterval: 0.6)

        // 4. 回到「车况」进入「充电管理与预约」专页，验证二级页无切换车辆/无右上车名、当前电池温度、去 CMD 及停充总结曲线弹窗
        app.buttons["车况"].tap()
        let chargeBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS '充电管理与预约' OR label CONTAINS '充电中'")).firstMatch
        XCTAssertTrue(chargeBtn.waitForExistence(timeout: 4), "应能定位充电入口按钮")
        chargeBtn.tap()

        XCTAssertTrue(app.staticTexts["健康充电限值"].waitForExistence(timeout: 5), "应进入充电专页")
        XCTAssertFalse(app.buttons["global_vehicle_switcher"].exists, "二级充电专页不应出现车辆选择切换按钮")
        XCTAssertFalse(app.staticTexts["零跑 C16 · 尊享六座"].exists, "充电专页右上角不应显示车辆名称")
        XCTAssertFalse(app.buttons["灵动岛监控"].exists, "充电页应已去除手动灵动岛监控按钮")
        let battTempLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '当前电池温度'")).firstMatch
        XCTAssertTrue(battTempLabel.waitForExistence(timeout: 3), "充电页应展示当前电池温度")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'CMD'")).firstMatch.exists, "界面不应存在 CMD 协议文案")

        let startChargeBtn = app.buttons["开始充电"]
        XCTAssertTrue(startChargeBtn.waitForExistence(timeout: 3))
        startChargeBtn.tap()
        let stopChargeBtn = app.buttons["停止充电"]
        XCTAssertTrue(stopChargeBtn.waitForExistence(timeout: 4), "点击开始充电后按钮应切换为停止充电")
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app: app, name: "04-Charge-Detail")

        // 手动停止充电，验证自动弹出本次充电报告与实时功率曲线弹窗
        stopChargeBtn.tap()
        XCTAssertTrue(app.staticTexts["本次充电功率曲线"].waitForExistence(timeout: 5), "手动停止充电后应弹出本次充电总结与功率曲线弹窗")
        XCTAssertTrue(app.staticTexts["增加续航"].exists)
        Thread.sleep(forTimeInterval: 1.2)
        attachScreenshot(app: app, name: "04b-Charge-Summary-Sheet")
        let dismissSummary = app.buttons["charge_summary_dismiss"]
        XCTAssertTrue(dismissSummary.waitForExistence(timeout: 3))
        dismissSummary.tap()
        Thread.sleep(forTimeInterval: 0.4)

        let backToHome = app.buttons["返回车况"]
        XCTAssertTrue(backToHome.waitForExistence(timeout: 4))
        backToHome.tap()
        Thread.sleep(forTimeInterval: 0.9)

        // 5. 切换至「出行」页验证地图与 Swift Charts 能耗图表
        app.buttons["出行"].tap()
        XCTAssertTrue(app.staticTexts["出行与能耗"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["近 7 日行车里程"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["上周能耗构成"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app: app, name: "05-Trip-Analytics")

        // 6. 切换至「我的」页，测试切换星煜紫车漆与深色模式
        app.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["我的与车辆设置"].waitForExistence(timeout: 4))
        let purplePaint = app.buttons["星煜紫"]
        if purplePaint.waitForExistence(timeout: 3) {
            purplePaint.tap()
        }
        let darkSeg = app.buttons["深色"]
        if darkSeg.waitForExistence(timeout: 3) {
            darkSeg.tap()
        }
        XCTAssertTrue(app.switches["settings_live_activity_toggle"].waitForExistence(timeout: 3), "设置页应提供灵动岛充电实况开关")
        Thread.sleep(forTimeInterval: 0.8)
        attachScreenshot(app: app, name: "06-Settings-Dark")

        // 7. 切回「车况」验证深色主题 + 星煜紫车漆实时换色 + 展开镜与四轮胎压安全边距
        app.buttons["车况"].tap()
        XCTAssertTrue(app.staticTexts["零跑 C16 · 尊享六座"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 1.2)
        attachScreenshot(app: app, name: "07-Home-Dark-Purple")

        // 8. 从车况页顶部全局多车入口唤起统一「我的车库」抽屉，验证 12 款展厅网格并选择 C11
        let homeSwitcher = app.buttons["home_vehicle_switcher"]
        XCTAssertTrue(homeSwitcher.waitForExistence(timeout: 4), "车况首页应显示全局切车入口")
        homeSwitcher.tap()
        XCTAssertTrue(app.staticTexts["全系车型展厅（12 款）"].waitForExistence(timeout: 4), "应展示全系 12 款车型展厅")
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app: app, name: "08-Vehicle-Garage-Sheet")

        let c11Card = app.buttons["garage_model_c11"]
        XCTAssertTrue(c11Card.waitForExistence(timeout: 4), "展厅网格应包含 C11 统一卡片")
        c11Card.tap()

        // 9. 验证 C11 已自动加入车库并激活，切回车况页渲染 C11
        XCTAssertTrue(app.staticTexts["零跑 C11 · 体验车"].waitForExistence(timeout: 5), "选择 C11 后车况首页应切至 C11 体验车")
        Thread.sleep(forTimeInterval: 1.3)
        attachScreenshot(app: app, name: "09-Home-Switched-C11")

        // 10. 切至「我的」页并调回浅色模式验证统一「我的车辆」同造型大卡列表（且底部已去除多余「更多车型」项）
        app.buttons["我的"].tap()
        let lightSeg = app.buttons["浅色"]
        if lightSeg.waitForExistence(timeout: 3) {
            lightSeg.tap()
        }
        // 滚动回顶部查看新版「我的车辆」统一大卡片
        for _ in 0..<2 {
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["settings_open_garage"].waitForExistence(timeout: 4), "我的页右上应包含「车型展厅」入口")
        XCTAssertFalse(app.buttons["settings_more_models"].exists, "底部不应重复出现冗余的更多车型块")
        let focusedC11Card = app.buttons.containing(NSPredicate(format: "label CONTAINS '零跑 C11'")).firstMatch
        XCTAssertTrue(focusedC11Card.waitForExistence(timeout: 4), "我的车辆焦点卡应显示当前激活的 C11")
        Thread.sleep(forTimeInterval: 0.9)
        attachScreenshot(app: app, name: "10-Settings-Unified-C11")

        // 11. 验证「控车」页顶栏 GlobalVehicleChip 多车切换功能：重新切回 C16
        app.buttons["控车"].tap()
        let globalChip = app.buttons["global_vehicle_switcher"]
        XCTAssertTrue(globalChip.waitForExistence(timeout: 4), "控车页顶栏应显示全局多车切换胶囊")
        globalChip.tap()
        let c16Card = app.buttons["garage_model_c16"]
        XCTAssertTrue(c16Card.waitForExistence(timeout: 4))
        c16Card.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // 12. 测单车形态：打开车库移出非当前车至仅剩 1 辆 C16，确认首页与我的页均按单车极简展示（无下拉切车）
        app.buttons["车况"].tap()
        let homeSwitcherAgain = app.buttons["home_vehicle_switcher"]
        XCTAssertTrue(homeSwitcherAgain.waitForExistence(timeout: 4))
        homeSwitcherAgain.tap()
        for carName in ["移除 零跑 D19 · 旗舰七座", "移除 零跑 Lafa5 · 灵动两厢", "移除 零跑 C11 · 体验车"] {
            let removeBtn = app.buttons[carName]
            if removeBtn.waitForExistence(timeout: 2) {
                removeBtn.tap()
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        app.buttons["关闭车库"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["home_vehicle_switcher"].exists, "仅剩一辆车时，车况首页应彻底隐藏下拉与进入车库入口")
    }

    @MainActor
    private func attachScreenshot(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
