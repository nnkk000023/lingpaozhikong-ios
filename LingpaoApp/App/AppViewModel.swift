import Foundation
import LingpaoCore
import Observation
import SwiftUI

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// 全局应用状态管理器（统一驱动真实网络/蓝牙模式、离线演示模式、PIN 弹窗与灵动岛同步）
@MainActor
@Observable
public final class AppViewModel {
    public let apiClient: LeapAPIClient
    public let bleManager = CoreBluetoothKeyManager()

    public var session: SessionState
    public var isDemoMode: Bool = false
    public var appearance: AppearancePreference

    public var vehicles: [Vehicle] = []
    public var selectedVehicle: Vehicle?
    public var telemetry: VehicleTelemetry = DemoVehicleFixtures.makeDemoTelemetry(isReev: true)
    public var locationWeather: VehicleLocationWeather?
    public var weeklyMetrics: [DailyDrivingMetric] = []
    public var energyComposition: EnergyComposition = DemoVehicleFixtures.demoEnergyComposition
    public var chassisPhoto: ChassisPhotoInfo?

    public var activeTab: AppStageRoute = .home
    public var isChargeSheetPresented: Bool = false
    public var isBleSheetPresented: Bool = false
    public var isVehicleGaragePresented: Bool = false
    public var liveActivityEnabled: Bool
    public var layoutPreferences: ControlLayoutPreferences
    public var completedChargeSummary: ChargeSessionSummary?
    public var selectedCabinTarget: CabinInteractiveTarget?
    public var isCabinDockExpanded: Bool = false
    public var loadedCarAssets: LoadedCarAssets?
    public var lightFlashOpacity: Double = 0.0

    /// 按车辆 VIN 独立缓存各自选定的座椅布局，避免多车切换残留布局错乱
    private var perVehicleSeatLayouts: [String: SeatLayout] = [:]
    private var activeChargeTracker: ActiveChargeTracker?
    private var chargeSimTask: Task<Void, Never>?

    public var isBusy: Bool = false
    public var toastMessage: String?
    public var pendingCommandForPin: ControlCommand?
    public var isPinPromptPresented: Bool = false
    public var pinInput: String = ""

    public var geetestChallenge: GeetestChallenge?
    public var smsCountdownSeconds: Int = 0
    public var amapKey: String

    /// 当前激活车辆展示名称
    public var currentVehicleName: String {
        selectedVehicle?.vehicleName ?? session.selectedNickname
    }

    /// 当前激活车型档案
    public var currentCarProfile: CarModelProfile {
        CarModelCatalog.profile(for: selectedVehicle?.carType ?? session.selectedCarType)
    }

    /// 当前激活车漆颜色
    public var currentPaintColor: PaintColor {
        PaintCatalog.resolvePaint(id: session.selectedPaintId, carTypeOrId: currentCarProfile.displayName)
    }

    /// 当前选中车辆在车库清单中的下标
    public var currentVehicleIndex: Int? {
        guard let vin = selectedVehicle?.vin else { return nil }
        return vehicles.firstIndex(where: { $0.vin == vin })
    }

    /// 计算当前呈现给 `InteractiveCarStageView` 的总姿态状态（充电专页优先）
    public var currentStageRoute: AppStageRoute {
        isChargeSheetPresented ? .charge : activeTab
    }

    public init() {
        let store = KeychainStore.shared
        let loadedSession = store.loadSession()
        self.apiClient = LeapAPIClient(store: store)
        self.session = loadedSession
        self.appearance = store.loadAppearance()
        self.amapKey = store.loadAmapKey()
        self.pinInput = store.loadOpPassword()
        self.liveActivityEnabled = store.loadLiveActivityEnabled()
        self.layoutPreferences = store.loadControlLayoutPreferences()
            ?? ControlLayoutPreferences.default(for: loadedSession.selectedCarType)

        bleManager.onDoorActionConfirmed = { [weak self] isLock in
            guard let self else { return }
            self.telemetry.isLocked = isLock
            self.telemetry.mirrorsFolded = isLock
            self.syncSharedSnapshot(lastAction: isLock ? "蓝牙确认上锁" : "蓝牙确认解锁")
            if !self.isDemoMode {
                Task { await self.apiClient.uploadBluetoothRecord(isLock: isLock) }
            }
        }
    }

    // MARK: - 初始化与资产加载

    public func bootstrap() async {
        await reloadCarAssets()
        if session.isLoggedIn {
            await refreshAllOnlineData()
        } else if isDemoMode {
            enterDemoMode()
        }
    }

    public func reloadCarAssets() async {
        let carType = selectedVehicle?.carType ?? session.selectedCarType
        let paintId = session.selectedPaintId
        let layout = session.selectedSeatLayout
        loadedCarAssets = await CarAssetLoader.shared.loadAssets(
            carType: carType,
            paintId: paintId,
            seatLayout: layout
        )
    }

    // MARK: - 登录与演示模式切换

    public func enterDemoMode() {
        isDemoMode = true
        vehicles = DemoVehicleFixtures.demoVehicles
        let first = vehicles.first!
        let defaultLayout = CarModelCatalog.profile(for: first.carType).defaultLayout
        perVehicleSeatLayouts = [first.vin: defaultLayout]
        selectedVehicle = first
        session.selectedVin = first.vin
        session.selectedCarType = first.carType
        session.selectedNickname = first.vehicleName
        session.selectedPaintId = first.outColor
        session.selectedSeatLayout = defaultLayout
        session.hvacCapability = first.hvacCapability
        telemetry = DemoVehicleFixtures.makeDemoTelemetry(isReev: first.isRangeExtender)
        weeklyMetrics = DemoVehicleFixtures.demoWeeklyMetrics
        energyComposition = DemoVehicleFixtures.demoEnergyComposition
        locationWeather = DemoVehicleFixtures.demoLocationWeather
        syncSharedSnapshot(lastAction: "演示模式就绪")
        Task { await reloadCarAssets() }
    }

    public func sendSMSCode(phone: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await apiClient.sendSMSCode(phone: phone)
            showToast("验证码已发送至 \(phone)")
            startCountdown()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func submitPhoneLogin(
        phone: String,
        smsCode: String,
        manualSmDeviceId: String?,
        geetestResult: GeetestValidateResult? = nil
    ) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let resolvedSm = await ShumeiDeviceProvider.resolveDeviceId(
                manualOverride: manualSmDeviceId,
                stored: session.smDeviceId
            )
            let updatedSession = try await apiClient.loginWithPhone(
                phone: phone,
                smsCode: smsCode,
                smDeviceId: resolvedSm,
                geetest: geetestResult
            )
            self.session = updatedSession
            self.isDemoMode = false
            self.geetestChallenge = nil
            showToast("登录成功")
            await refreshAllOnlineData()
        } catch LeapAPIError.geetestChallengeRequired(let challenge) {
            self.geetestChallenge = challenge
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func submitRawAuthLogin(rawText: String, phone: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await apiClient.loginWithRawAuth(rawText: rawText, phoneInput: phone)
            self.session = updated
            self.isDemoMode = false
            showToast("原始凭据导入成功")
            await refreshAllOnlineData()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func logout() {
        KeychainStore.shared.clearSession()
        session = KeychainStore.shared.loadSession()
        isDemoMode = false
        vehicles = []
        selectedVehicle = nil
        perVehicleSeatLayouts = [:]
        isVehicleGaragePresented = false
        chargeSimTask?.cancel()
        chargeSimTask = nil
        activeChargeTracker = nil
        completedChargeSummary = nil
        activeTab = .home
        showToast("已退出登录")
        Task { await syncChargeLiveActivity() }
    }

    // MARK: - 在线数据拉取

    public func refreshAllOnlineData(silent: Bool = false) async {
        guard !isDemoMode, session.isLoggedIn else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let list = try await apiClient.fetchVehicleList()
            vehicles = list
            if let match = list.first(where: { $0.vin == session.selectedVin }) ?? list.first {
                applySelectedVehicleLocally(match)
            }
            let wasCharging = telemetry.isCharging
            async let telemetryTask = apiClient.fetchTelemetry(vin: selectedVehicle?.vin)
            async let metricsTask = apiClient.fetchRecent7DaysEnergy(vin: selectedVehicle?.vin)
            telemetry = try await telemetryTask
            weeklyMetrics = (try? await metricsTask) ?? []
            session = KeychainStore.shared.loadSession()
            handleChargeTransition(previousIsCharging: wasCharging, wasManualStop: false)
            await reloadCarAssets()
            await refreshLocationAndWeather()
            syncSharedSnapshot(lastAction: nil)
            await syncChargeLiveActivity()
        } catch {
            if !silent {
                showToast("刷新失败：\(error.localizedDescription)")
            }
        }
    }

    public func refreshLocationAndWeather() async {
        guard !isDemoMode else {
            locationWeather = DemoVehicleFixtures.demoLocationWeather
            return
        }
        guard let lat = telemetry.latitude, let lon = telemetry.longitude, lat != 0, lon != 0 else { return }
        if let info = try? await apiClient.fetchLocationAndWeather(latitude: lat, longitude: lon, amapKey: amapKey) {
            locationWeather = info
        }
    }

    public func fetchChassisPhotoIfNeeded() async {
        guard !isDemoMode else { return }
        chassisPhoto = try? await apiClient.fetchChassisPhoto(vin: selectedVehicle?.vin)
    }

    // MARK: - 车型与车漆偏好切换

    public func selectVehicle(_ vehicle: Vehicle, showFeedback: Bool = true) {
        if selectedVehicle?.vin != vehicle.vin {
            chargeSimTask?.cancel()
            chargeSimTask = nil
            activeChargeTracker = nil
        }
        selectedCabinTarget = nil
        isCabinDockExpanded = false
        let profile = CarModelCatalog.profile(for: vehicle.carType)
        let savedLayout = perVehicleSeatLayouts[vehicle.vin]
        let validLayout = (savedLayout != nil && profile.supportedLayouts.contains(savedLayout!))
            ? savedLayout!
            : profile.defaultLayout
        perVehicleSeatLayouts[vehicle.vin] = validLayout
        session.selectedSeatLayout = validLayout

        applySelectedVehicleLocally(vehicle)
        if isDemoMode {
            telemetry = DemoVehicleFixtures.makeDemoTelemetry(isReev: vehicle.isRangeExtender)
        }
        if showFeedback {
            showToast("已切换至 \(vehicle.vehicleName)")
        }
        Task {
            await reloadCarAssets()
            await syncChargeLiveActivity()
            if !isDemoMode {
                await refreshAllOnlineData()
            }
        }
    }

    /// 演示模式统一车型展厅切车：已在车库则直接切换，未在车库则新增为体验车并立即激活
    public func addOrSwitchDemoModel(modelId: String) {
        let prof = CarModelCatalog.profile(for: modelId)
        if let existing = vehicles.first(where: { CarModelCatalog.profile(for: $0.carType).id == prof.id }) {
            selectVehicle(existing, showFeedback: true)
            return
        }

        let defaultPaint = PaintCatalog.availablePaints(for: prof.displayName).first?.id ?? "liquid_silver"
        let isReevModel = ["c16", "c11", "c10", "c01", "d19"].contains(prof.id)
        let demo = Vehicle(
            vin: "LPZ000\(prof.id.uppercased())DEMO26",
            carType: prof.displayName,
            hvacCapability: HvacCapability(minTemp: 16, maxTemp: 32, minFan: 1, maxFan: 9),
            vehicleName: "零跑 \(prof.displayName) · 体验车",
            year: "2026",
            outColor: defaultPaint,
            powertrain: isReevModel ? .reev : .bev
        )
        vehicles.append(demo)
        selectVehicle(demo, showFeedback: true)
    }

    /// 演示模式从车库移除指定预览车（至少保留 1 辆默认车）
    public func removeDemoVehicle(vin: String) {
        guard isDemoMode, vehicles.count > 1 else { return }
        vehicles.removeAll { $0.vin == vin }
        perVehicleSeatLayouts.removeValue(forKey: vin)
        if selectedVehicle?.vin == vin, let fallback = vehicles.first {
            selectVehicle(fallback, showFeedback: false)
        }
        showToast("已从演示车库移出")
    }

    /// 在线真实模式：在不改变真实 VIN 的前提下校正本地 3D 渲染车模
    public func overrideLocalCarModel(modelId: String) {
        let prof = CarModelCatalog.profile(for: modelId)
        selectedCabinTarget = nil
        isCabinDockExpanded = false
        session.selectedCarType = prof.displayName
        session.selectedSeatLayout = prof.defaultLayout
        if var current = selectedVehicle {
            current.carType = prof.displayName
            selectedVehicle = current
            if let idx = vehicles.firstIndex(where: { $0.vin == current.vin }) {
                vehicles[idx].carType = prof.displayName
            }
            perVehicleSeatLayouts[current.vin] = prof.defaultLayout
        }
        KeychainStore.shared.saveSession(session)
        showToast("已将本地渲染车型调整为 \(prof.displayName)")
        Task { await reloadCarAssets() }
    }

    private func applySelectedVehicleLocally(_ vehicle: Vehicle) {
        selectedVehicle = vehicle
        session.selectedVin = vehicle.vin
        session.selectedCarType = vehicle.carType
        session.selectedNickname = vehicle.vehicleName
        session.selectedYear = vehicle.year
        session.selectedPaintId = vehicle.outColor
        session.hvacCapability = vehicle.hvacCapability
        KeychainStore.shared.saveSession(session)
    }

    public func updatePaint(id: String) {
        session.selectedPaintId = id
        if var current = selectedVehicle {
            current.outColor = id
            selectedVehicle = current
            if let idx = vehicles.firstIndex(where: { $0.vin == current.vin }) {
                vehicles[idx].outColor = id
            }
        }
        KeychainStore.shared.saveSession(session)
        Task { await reloadCarAssets() }
    }

    public func updateSeatLayout(_ layout: SeatLayout) {
        session.selectedSeatLayout = layout
        if !session.selectedVin.isEmpty {
            perVehicleSeatLayouts[session.selectedVin] = layout
        }
        KeychainStore.shared.saveSession(session)
        Task { await reloadCarAssets() }
    }

    public func updateAppearance(_ pref: AppearancePreference) {
        appearance = pref
        KeychainStore.shared.saveAppearance(pref)
    }

    public func saveAmapKey(_ key: String) {
        amapKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.shared.saveAmapKey(amapKey)
        showToast("高德 Web 服务 Key 已保存")
        Task { await refreshLocationAndWeather() }
    }

    public func saveControlPin(_ pin: String) {
        pinInput = pin
        KeychainStore.shared.saveOpPassword(pin)
        showToast("4 位操控密码已安全保存至 Keychain")
    }

    // MARK: - 远程控车与双闪烁动画

    public func executeControl(_ command: ControlCommand) {
        let savedPin = KeychainStore.shared.loadOpPassword()
        if isDemoMode {
            performSimulatedControl(command)
            return
        }
        guard !savedPin.isEmpty else {
            pendingCommandForPin = command
            isPinPromptPresented = true
            return
        }
        Task { await sendOnlineCommand(command, pin: savedPin) }
    }

    public func confirmPinAndExecute(_ pin: String) {
        KeychainStore.shared.saveOpPassword(pin)
        self.pinInput = pin
        isPinPromptPresented = false
        guard let cmd = pendingCommandForPin else { return }
        pendingCommandForPin = nil
        Task { await sendOnlineCommand(cmd, pin: pin) }
    }

    private func sendOnlineCommand(_ command: ControlCommand, pin: String) async {
        isBusy = true
        defer { isBusy = false }
        let isManualStop: Bool = {
            switch command {
            case .stopCharging, .unlockCharger: return true
            default: return false
            }
        }()
        do {
            let payload = try command.buildPayload()
            let msgID = try await apiClient.sendRemoteControl(command: command, opPassword: pin)
            let wasCharging = telemetry.isCharging
            DemoVehicleFixtures.applySimulatedCommand(command, to: &telemetry)
            handleChargeTransition(previousIsCharging: wasCharging, wasManualStop: isManualStop)
            syncSharedSnapshot(lastAction: payload.summary)
            showToast("\(payload.summary)已下发")
            triggerLightFlashIfNeeded(command)
            await syncChargeLiveActivity()

            // 后台轻量轮询最终执行态并刷新车况
            if !msgID.isEmpty {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                _ = try? await apiClient.queryRemoteControlResult(msgID: msgID)
                if let latest = try? await apiClient.fetchTelemetry(vin: selectedVehicle?.vin) {
                    let prevCharging = telemetry.isCharging
                    telemetry = latest
                    handleChargeTransition(previousIsCharging: prevCharging, wasManualStop: false)
                    syncSharedSnapshot(lastAction: nil)
                    await syncChargeLiveActivity()
                }
            }
        } catch {
            showToast("控车失败：\(error.localizedDescription)")
        }
    }

    private func performSimulatedControl(_ command: ControlCommand) {
        let isManualStop: Bool = {
            switch command {
            case .stopCharging, .unlockCharger: return true
            default: return false
            }
        }()
        do {
            let payload = try command.buildPayload()
            let wasCharging = telemetry.isCharging
            DemoVehicleFixtures.applySimulatedCommand(command, to: &telemetry)
            handleChargeTransition(previousIsCharging: wasCharging, wasManualStop: isManualStop)
            syncSharedSnapshot(lastAction: "\(payload.summary)（演示）")
            showToast("\(payload.summary)成功（演示模式）")
            triggerLightFlashIfNeeded(command)
            Task { await syncChargeLiveActivity() }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// 精确复刻 `lights_glow_only.webp` 两次呼吸车灯闪烁动画（120ms 淡入 -> 220ms 淡出 -> 100ms 间隔 -> 重复）
    private func triggerLightFlashIfNeeded(_ command: ControlCommand) {
        switch command {
        case .unlock, .horn:
            Task {
                for flashIndex in 0..<2 {
                    withAnimation(.easeIn(duration: 0.12)) { lightFlashOpacity = 1.0 }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    withAnimation(.easeOut(duration: 0.22)) { lightFlashOpacity = 0.0 }
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    if flashIndex == 0 {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            }
        default:
            break
        }
    }

    // MARK: - BLE 数字钥匙管理

    public func syncAndPrepareBleKey() async {
        let vin = selectedVehicle?.vin ?? session.selectedVin
        let accountId = session.oldSession?.accountId ?? ""
        guard !vin.isEmpty, !accountId.isEmpty else {
            showToast("请先登录真实账号后再同步蓝牙证书")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let cert = try await apiClient.syncBluetoothKeyCertificate(vin: vin)
            KeychainStore.shared.saveBleCertificate(cert, accountId: accountId)
            bleManager.configure(
                certificate: cert,
                accountId: accountId,
                deviceId: session.deviceId,
                passiveConfig: KeychainStore.shared.loadPassiveConfig()
            )
            showToast("蓝牙证书同步成功（\(cert.keyType.displayName)）")
        } catch {
            showToast("证书同步失败：\(error.localizedDescription)")
        }
    }

    public func prepareBleFromCache() {
        let vin = selectedVehicle?.vin ?? session.selectedVin
        let accountId = session.oldSession?.accountId ?? ""
        let cert = (!vin.isEmpty && !accountId.isEmpty) ? KeychainStore.shared.loadBleCertificate(accountId: accountId, vin: vin) : nil
        bleManager.configure(
            certificate: cert,
            accountId: accountId,
            deviceId: session.deviceId,
            passiveConfig: KeychainStore.shared.loadPassiveConfig()
        )
    }

    // MARK: - App Group 快照与灵动岛 Live Activity

    public func syncSharedSnapshot(lastAction: String?) {
        let snapshot = SharedVehicleSnapshot(
            vin: selectedVehicle?.vin ?? session.selectedVin,
            vehicleName: selectedVehicle?.vehicleName ?? session.selectedNickname,
            carType: selectedVehicle?.carType ?? session.selectedCarType,
            paintId: session.selectedPaintId,
            soc: telemetry.displaySoc,
            rangeKm: telemetry.electricRangeKm,
            isLocked: telemetry.isLocked,
            acOn: telemetry.acOn,
            interiorTemp: telemetry.interiorTemp,
            isCharging: telemetry.isCharging,
            chargePowerKw: telemetry.chargePowerKw,
            chargeRemainMinutes: telemetry.chargeRemainTimeMinutes,
            updatedAt: Date(),
            lastActionMessage: lastAction
        )
        SharedSnapshotStore.save(snapshot)
    }

    // MARK: - 自定义布局、灵动岛总开关与充电会话曲线追踪

    public func saveLayoutPreferences(_ prefs: ControlLayoutPreferences) {
        layoutPreferences = prefs
        KeychainStore.shared.saveControlLayoutPreferences(prefs)
        showToast("已保存自定义布局")
    }

    public func resetLayoutPreferences() {
        let def = ControlLayoutPreferences.default(for: currentCarProfile.displayName)
        layoutPreferences = def
        KeychainStore.shared.saveControlLayoutPreferences(def)
        showToast("已恢复默认功能布局")
    }

    public func updateLiveActivityEnabled(_ enabled: Bool) {
        liveActivityEnabled = enabled
        KeychainStore.shared.saveLiveActivityEnabled(enabled)
        showToast(enabled ? "已开启灵动岛充电实况" : "已关闭灵动岛充电实况")
        Task { await syncChargeLiveActivity() }
    }

    /// 仅当开关打开且车辆处于充电中时自动启动/刷新灵动岛；充电结束或关闭开关即自动收回
    public func syncChargeLiveActivity() async {
        #if canImport(ActivityKit) && os(iOS)
        let shouldShow = liveActivityEnabled && telemetry.isCharging
        let activities = Activity<ChargeActivityAttributes>.activities

        guard shouldShow else {
            for act in activities {
                await act.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let state = makeLiveActivityState()
        if let existing = activities.first {
            await existing.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600)))
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = ChargeActivityAttributes(
            vehicleName: selectedVehicle?.vehicleName ?? session.selectedNickname,
            carType: selectedVehicle?.carType ?? session.selectedCarType
        )
        _ = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600))
        )
        #endif
    }

    private func handleChargeTransition(previousIsCharging: Bool, wasManualStop: Bool) {
        let isNowCharging = telemetry.isCharging

        if !previousIsCharging && isNowCharging {
            beginChargeSessionTracking()
        } else if previousIsCharging && isNowCharging {
            appendRealChargeSampleIfTracking()
        } else if previousIsCharging && !isNowCharging {
            finalizeChargeSessionTracking(isCompletedNormally: !wasManualStop)
        }
    }

    private func beginChargeSessionTracking() {
        let startSoc = telemetry.displaySoc
        let initialPower = max(telemetry.chargePowerKw, 1.0)
        activeChargeTracker = ActiveChargeTracker(
            vin: selectedVehicle?.vin ?? session.selectedVin,
            vehicleName: currentVehicleName,
            carType: currentCarProfile.displayName,
            startTime: Date(),
            startSoc: startSoc,
            startRangeKm: telemetry.electricRangeKm,
            samples: [ChargeCurvePoint(elapsedMinutes: 0, powerKw: initialPower, soc: startSoc)],
            isSimulating: isDemoMode
        )

        chargeSimTask?.cancel()
        guard isDemoMode else { return }

        chargeSimTask = Task { [weak self] in
            var step = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, self.isDemoMode, self.telemetry.isCharging else { break }
                step += 1

                let limit = self.telemetry.healthyChargeEnabled
                    ? Double(min(self.telemetry.healthyChargeTargetSoc, 90))
                    : Double(self.telemetry.healthyChargeTargetSoc)

                let currentSoc = self.telemetry.displaySoc
                if currentSoc >= limit {
                    DemoVehicleFixtures.applySimulatedCommand(.stopCharging, to: &self.telemetry)
                    self.finalizeChargeSessionTracking(isCompletedNormally: true)
                    await self.syncChargeLiveActivity()
                    break
                }

                // 模拟快充功率随 SOC 变化：爬坡 -> 高平台 -> 80% 后逐步涓流降功
                let nextSoc = min(currentSoc + 0.9, limit)
                let simulatedPower: Double = {
                    if nextSoc < 80 {
                        return 51.5 + Double(step % 3) * 1.6
                    } else if nextSoc < 88 {
                        return max(28.0, 48.0 - (nextSoc - 80.0) * 2.2)
                    } else {
                        return max(14.5, 26.0 - (nextSoc - 88.0) * 1.4)
                    }
                }()
                let volts = max(self.telemetry.batteryVoltage, 386.0)
                self.telemetry.batteryCurrent = (simulatedPower * 1000.0) / volts
                self.telemetry.preciseSoc = nextSoc
                self.telemetry.soc = nextSoc.rounded()
                self.telemetry.electricRangeKm += 2.2
                self.telemetry.combinedRangeKm += 2.2
                self.telemetry.chargeRemainTimeMinutes = max(1, Int(ceil((limit - nextSoc) * 2.1)))
                self.telemetry.avgBatteryTemp = min(31.0, (self.telemetry.avgBatteryTemp ?? 24.5) + 0.2)

                let elapsed = Double(step) * 1.5
                self.activeChargeTracker?.samples.append(
                    ChargeCurvePoint(elapsedMinutes: elapsed, powerKw: simulatedPower, soc: nextSoc)
                )
                self.syncSharedSnapshot(lastAction: nil)
                await self.syncChargeLiveActivity()
            }
        }
    }

    private func appendRealChargeSampleIfTracking() {
        guard var tracker = activeChargeTracker else { return }
        let elapsedMin = max(Date().timeIntervalSince(tracker.startTime) / 60.0, Double(tracker.samples.count) * 0.5)
        tracker.samples.append(
            ChargeCurvePoint(elapsedMinutes: elapsedMin, powerKw: telemetry.chargePowerKw, soc: telemetry.displaySoc)
        )
        activeChargeTracker = tracker
    }

    private func finalizeChargeSessionTracking(isCompletedNormally: Bool) {
        chargeSimTask?.cancel()
        chargeSimTask = nil
        guard let tracker = activeChargeTracker else { return }
        activeChargeTracker = nil

        var finalPoints = tracker.samples
        var startTime = tracker.startTime
        let endTime = Date()
        var endSoc = telemetry.displaySoc
        var addedRange = max(0, telemetry.electricRangeKm - tracker.startRangeKm)
        var durationMinutes = max(1, Int(ceil(endTime.timeIntervalSince(startTime) / 60.0)))

        // 演示模式如果刚启动不久即手动结束（不足 4 个采样点），按本次实际起止构建直观流畅的演示充电曲线并回写一致增量
        if isDemoMode && finalPoints.count < 4 {
            let capSoc = telemetry.healthyChargeEnabled
                ? Double(min(telemetry.healthyChargeTargetSoc, 90))
                : Double(telemetry.healthyChargeTargetSoc)
            let targetDemoEnd = min(max(tracker.startSoc + 6.4, endSoc), capSoc)
            let socGain = max(0, targetDemoEnd - tracker.startSoc)
            endSoc = tracker.startSoc + socGain
            addedRange = max(addedRange, (socGain * 4.8).rounded())
            durationMinutes = max(durationMinutes, 16)
            startTime = endTime.addingTimeInterval(-TimeInterval(durationMinutes * 60))

            telemetry.preciseSoc = endSoc
            telemetry.soc = endSoc.rounded()
            telemetry.electricRangeKm = tracker.startRangeKm + addedRange
            telemetry.combinedRangeKm += addedRange

            let shape: [(Double, Double)] = [
                (0.0, 22.4),
                (2.5, 47.8),
                (5.0, 54.6),
                (8.0, 55.8),
                (11.0, 51.2),
                (13.5, 42.6),
                (Double(durationMinutes), 31.4)
            ]
            finalPoints = shape.map { elapsed, kw in
                let ratio = elapsed / Double(durationMinutes)
                return ChargeCurvePoint(
                    elapsedMinutes: elapsed,
                    powerKw: kw,
                    soc: tracker.startSoc + socGain * ratio
                )
            }
        } else {
            let elapsedMin = max(Date().timeIntervalSince(tracker.startTime) / 60.0, 0.5)
            let lastKw = max(finalPoints.last?.powerKw ?? 0, telemetry.chargePowerKw)
            if (finalPoints.last?.elapsedMinutes ?? 0) < elapsedMin {
                finalPoints.append(
                    ChargeCurvePoint(elapsedMinutes: elapsedMin, powerKw: lastKw, soc: endSoc)
                )
            }
        }

        let powers = finalPoints.map(\.powerKw)
        let peakPower = powers.max() ?? 0
        let avgPower = powers.isEmpty ? 0 : powers.reduce(0, +) / Double(powers.count)
        let estEnergyKwh = max((avgPower * Double(durationMinutes)) / 60.0, max(0, endSoc - tracker.startSoc) * 0.67)

        completedChargeSummary = ChargeSessionSummary(
            vehicleName: tracker.vehicleName,
            carType: tracker.carType,
            startTime: startTime,
            endTime: endTime,
            durationMinutes: durationMinutes,
            startSoc: tracker.startSoc,
            endSoc: endSoc,
            addedRangeKm: addedRange,
            peakPowerKw: peakPower,
            averagePowerKw: avgPower,
            addedEnergyKwh: estEnergyKwh,
            isCompletedNormally: isCompletedNormally,
            curvePoints: finalPoints
        )
    }

    #if canImport(ActivityKit) && os(iOS)
    private func makeLiveActivityState() -> ChargeActivityAttributes.ContentState {
        ChargeActivityAttributes.ContentState(
            soc: Int(telemetry.displaySoc.rounded()),
            targetSoc: telemetry.healthyChargeTargetSoc,
            rangeKm: Int(telemetry.electricRangeKm.rounded()),
            powerKw: telemetry.chargePowerKw,
            remainMinutes: telemetry.chargeRemainTimeMinutes,
            isCharging: telemetry.isCharging,
            acOn: telemetry.acOn,
            interiorTemp: telemetry.interiorTemp
        )
    }
    #endif

    // MARK: - 提示与倒计时辅助

    public func showToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toastMessage == msg {
                toastMessage = nil
            }
        }
    }

    private func startCountdown() {
        smsCountdownSeconds = 60
        Task {
            while smsCountdownSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if smsCountdownSeconds > 0 {
                    smsCountdownSeconds -= 1
                }
            }
        }
    }
}

private struct ActiveChargeTracker {
    let vin: String
    let vehicleName: String
    let carType: String
    let startTime: Date
    let startSoc: Double
    let startRangeKm: Double
    var samples: [ChargeCurvePoint]
    let isSimulating: Bool
}
