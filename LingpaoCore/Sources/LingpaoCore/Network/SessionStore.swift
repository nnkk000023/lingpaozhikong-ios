import Foundation

/// 会话存储抽象协议（支持主 App KeychainStore 与测试用内存 Store 无缝切换）
public protocol SessionStoring: AnyObject, Sendable {
    func loadSession() -> SessionState
    func saveSession(_ state: SessionState)
}

/// 线程安全内存会话存储器（用于单元测试或临时访客模式）
public final class InMemorySessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SessionState

    public init(initial: SessionState = SessionState()) {
        self.state = initial
    }

    public func loadSession() -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func saveSession(_ newState: SessionState) {
        lock.lock()
        defer { lock.unlock() }
        state = newState
    }
}
