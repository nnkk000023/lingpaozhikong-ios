import Foundation

/// Token 自动续期并发协调器（`actor` 串行控制，避免并发请求触发重复刷新）
public actor TokenCoordinator {
    public typealias GatewayRefreshAction = @Sendable (GatewaySession, SessionState) async throws -> GatewaySession
    public typealias LegacyRefreshAction = @Sendable (OldSession, SessionState) async throws -> SessionState

    private let store: any SessionStoring
    private var inFlightGatewayTask: Task<GatewaySession, Error>?
    private var inFlightLegacyTask: Task<SessionState, Error>?

    public init(store: any SessionStoring) {
        self.store = store
    }

    public func currentState() -> SessionState {
        store.loadSession()
    }

    public func updateState(_ transform: (inout SessionState) -> Void) -> SessionState {
        var state = store.loadSession()
        transform(&state)
        store.saveSession(state)
        return state
    }

    /// 检查网关 Token（剩余 <= 300s 或强制刷新）并在需要时串行续期
    public func ensureFreshGateway(
        force: Bool = false,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        refreshGateway: @escaping GatewayRefreshAction,
        refreshLegacy: @escaping LegacyRefreshAction
    ) async throws -> GatewaySession {
        let state = store.loadSession()
        if !force, let gw = state.gatewaySession, gw.expiresAtMs > 0, (gw.expiresAtMs - nowMs) > 300_000 {
            return gw
        }
        if !force, let gw = state.gatewaySession, gw.expiresAtMs <= 0 {
            return gw
        }

        if let task = inFlightGatewayTask {
            return try await task.value
        }

        let task = Task<GatewaySession, Error> {
            defer { self.clearGatewayTask() }
            let current = self.store.loadSession()
            if let gw = current.gatewaySession, !gw.refreshToken.isEmpty {
                do {
                    let refreshed = try await refreshGateway(gw, current)
                    var updated = self.store.loadSession()
                    updated.gatewaySession = refreshed
                    self.store.saveSession(updated)
                    return refreshed
                } catch {
                    // 网关刷新失败时，尝试刷新旧 Token 后重登网关
                }
            }
            guard let old = current.oldSession else {
                throw LeapAPIError.notLoggedIn("未登录（缺少旧会话凭证）")
            }
            let updatedState = try await refreshLegacy(old, current)
            guard let newGw = updatedState.gatewaySession else {
                throw LeapAPIError.gatewayTokenExpired("刷新旧凭证后仍未能获取网关访问令牌")
            }
            return newGw
        }
        inFlightGatewayTask = task
        return try await task.value
    }

    /// 检查旧 Token（剩余 <= 60s 或强制刷新）并在需要时串行续期后换取新网关会话
    public func ensureFreshLegacy(
        force: Bool = false,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        refreshLegacy: @escaping LegacyRefreshAction
    ) async throws -> SessionState {
        let state = store.loadSession()
        guard let old = state.oldSession else {
            throw LeapAPIError.notLoggedIn("未登录（缺少旧凭证）")
        }
        if !force, (old.expiresAtMs - nowMs) > 60_000 {
            return state
        }
        if let task = inFlightLegacyTask {
            return try await task.value
        }
        let task = Task<SessionState, Error> {
            defer { self.clearLegacyTask() }
            let updated = try await refreshLegacy(old, self.store.loadSession())
            self.store.saveSession(updated)
            return updated
        }
        inFlightLegacyTask = task
        return try await task.value
    }

    private func clearGatewayTask() {
        inFlightGatewayTask = nil
    }

    private func clearLegacyTask() {
        inFlightLegacyTask = nil
    }
}
