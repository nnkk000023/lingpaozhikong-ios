import Foundation

/// 零跑云端 + 网关全量 API 客户端（基于 `URLSession` `async/await`，精确复刻 `defpackage.GG`）
public final class LeapAPIClient: @unchecked Sendable {
    public enum Host {
        public static let legacyUser = "https://appuser.leapmotor.cn"
        public static let globalMaster = "https://app-gw-global-master.leapmotor.com"
        public static let appGateway = "https://appgateway.leapmotor.com"
        public static let iovApi = "https://iov-api.leapmotor.com"
        public static let amapRest = "https://restapi.amap.com"
    }

    private let urlSession: URLSession
    public let store: any SessionStoring
    public let tokenCoordinator: TokenCoordinator

    public init(
        store: any SessionStoring = InMemorySessionStore(),
        urlSession: URLSession = .shared
    ) {
        self.store = store
        self.urlSession = urlSession
        self.tokenCoordinator = TokenCoordinator(store: store)
    }

    // MARK: - 1. 登录与极验 / 原始凭据导入

    /// 发送短信验证码（`GET /app-user/applogin/compliance/sendmessagecode`）
    public func sendSMSCode(phone: String) async throws {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LeapAPIError.businessError(code: "-1", message: "手机号不能为空", endpoint: "sendmessagecode")
        }
        let state = await tokenCoordinator.currentState()
        let cipherPhone = try LeapCrypto.encryptPhoneRSA(trimmed)
        let headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: nil, withToken: false)
        let req = try buildURLRequest(
            baseURL: "\(Host.legacyUser)/app-user/applogin/compliance/sendmessagecode",
            method: "GET",
            query: ["phoneNo": cipherPhone],
            headers: headers
        )
        let json = try await performJSON(req, endpoint: "sendmessagecode")
        let code = responseCode(json)
        guard code == nil || code == "0" || code == "200" else {
            throw LeapAPIError.businessError(
                code: code ?? "-1",
                message: responseMessage(json, fallback: "发送验证码失败"),
                endpoint: "sendmessagecode"
            )
        }
    }

    /// 手机验证码登录（含可选极验回调），若服务端触发风控会抛出 `LeapAPIError.geetestChallengeRequired`
    public func loginWithPhone(
        phone: String,
        smsCode: String,
        smDeviceId: String? = nil,
        geetest: GeetestValidateResult? = nil
    ) async throws -> SessionState {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSMS = smsCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty, !trimmedSMS.isEmpty else {
            throw LeapAPIError.businessError(code: "-1", message: "手机号和验证码不能为空", endpoint: "check_login_with_phone")
        }

        let currentState = await tokenCoordinator.currentState()
        let effectiveSmId = (smDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (currentState.smDeviceId.isEmpty ? nil : currentState.smDeviceId)

        guard let effectiveSmId else {
            throw LeapAPIError.missingSmDeviceId
        }

        let cipherPhone = try LeapCrypto.encryptPhoneRSA(trimmedPhone)
        var query: [String: String] = [
            "phoneNoCiphertext": cipherPhone,
            "smsCode": trimmedSMS,
            "deviceID": currentState.deviceId,
            "smDeviceId": effectiveSmId,
            "os": "android",
            "pageUrl": ""
        ]
        if let geetest {
            guard geetest.isComplete else {
                throw LeapAPIError.businessError(code: "-1", message: "安全验证凭据不完整，请重试", endpoint: "check_login_with_phone")
            }
            query["captchaOutput"] = geetest.captchaOutput
            query["genTime"] = geetest.genTime
            query["lotNumber"] = geetest.lotNumber
            query["passToken"] = geetest.passToken
            query["requestId"] = geetest.requestId
            query["phone"] = trimmedPhone
        }

        let headers = LeapCrypto.buildBaseHeaders(deviceId: currentState.deviceId, oldToken: nil, withToken: false)
        let req = try buildURLRequest(
            baseURL: "\(Host.legacyUser)/app-user/applogin/check_login_with_phone",
            method: "POST",
            query: query,
            headers: headers,
            rawBody: Data()
        )
        let json = try await performJSON(req, endpoint: "check_login_with_phone")
        let dataObj = json["data"] as? [String: Any]
        let vo = (dataObj?["appLoginVO"] as? [String: Any])
            ?? (dataObj?["appOneLoginVO"] as? [String: Any])
            ?? findAuthObject(in: json)
        let code = responseCode(json)

        if let vo,
           let accountId = vo["accountId"] as? String, !accountId.isEmpty,
           let token = vo["token"] as? String, !token.isEmpty,
           (code == nil || code == "0" || code == "200") {
            let refreshToken = (vo["refreshToken"] as? String) ?? ""
            let expired = stringValue(vo["tokenExpired"]) ?? "21600"
            let old = OldSession(
                accountId: accountId,
                token: token,
                refreshToken: refreshToken,
                tokenExpiredSeconds: expired.isEmpty ? "21600" : expired
            )
            _ = await tokenCoordinator.updateState {
                $0.phone = trimmedPhone
                $0.smDeviceId = effectiveSmId
                $0.oldSession = old
            }
            return try await exchangeGatewaySession()
        }

        // 检查是否下发极验挑战
        let riskType = (dataObj?["risk_type"] as? String) ?? (json["risk_type"] as? String)
        if let riskType, !riskType.isEmpty {
            guard let requestId = (dataObj?["requestId"] as? String) ?? (json["requestId"] as? String),
                  !requestId.isEmpty else {
                throw LeapAPIError.businessError(code: code ?? "-1", message: "安全验证挑战缺少 requestId", endpoint: "check_login_with_phone")
            }
            let captchaId = GeetestChallenge.extractCaptchaId(from: riskType)
            throw LeapAPIError.geetestChallengeRequired(
                GeetestChallenge(
                    captchaId: captchaId,
                    riskType: riskType,
                    requestId: requestId,
                    phone: trimmedPhone,
                    smsCode: trimmedSMS
                )
            )
        }

        throw LeapAPIError.businessError(
            code: code ?? "-1",
            message: responseMessage(json, fallback: "登录响应缺少有效账号凭据"),
            endpoint: "check_login_with_phone"
        )
    }

    /// 原始 Auth 凭据导入登录（100% 绕过短信与数美风控，直接换取网关会话，对齐 `GG.T()`）
    public func loginWithRawAuth(rawText: String, phoneInput: String = "") async throws -> SessionState {
        let parsed = try RawAuthParser.parse(rawText: rawText, phoneInput: phoneInput)
        _ = await tokenCoordinator.updateState {
            if let did = parsed.deviceId, !did.isEmpty { $0.deviceId = did }
            if let sm = parsed.smDeviceId, !sm.isEmpty { $0.smDeviceId = sm }
            if let phone = parsed.phone, !phone.isEmpty { $0.phone = phone }
            $0.oldSession = OldSession(
                accountId: parsed.accountId,
                token: parsed.token,
                refreshToken: parsed.refreshToken,
                tokenExpiredSeconds: parsed.tokenExpiredSeconds
            )
        }
        return try await exchangeGatewaySession()
    }

    /// 用旧 `token` 换取网关 `accessToken` 与 XOR HMAC 密钥（对应 `GG.r()`）
    @discardableResult
    public func exchangeGatewaySession() async throws -> SessionState {
        let state = await tokenCoordinator.currentState()
        guard let old = state.oldSession else {
            throw LeapAPIError.notLoggedIn("未登录（缺少旧会话凭证）")
        }
        let bodyDict: [String: String] = [
            "identifier": old.accountId,
            "identifierType": "1",
            "security": old.token
        ]
        let headers = try LeapCrypto.buildGatewayHeaders(
            business: bodyDict,
            deviceId: state.deviceId,
            accountId: old.accountId,
            accessToken: nil,
            carvin: state.selectedVin,
            cartype: state.selectedCarType,
            hmacKey: nil,
            useHmac: false
        )
        let req = try buildURLRequest(
            baseURL: "\(Host.globalMaster)/base/base-user/account/v1/login",
            method: "POST",
            headers: headers,
            jsonBody: bodyDict
        )
        let json = try await performJSON(req, endpoint: "gateway/login")
        let dataObj = (json["data"] as? [String: Any]) ?? json
        let derived = try LeapCrypto.deriveGatewaySession(from: dataObj, fallbackAccountId: old.accountId)
        return await tokenCoordinator.updateState {
            if let extractedId = derived.extractedDeviceId, !extractedId.isEmpty {
                $0.deviceId = extractedId
            }
            $0.gatewaySession = derived.session
        }
    }

    // MARK: - 2. 车辆列表、路由与实时车况

    /// 拉取绑定车辆列表与能力模型（对应 `GG.S()`）
    public func fetchVehicleList() async throws -> [Vehicle] {
        let json = try await requestGateway(
            url: "\(Host.globalMaster)/app/app-global-service/v1/vehicle/list",
            method: "GET",
            endpoint: "vehicle/list"
        )
        var rawObjects: [[String: Any]] = []
        collectVehicleObjects(from: json, into: &rawObjects)

        var seenVIN = Set<String>()
        var vehicles: [Vehicle] = []
        for obj in rawObjects {
            let vin = (obj["vin"] as? String) ?? ""
            guard !vin.isEmpty, seenVIN.insert(vin).inserted else { continue }

            let modelParam = obj["modelParam"] as? [String: Any]
            let carType = nonEmpty(obj["carType"] as? String)
                ?? nonEmpty(obj["cartype"] as? String)
                ?? nonEmpty(modelParam?["carType"] as? String)
                ?? nonEmpty(obj["model"] as? String)
                ?? "C16"

            let rights = stringArray(obj["rightList"])
            let abilitiesRaw = obj["abilities"] ?? obj["ability"]
            let abilities = stringArray(abilitiesRaw)

            let isReev = carType.localizedCaseInsensitiveContains("REEV")
                || carType.contains("增程")
                || rights.contains("380")

            let vehicleName = nonEmpty(obj["vehicleName"] as? String)
                ?? nonEmpty(obj["carName"] as? String)
                ?? nonEmpty(obj["licensePlate"] as? String)
                ?? nonEmpty(obj["nickName"] as? String)
                ?? nonEmpty(obj["nickname"] as? String)
                ?? carType

            let year = nonEmpty(stringValue(obj["year"]))
                ?? nonEmpty(stringValue(modelParam?["year"]))
                ?? nonEmpty(stringValue(obj["modelYear"]))
                ?? nonEmpty(stringValue(obj["modelyear"]))
                ?? ""

            let outColor = nonEmpty(obj["outColor"] as? String)
                ?? nonEmpty(obj["color"] as? String)
                ?? "liquid_silver"

            let isShared = (obj["isShare"] as? Bool == true)
                || (obj["isShared"] as? Bool == true)
                || (stringValue(obj["bindType"]) == "2")
                || (stringValue(obj["userType"]) == "2")
                || (stringValue(obj["shareType"]) == "1")
                || ((obj["isMaster"] as? NSNumber)?.intValue == 0)

            let hvac = parseHvacCapability(obj["funcConfig"] as? [String: Any])
            vehicles.append(
                Vehicle(
                    vin: vin,
                    carType: carType,
                    hvacCapability: hvac,
                    vehicleName: vehicleName,
                    year: year,
                    outColor: outColor,
                    powertrain: isReev ? .reev : .bev,
                    isShared: isShared,
                    rightList: rights,
                    abilities: abilities
                )
            )
        }

        if let first = vehicles.first {
            _ = await tokenCoordinator.updateState { state in
                if state.selectedVin.isEmpty {
                    state.selectedVin = first.vin
                }
                if let matched = vehicles.first(where: { $0.vin == state.selectedVin }) {
                    state.selectedCarType = matched.carType
                    state.selectedNickname = matched.vehicleName
                    state.selectedYear = matched.year
                    state.selectedPaintId = matched.outColor
                    state.hvacCapability = matched.hvacCapability
                }
            }
        }
        return vehicles
    }

    /// 获取车辆区域动态路由 `appRegion` 与 `appCenter`（对应 `GG.x()`）
    public func fetchCarRoute(vin: String? = nil) async throws -> CarRoute {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }

        let json = try await requestGateway(
            url: "\(Host.globalMaster)/app/app-global-service/v1/vehicle/getCarRoute",
            method: "GET",
            business: ["vin": targetVIN],
            query: ["vin": targetVIN],
            endpoint: "vehicle/getCarRoute"
        )
        let target = (json["data"] as? [String: Any]) ?? findDictWithKey("appRegion", in: json)
        guard let target, let appRegion = nonEmpty(target["appRegion"] as? String) else {
            throw LeapAPIError.missingResponseData("车辆路由响应缺少 appRegion")
        }
        let appCenter = nonEmpty(target["appCenter"] as? String) ?? Host.appGateway
        let route = CarRoute(appRegion: appRegion, appCenter: appCenter)
        _ = await tokenCoordinator.updateState { $0.carRoute = route }
        return route
    }

    /// 查询实时全车遥测车况（对应 `GG.M()`）
    public func fetchTelemetry(vin: String? = nil) async throws -> VehicleTelemetry {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let json = try await requestGateway(
            url: "\(route.appRegion)/app/app-signal-service/signal/info/query",
            method: "POST",
            business: ["vin": targetVIN],
            jsonBody: ["vin": targetVIN],
            endpoint: "signal/info/query"
        )
        let dataObj = json["data"] as? [String: Any]
        let signalMap = (dataObj?["signalMap"] as? [String: Any])
            ?? (json["signalMap"] as? [String: Any])
            ?? findDictWithKey("1204", in: json)
            ?? [:]
        guard !signalMap.isEmpty else {
            throw LeapAPIError.missingResponseData("车况接口未返回 signalMap")
        }
        let configObj = (dataObj?["config"] as? [String: Any]) ?? (json["config"] as? [String: Any])
        let chargeConfig = configObj?["3"] as? [String: Any]
        return VehicleTelemetry.decode(signalMap: signalMap, chargeConfig: chargeConfig)
    }

    // MARK: - 3. 远程控车与状态轮询

    /// 发送远程控车指令，返回 `msgID`（对应 `GG.k0()`）
    public func sendRemoteControl(command: ControlCommand, opPassword: String, vin: String? = nil) async throws -> String {
        let trimmedPwd = opPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPwd.isEmpty else {
            throw LeapAPIError.businessError(code: "-1", message: "操作密码不能为空", endpoint: "appremotectl")
        }
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }

        let payload = try command.buildPayload()
        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let encryptToken = gw.accessToken.isEmpty ? (state.oldSession?.token ?? "") : gw.accessToken
        let encryptedPwd = try LeapCrypto.encryptOpPassword(trimmedPwd, token: encryptToken)

        guard let old = state.oldSession else {
            throw LeapAPIError.notLoggedIn("未登录（缺少旧会话凭证）")
        }
        let signedForm = LeapCrypto.signLegacyParams(
            business: [
                "cmdid": payload.cmdid,
                "state": payload.stateJSON,
                "carvin": targetVIN,
                "oppwd": encryptedPwd
            ],
            deviceID: state.deviceId,
            tokenOrRefreshToken: old.token
        )

        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        let gwHeaders = try buildGatewaySignHeaders(business: signedForm, state: state, gw: gw)
        headers.merge(gwHeaders) { _, new in new }

        let hosts = Array(NSOrderedSet(array: ["\(route.appRegion)/app/app-control-service/v3/api/appremotectl",
                                               "\(Host.globalMaster)/app/app-control-service/v3/api/appremotectl"]))
            .compactMap { $0 as? String }

        var lastError: Error?
        for url in hosts {
            do {
                let req = try buildURLRequest(baseURL: url, method: "POST", headers: headers, formBody: signedForm)
                let json = try await performJSON(req, endpoint: "appremotectl")
                let code = responseCode(json)
                if code == nil || code == "0" || code == "200" {
                    return extractMsgID(json)
                }
                throw LeapAPIError.businessError(
                    code: code ?? "-1",
                    message: responseMessage(json, fallback: "控车指令下发失败"),
                    endpoint: "appremotectl"
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LeapAPIError.missingResponseData("控车请求发送失败")
    }

    /// 轮询远程控车指令执行结果（对应 `GG.a0()`）
    public func queryRemoteControlResult(msgID: String, vin: String? = nil) async throws -> [String: Any] {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let signedQuery = LeapCrypto.signLegacyParams(
            business: ["msgID": msgID],
            deviceID: state.deviceId,
            tokenOrRefreshToken: old.token
        )

        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(try buildGatewaySignHeaders(business: signedQuery, state: state, gw: gw)) { _, new in new }

        let urls = ["\(route.appRegion)/app/app-control-service/v3/api/appremotectl/query",
                    "\(Host.globalMaster)/app/app-control-service/v3/api/appremotectl/query"]
        var lastError: Error?
        for url in urls {
            do {
                let req = try buildURLRequest(baseURL: url, method: "GET", query: signedQuery, headers: headers)
                return try await performJSON(req, endpoint: "appremotectl/query")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LeapAPIError.missingResponseData("控车结果查询失败")
    }

    // MARK: - 4. 健康充电、预约充电、定时空调与电池预热

    /// 设置健康充电上限与开关（对应 `GG.l0()`）
    public func setHealthyCharging(enabled: Bool, targetSoc: Int, vin: String? = nil) async throws {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        // 健康充电开启时，上限协议硬性钳位最高为 90%；关闭时才可放开至 100%
        let maxTarget = enabled ? 90 : 100
        let clamped = min(max(targetSoc, 50), maxTarget)
        let params: [String: String] = [
            "carvin": targetVIN,
            "vin": targetVIN,
            "state": enabled ? "1" : "0",
            "soc": String(clamped),
            "targetSoc": String(clamped)
        ]
        _ = try await requestGateway(
            url: "\(route.appRegion)/carownerservice/v3/api/healthyCharging/control",
            method: "POST",
            business: params,
            query: params,
            jsonBody: params,
            endpoint: "healthyCharging/control"
        )
    }

    /// 设置预约充电（`cmdid="190"`，对应 `GG.o0()`）
    public func setChargeSchedule(
        enabled: Bool,
        startTime: String,
        endTime: String,
        targetSoc: Int,
        opPassword: String,
        circulation: Int = 1,
        cycles: String = "1,2,3,4,5,6,7",
        recharge: Bool = false
    ) async throws {
        let state = await tokenCoordinator.currentState()
        let targetVIN = state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let clampedSoc = min(max(targetSoc, 50), 100)
        let stateDict: [String: Any] = [
            "chargeEnable": enabled ? 1 : 0,
            "chargesoc": clampedSoc,
            "circulation": enabled ? circulation : 0,
            "cycles": circulation == 1 ? cycles : "",
            "starttime": startTime,
            "endtime": endTime,
            "recharge": recharge ? 1 : 0
        ]
        let stateData = try JSONSerialization.data(withJSONObject: stateDict, options: [.sortedKeys])
        let stateStr = String(data: stateData, encoding: .utf8) ?? "{}"

        var biz: [String: String] = [
            "cmdid": "190",
            "state": stateStr,
            "carvin": targetVIN
        ]
        if !opPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encToken = gw.accessToken.isEmpty ? old.token : gw.accessToken
            biz["oppwd"] = try LeapCrypto.encryptOpPassword(opPassword, token: encToken)
        }
        let signed = LeapCrypto.signLegacyParams(business: biz, deviceID: state.deviceId, tokenOrRefreshToken: old.token)
        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(try buildGatewaySignHeaders(business: signed, state: state, gw: gw)) { _, new in new }

        let urls = [
            "\(route.appRegion)/app/app-control-service/v3/api/appremotectl",
            "\(route.appCenter)/carownerservice/v3/api/appremotectl/appointment"
        ]
        var lastError: Error?
        for url in urls {
            do {
                let req = try buildURLRequest(baseURL: url, method: "POST", headers: headers, formBody: signed)
                let json = try await performJSON(req, endpoint: "charge/schedule")
                let code = responseCode(json)
                if code == nil || code == "0" || code == "200" {
                    return
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }

    /// 设置定时空调预约（`cmdid="171"`，对应 `GG.m0()`）
    public func setScheduledAc(config: ScheduledAcConfig, opPassword: String) async throws {
        let state = await tokenCoordinator.currentState()
        let targetVIN = state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let stateStr: String
        if config.enabled {
            let clampedTemp = min(max(config.temperature, 16), 32)
            let clampedWind = min(max(config.windLevel, 1), 9)
            let mode = clampedTemp >= 27 ? "hot" : "cold"
            let dayList = config.weekdays.map { $0 == 7 ? 0 : $0 }.sorted()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let datePrefix = df.string(from: Date())
            let startTime = config.startTimeHHMM.count == 5 ? "\(datePrefix) \(config.startTimeHHMM):00" : config.startTimeHHMM
            let controlObj: [String: Any] = [
                "on": "1",
                "set_id": "android_\(state.deviceId)\(nowMs)00",
                "start_time": startTime,
                "update_time": String(nowMs),
                "days": dayList,
                "operate": "manual",
                "mode": mode,
                "temperature": String(clampedTemp),
                "windlevel": String(clampedWind),
                "circle": config.circleIn ? "in" : "out",
                "wshld": config.windshieldDefrost ? "1" : "0",
                "position": "all"
            ]
            let data = try JSONSerialization.data(withJSONObject: ["controls": [controlObj]])
            stateStr = String(data: data, encoding: .utf8) ?? "{\"controls\":[]}"
        } else {
            stateStr = "{\"controls\":[]}"
        }

        var biz: [String: String] = ["cmdid": "171", "state": stateStr, "carvin": targetVIN]
        if !opPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            biz["oppwd"] = try LeapCrypto.encryptOpPassword(opPassword, token: gw.accessToken.isEmpty ? old.token : gw.accessToken)
        }
        let signed = LeapCrypto.signLegacyParams(business: biz, deviceID: state.deviceId, tokenOrRefreshToken: old.token)
        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(try buildGatewaySignHeaders(business: signed, state: state, gw: gw)) { _, new in new }

        let targetHost = route.appCenter.isEmpty ? route.appRegion : route.appCenter
        let req = try buildURLRequest(
            baseURL: "\(targetHost)/carownerservice/v3/api/appremotectl/appointment",
            method: "POST",
            headers: headers,
            formBody: signed
        )
        _ = try await performJSON(req, endpoint: "ac/appointment")
    }

    /// 设置电池定时预热（`cmdid="161"`，对应 `GG.n0()`）
    public func setScheduledBatteryPreheat(config: ScheduledBatteryPreheatConfig, opPassword: String) async throws {
        let state = await tokenCoordinator.currentState()
        let targetVIN = state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let stateStr: String
        if config.enabled {
            let dayList = (config.weekdays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : config.weekdays)
                .map { $0 == 7 ? 0 : $0 }.sorted()
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let startTime = config.startTimeHHMM.count == 5 ? "\(df.string(from: Date())) \(config.startTimeHHMM):00" : config.startTimeHHMM
            let obj: [String: Any] = [
                "on": "1",
                "set_id": "ptc_set_\(nowMs)",
                "start_time": startTime,
                "update_time": String(nowMs),
                "days": dayList
            ]
            let data = try JSONSerialization.data(withJSONObject: ["controls": [obj]])
            stateStr = String(data: data, encoding: .utf8) ?? "{\"controls\":[]}"
        } else {
            stateStr = "{\"controls\":[]}"
        }

        var biz: [String: String] = ["cmdid": "161", "state": stateStr, "carvin": targetVIN]
        if !opPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            biz["oppwd"] = try LeapCrypto.encryptOpPassword(opPassword, token: gw.accessToken.isEmpty ? old.token : gw.accessToken)
        }
        let signed = LeapCrypto.signLegacyParams(business: biz, deviceID: state.deviceId, tokenOrRefreshToken: old.token)
        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(try buildGatewaySignHeaders(business: signed, state: state, gw: gw)) { _, new in new }

        let req = try buildURLRequest(
            baseURL: "\(route.appRegion)/app/app-control-service/v3/api/appremotectl",
            method: "POST",
            headers: headers,
            formBody: signed
        )
        _ = try await performJSON(req, endpoint: "preheat/schedule")
    }

    // MARK: - 5. 行程能耗与底盘拍照

    /// 查询近 7 天里程与能耗明细（对应 `GG.G()`）
    public func fetchRecent7DaysEnergy(vin: String? = nil) async throws -> [DailyDrivingMetric] {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sevenDaysAgo = Calendar.current.startOfDay(for: Date().addingTimeInterval(-7 * 86400))
        let beginMs = Int64(sevenDaysAgo.timeIntervalSince1970 * 1000)

        let json = try await requestLegacyWithAutoRenew(
            url: "\(Host.appGateway)/carownerservice/v3/api/drivingrecord/mileage/energy/detail",
            business: [
                "begintime": String(beginMs),
                "endtime": String(nowMs),
                "vin": targetVIN
            ],
            includeTimestamp: false,
            endpoint: "drivingrecord/detail"
        )
        let list = ((json["data"] as? [String: Any])?["list"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []
        return list.enumerated().map { idx, item in
            let date = (item["date"] as? String) ?? (item["day"] as? String) ?? "Day \(idx + 1)"
            let mileage = doubleValue(item["mileage"]) ?? doubleValue(item["totalMileage"]) ?? 0
            let energy = doubleValue(item["energy"]) ?? doubleValue(item["powerConsume"]) ?? 0
            return DailyDrivingMetric(dateLabel: date, mileageKm: mileage, energyKwh: energy)
        }
    }

    /// 查询底盘停车拍照图片 URL（对应 `GG.y()`）
    public func fetchChassisPhoto(vin: String? = nil) async throws -> ChassisPhotoInfo? {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }

        let route = try? await ensureRoute(for: targetVIN, cached: state.carRoute)
        let gw = try await freshGatewaySession()
        let signed = LeapCrypto.signLegacyParams(business: ["vin": targetVIN], deviceID: state.deviceId, tokenOrRefreshToken: old.token)
        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(try buildGatewaySignHeaders(business: signed, state: state, gw: gw)) { _, new in new }

        var hosts = [Host.iovApi, Host.globalMaster]
        if let reg = route?.appRegion, !reg.isEmpty { hosts.append(reg) }
        for host in hosts {
            if let req = try? buildURLRequest(baseURL: "\(host)/carownerservice/v3/api/chassis/query", method: "GET", query: signed, headers: headers),
               let json = try? await performJSON(req, endpoint: "chassis/query"),
               let data = json["data"] as? [String: Any],
               let fileURL = nonEmpty(data["fileUrl"] as? String) {
                let ts = (data["uploadTime"] as? NSNumber)?.int64Value ?? 0
                return ChassisPhotoInfo(fileURL: fileURL, uploadTimeMs: ts)
            }
        }
        return nil
    }

    // MARK: - 6. 蓝牙钥匙证书同步与记录上报

    /// 同步云端蓝牙钥匙证书（`POST {appCenter}/carownerservice/v3/api/bluetoothkey/combine/syncBluetoothKeys`）
    public func syncBluetoothKeyCertificate(vin: String? = nil) async throws -> BleKeyCertificate {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty else { throw LeapAPIError.noVehicleSelected }
        guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录（请先登录后同步蓝牙钥匙）") }

        let route = try await ensureRoute(for: targetVIN, cached: state.carRoute)
        let signedForm = LeapCrypto.signLegacyParams(business: ["vin": targetVIN], deviceID: state.deviceId, tokenOrRefreshToken: old.token)
        let headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)

        let req = try buildURLRequest(
            baseURL: "\(route.appCenter)/carownerservice/v3/api/bluetoothkey/combine/syncBluetoothKeys",
            method: "POST",
            headers: headers,
            formBody: signedForm
        )
        let json = try await performJSON(req, endpoint: "syncBluetoothKeys")
        let dataObj = (json["data"] as? [String: Any]) ?? json
        let keyObj = (dataObj["bluetoothKey"] as? [String: Any]) ?? dataObj

        guard let ecdhPub = nonEmpty(keyObj["ecdhPublicKey"] as? String),
              let passwordCard = nonEmpty(keyObj["passwordCard"] as? String),
              let plainText = nonEmpty(keyObj["plainText"] as? String),
              let signResult = nonEmpty(keyObj["signResult"] as? String) else {
            throw LeapAPIError.missingResponseData("云端蓝牙钥匙响应缺少关键证书字段")
        }
        let keyTypeRaw = (keyObj["keyType"] as? NSNumber)?.intValue
            ?? Int((keyObj["keyType"] as? String) ?? "0")
            ?? 0
        return BleKeyCertificate(
            vin: targetVIN,
            ecdhPublicKey: ecdhPub,
            keyType: BLEKeyType(rawValue: keyTypeRaw) ?? .p256AES,
            passwordCard: passwordCard,
            plainText: plainText,
            signResult: signResult
        )
    }

    /// 上报蓝牙解闭锁记录（对应 `GG.q0()`）
    public func uploadBluetoothRecord(isLock: Bool, vin: String? = nil) async {
        let state = await tokenCoordinator.currentState()
        let targetVIN = vin ?? state.selectedVin
        guard !targetVIN.isEmpty, let old = state.oldSession else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let recordPayload: [String: Any] = [
            "devType": "Android",
            "list": [[
                "optDesc": isLock ? "0" : "1",
                "optResult": "0",
                "optTime": String(nowMs),
                "optType": "1",
                "sendType": "4",
                "vin": targetVIN
            ]]
        ]
        guard let recordData = try? JSONSerialization.data(withJSONObject: recordPayload),
              let recordStr = String(data: recordData, encoding: .utf8) else { return }

        let signed = LeapCrypto.signLegacyParams(
            business: ["records": recordStr],
            deviceID: state.deviceId,
            tokenOrRefreshToken: old.token
        )
        guard let gw = try? await freshGatewaySession(),
              let gwHeaders = try? buildGatewaySignHeaders(business: signed, state: state, gw: gw) else { return }

        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers.merge(gwHeaders) { _, new in new }
        guard let req = try? buildURLRequest(
            baseURL: "\(Host.appGateway)/carownerservice/v3/api/bluetoothkey/uploadRecords",
            method: "POST",
            headers: headers,
            formBody: signed
        ) else { return }
        _ = try? await urlSession.data(for: req)
    }

    // MARK: - 7. 高德位置与天气查询

    public func fetchLocationAndWeather(latitude: Double, longitude: Double, amapKey: String) async throws -> VehicleLocationWeather {
        let keyTrimmed = amapKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyTrimmed.isEmpty else {
            return VehicleLocationWeather(formattedAddress: String(format: "%.4f, %.4f", latitude, longitude))
        }

        let regeoReq = try buildURLRequest(
            baseURL: "\(Host.amapRest)/v3/geocode/regeo",
            method: "GET",
            query: [
                "key": keyTrimmed,
                "location": String(format: "%.6f,%.6f", longitude, latitude),
                "extensions": "base"
            ]
        )
        let regeoJSON = try await performJSON(regeoReq, endpoint: "amap/regeo")
        let regeocode = regeoJSON["regeocode"] as? [String: Any]
        let addrComp = regeocode?["addressComponent"] as? [String: Any]
        let formatted = nonEmpty(regeocode?["formatted_address"] as? String) ?? String(format: "%.4f, %.4f", latitude, longitude)
        let adcode = nonEmpty(addrComp?["adcode"] as? String) ?? ""
        let city = nonEmpty(addrComp?["city"] as? String) ?? nonEmpty(addrComp?["province"] as? String) ?? ""

        guard !adcode.isEmpty else {
            return VehicleLocationWeather(formattedAddress: formatted, adcode: adcode, cityName: city)
        }

        let weatherReq = try buildURLRequest(
            baseURL: "\(Host.amapRest)/v3/weather/weatherInfo",
            method: "GET",
            query: [
                "key": keyTrimmed,
                "city": adcode,
                "extensions": "base"
            ]
        )
        if let weatherJSON = try? await performJSON(weatherReq, endpoint: "amap/weatherInfo"),
           let lives = weatherJSON["lives"] as? [[String: Any]],
           let first = lives.first {
            return VehicleLocationWeather(
                formattedAddress: formatted,
                adcode: adcode,
                cityName: (first["city"] as? String) ?? city,
                weatherText: (first["weather"] as? String) ?? "",
                temperatureCelsius: (first["temperature"] as? String) ?? "",
                windDirection: (first["winddirection"] as? String) ?? "",
                windPower: (first["windpower"] as? String) ?? ""
            )
        }
        return VehicleLocationWeather(formattedAddress: formatted, adcode: adcode, cityName: city)
    }

    // MARK: - 内部请求管线与自动续期

    private func freshGatewaySession(force: Bool = false) async throws -> GatewaySession {
        try await tokenCoordinator.ensureFreshGateway(
            force: force,
            refreshGateway: { [weak self] gw, state in
                guard let self else { throw LeapAPIError.notLoggedIn("客户端已释放") }
                return try await self.performGatewayRefresh(gw: gw, state: state)
            },
            refreshLegacy: { [weak self] old, state in
                guard let self else { throw LeapAPIError.notLoggedIn("客户端已释放") }
                return try await self.performLegacyRefreshAndRelogin(old: old, state: state)
            }
        )
    }

    private func ensureRoute(for vin: String, cached: CarRoute?) async throws -> CarRoute {
        if let cached, !cached.appRegion.isEmpty {
            return cached
        }
        return try await fetchCarRoute(vin: vin)
    }

    private func requestGateway(
        url: String,
        method: String,
        business: [String: String] = [:],
        query: [String: String]? = nil,
        jsonBody: [String: Any]? = nil,
        endpoint: String
    ) async throws -> [String: Any] {
        for attempt in 0..<2 {
            let gw = try await freshGatewaySession(force: attempt > 0)
            let state = await tokenCoordinator.currentState()
            let headers = try buildGatewaySignHeaders(business: business, state: state, gw: gw)
            let finalQuery = query ?? (method == "GET" ? business : nil)
            let req = try buildURLRequest(
                baseURL: url,
                method: method,
                query: finalQuery,
                headers: headers,
                jsonBody: jsonBody
            )
            let json = try await performJSON(req, endpoint: endpoint)
            if attempt == 0 && LeapAPIError.isGatewayTokenExpiredJSON(json) {
                continue
            }
            return json
        }
        throw LeapAPIError.gatewayTokenExpired("网关鉴权重试失败")
    }

    private func requestLegacyWithAutoRenew(
        url: String,
        business: [String: String],
        includeTimestamp: Bool,
        endpoint: String
    ) async throws -> [String: Any] {
        for attempt in 0..<2 {
            if attempt > 0 {
                _ = try await tokenCoordinator.ensureFreshLegacy(force: true) { [weak self] old, state in
                    guard let self else { throw LeapAPIError.notLoggedIn("客户端已释放") }
                    return try await self.performLegacyRefreshAndRelogin(old: old, state: state)
                }
            }
            let state = await tokenCoordinator.currentState()
            guard let old = state.oldSession else { throw LeapAPIError.notLoggedIn("未登录") }
            let gw = try await freshGatewaySession()
            let signedQuery = LeapCrypto.signLegacyParams(
                business: business,
                deviceID: state.deviceId,
                tokenOrRefreshToken: old.token,
                includeTimestamp: includeTimestamp
            )
            var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
            headers.merge(try buildGatewaySignHeaders(business: signedQuery, state: state, gw: gw)) { _, new in new }
            let req = try buildURLRequest(baseURL: url, method: "GET", query: signedQuery, headers: headers)
            let json = try await performJSON(req, endpoint: endpoint)
            if attempt == 0 && LeapAPIError.isLegacyTokenExpiredJSON(json) {
                continue
            }
            return json
        }
        throw LeapAPIError.legacyTokenExpired("旧 Token 续期失败")
    }

    private func performGatewayRefresh(gw: GatewaySession, state: SessionState) async throws -> GatewaySession {
        let headers = try buildGatewaySignHeaders(business: ["refreshToken": gw.refreshToken], state: state, gw: gw)
        let req = try buildURLRequest(
            baseURL: "\(Host.globalMaster)/base/base-user/token/v1/refresh",
            method: "POST",
            headers: headers,
            jsonBody: ["refreshToken": gw.refreshToken]
        )
        let json = try await performJSON(req, endpoint: "gateway/refresh")
        let dataObj = (json["data"] as? [String: Any]) ?? json
        let derived = try LeapCrypto.deriveGatewaySession(from: dataObj, fallbackAccountId: gw.accountId)
        return derived.session
    }

    private func performLegacyRefreshAndRelogin(old: OldSession, state: SessionState) async throws -> SessionState {
        guard !state.phone.isEmpty else {
            throw LeapAPIError.missingPhoneForRenewal
        }
        let cipherPhone = try LeapCrypto.encryptPhoneRSA(state.phone)
        let signed = LeapCrypto.signLegacyParams(
            business: [
                "accountId": old.accountId,
                "accountNumber": cipherPhone
            ],
            deviceID: state.deviceId,
            tokenOrRefreshToken: old.refreshToken,
            isRefresh: true
        )
        var headers = LeapCrypto.buildBaseHeaders(deviceId: state.deviceId, oldToken: old.token, withToken: true)
        headers["XFX-CDN-CROSS-REFRESH-NODE"] = old.refreshToken
        let req = try buildURLRequest(
            baseURL: "\(Host.legacyUser)/app-user/appuseroperate/getnewtoken",
            method: "GET",
            query: signed,
            headers: headers
        )
        let json = try await performJSON(req, endpoint: "getnewtoken")
        let dataObj = (json["data"] as? [String: Any]) ?? json
        guard let newToken = nonEmpty(dataObj["token"] as? String) else {
            throw LeapAPIError.legacyTokenExpired("旧 Token 续期失败：服务端未返回新 Token")
        }
        let newRefresh = nonEmpty(dataObj["refreshToken"] as? String) ?? old.refreshToken
        let newExp = stringValue(dataObj["tokenExpired"]) ?? "21600"
        let updatedOld = OldSession(
            accountId: old.accountId,
            token: newToken,
            refreshToken: newRefresh,
            tokenExpiredSeconds: newExp
        )
        _ = await tokenCoordinator.updateState { $0.oldSession = updatedOld }
        return try await exchangeGatewaySession()
    }

    private func buildGatewaySignHeaders(
        business: [String: String],
        state: SessionState,
        gw: GatewaySession
    ) throws -> [String: String] {
        var nullableBiz: [String: String?] = [:]
        for (k, v) in business { nullableBiz[k] = v }
        return try LeapCrypto.buildGatewayHeaders(
            business: nullableBiz,
            deviceId: state.deviceId,
            accountId: gw.accountId,
            accessToken: gw.accessToken,
            carvin: state.selectedVin,
            cartype: state.selectedCarType,
            hmacKey: gw.hmacKeyData,
            useHmac: true
        )
    }

    private func buildURLRequest(
        baseURL: String,
        method: String,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        jsonBody: [String: Any]? = nil,
        formBody: [String: String]? = nil,
        rawBody: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw LeapAPIError.businessError(code: "-1", message: "无效 URL: \(baseURL)", endpoint: baseURL)
        }
        if let query, !query.isEmpty {
            var items = components.queryItems ?? []
            for key in query.keys.sorted() {
                if let val = query[key] {
                    items.append(URLQueryItem(name: key, value: val))
                }
            }
            components.queryItems = items
        }
        guard let finalURL = components.url else {
            throw LeapAPIError.businessError(code: "-1", message: "无法构造请求 URL", endpoint: baseURL)
        }
        var request = URLRequest(url: finalURL, timeoutInterval: 20)
        request.httpMethod = method
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else if let formBody {
            let encoded = formBody.keys.sorted().compactMap { key -> String? in
                guard let val = formBody[key] else { return nil }
                return "\(formEscape(key))=\(formEscape(val))"
            }.joined(separator: "&")
            request.httpBody = Data(encoded.utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else if let rawBody {
            request.httpBody = rawBody
        }
        return request
    }

    private func performJSON(_ request: URLRequest, endpoint: String) async throws -> [String: Any] {
        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(statusCode) else {
            throw LeapAPIError.httpError(statusCode: statusCode, message: String(text.prefix(200)), endpoint: endpoint)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LeapAPIError.invalidJSON(endpoint: endpoint, preview: String(text.prefix(200)))
        }
        return obj
    }

    // MARK: - 辅助工具函数

    private func formEscape(_ str: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return str.addingPercentEncoding(withAllowedCharacters: allowed) ?? str
    }

    private func responseCode(_ json: [String: Any]) -> String? {
        stringValue(json["result"]) ?? stringValue(json["code"])
    }

    private func responseMessage(_ json: [String: Any], fallback: String) -> String {
        nonEmpty(json["msg"] as? String) ?? nonEmpty(json["message"] as? String) ?? fallback
    }

    private func extractMsgID(_ json: [String: Any]) -> String {
        if let dict = findDictWithKey("msgID", in: json) ?? findDictWithKey("msgId", in: json) ?? findDictWithKey("eventId", in: json) {
            if let s = nonEmpty(stringValue(dict["msgID"])) { return s }
            if let s = nonEmpty(stringValue(dict["msgId"])) { return s }
            if let s = nonEmpty(stringValue(dict["eventId"])) { return s }
        }
        if let primitive = stringValue(json["data"]) {
            return primitive
        }
        return ""
    }

    private func collectVehicleObjects(from object: Any, into list: inout [[String: Any]]) {
        if let dict = object as? [String: Any] {
            if let vin = dict["vin"] as? String, !vin.isEmpty {
                list.append(dict)
            }
            for val in dict.values {
                collectVehicleObjects(from: val, into: &list)
            }
        } else if let arr = object as? [Any] {
            for item in arr {
                collectVehicleObjects(from: item, into: &list)
            }
        }
    }

    private func findAuthObject(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if nonEmpty(dict["accountId"] as? String) != nil && nonEmpty(dict["token"] as? String) != nil {
                return dict
            }
            for v in dict.values {
                if let found = findAuthObject(in: v) { return found }
            }
        } else if let arr = object as? [Any] {
            for item in arr {
                if let found = findAuthObject(in: item) { return found }
            }
        }
        return nil
    }

    private func findDictWithKey(_ key: String, in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if dict[key] != nil { return dict }
            for v in dict.values {
                if let found = findDictWithKey(key, in: v) { return found }
            }
        } else if let arr = object as? [Any] {
            for item in arr {
                if let found = findDictWithKey(key, in: item) { return found }
            }
        }
        return nil
    }

    private func parseHvacCapability(_ funcConfig: [String: Any]?) -> HvacCapability {
        guard let hvac = (funcConfig?["HVAC"] as? [String: Any]) ?? (funcConfig?["hvac"] as? [String: Any]) else {
            return .default
        }
        let tempObj = hvac["temperature"] as? [String: Any]
        let fanObj = hvac["fan"] as? [String: Any]
        let tMin = (tempObj?["min"] as? NSNumber)?.intValue
        let tMax = (tempObj?["max"] as? NSNumber)?.intValue
        let fMin = (fanObj?["min"] as? NSNumber)?.intValue
        let fMax = (fanObj?["max"] as? NSNumber)?.intValue

        let validTemp = (tMin != nil && tMax != nil && tMin! >= 10 && tMax! <= 40 && tMax! >= tMin!)
        let validFan = (fMin != nil && fMax != nil && fMin! >= 0 && fMax! >= fMin!)
        return HvacCapability(
            minTemp: validTemp ? tMin! : 19,
            maxTemp: validTemp ? tMax! : 32,
            minFan: validFan ? fMin : 1,
            maxFan: validFan ? fMax : 9
        )
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let arr = value as? [Any] {
            return arr.compactMap { stringValue($0) }
        }
        if let str = value as? String {
            return str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    private func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
