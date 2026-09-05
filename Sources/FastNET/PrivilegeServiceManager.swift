import FastNETShared
import Foundation

@MainActor
final class PrivilegeServiceManager: ObservableObject {
    static let shared = PrivilegeServiceManager()

    @Published private(set) var lastError: String?
    @Published private(set) var isHelperRunning = false
    @Published private(set) var isChecking = false

    private var checkTask: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool { isHelperRunning }
    var isReady: Bool { isHelperRunning }
    var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: FastNETHelperConstants.installedExecutablePath)
            && FileManager.default.fileExists(atPath: FastNETHelperConstants.installedPlistPath)
    }

    func refresh() {
        startHelper()
    }

    func requestAuthorization() {
        lastError = nil
        startHelper()
    }

    func reconcileAuthorization() {
        startHelper()
    }

    func prepareForLaunch() async {
        isChecking = true
        let success = await HelperXPCTransport.ping(timeout: 2)
        isHelperRunning = success
        isChecking = false
        if !success {
            lastError = isHelperInstalled
                ? "系统帮助程序未能启动，请重新运行 FastNET 安装器"
                : "尚未安装系统帮助程序，请运行 FastNET 安装器"
        }
    }

    func startHelper() {
        guard checkTask == nil else { return }
        isChecking = true
        checkTask = Task { [weak self] in
            guard let self else { return }
            let success = await HelperXPCTransport.ping(timeout: 2)
            self.isHelperRunning = success
            self.isChecking = false
            if success {
                self.lastError = nil
            } else {
                self.lastError = self.isHelperInstalled
                    ? "系统帮助程序未能启动，请重新运行 FastNET 安装器"
                    : "尚未安装系统帮助程序，请运行 FastNET 安装器"
            }
            self.checkTask = nil
        }
    }

    func stopHelper() {
        guard isHelperRunning else { return }
        HelperXPCTransport.stop(timeout: 1)
        isHelperRunning = false
    }

    nonisolated func apply(_ request: NetworkConfigurationRequest) async -> Result<Void, Error> {
        do {
            let data = try JSONEncoder().encode(request)
            return await withCheckedContinuation { continuation in
                let connection = HelperXPCTransport.makeConnection()
                let gate = XPCApplyCompletionGate(
                    connection: connection,
                    continuation: continuation
                )
                connection.interruptionHandler = {
                    gate.finish(.failure(PrivilegeServiceError.unavailable))
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    gate.finish(.failure(error))
                } as? FastNETHelperProtocol
                guard let proxy else {
                    gate.finish(.failure(PrivilegeServiceError.unavailable))
                    return
                }
                connection.resume()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 6) {
                    gate.finish(.failure(PrivilegeServiceError.timedOut))
                }
                proxy.applyConfiguration(data as NSData) { success, message in
                    if success {
                        gate.finish(.success(()))
                    } else {
                        gate.finish(.failure(
                            PrivilegeServiceError.applyFailed(message as String? ?? "修改网络设置失败")
                        ))
                    }
                }
            }
        } catch {
            return .failure(error)
        }
    }
}

/// XPC invokes reply and error blocks on its private queues. Keeping those
/// blocks outside the main-actor manager prevents Swift executor assertions.
private enum HelperXPCTransport {
    nonisolated static func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: FastNETHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FastNETHelperProtocol.self)
        return connection
    }

    nonisolated static func ping(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            ping(timeout: timeout) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated static func ping(
        timeout: TimeInterval,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let connection = makeConnection()
        let gate = XPCValueCompletionGate(connection: connection, completion: completion)
        connection.interruptionHandler = { gate.finish(false) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            gate.finish(false)
        } as? FastNETHelperProtocol
        guard let proxy else {
            gate.finish(false)
            return
        }
        connection.resume()
        proxy.ping { success in gate.finish(success) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            gate.finish(false)
        }
    }

    nonisolated static func stop(timeout: TimeInterval) {
        let connection = makeConnection()
        let acknowledgement = DispatchSemaphore(value: 0)
        let gate = XPCValueCompletionGate<Void>(connection: connection) { _ in
            acknowledgement.signal()
        }
        connection.interruptionHandler = { gate.finish(()) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            gate.finish(())
        } as? FastNETHelperProtocol
        guard let proxy else {
            gate.finish(())
            return
        }
        connection.resume()
        proxy.stopHelper { gate.finish(()) }
        if acknowledgement.wait(timeout: .now() + timeout) == .timedOut {
            gate.finish(())
        }
    }
}

enum PrivilegeServiceError: LocalizedError {
    case unavailable
    case timedOut
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "免密码切换服务尚未启用"
        case .timedOut: return "帮助程序响应超时，请重新打开 FastNET 或检查后台运行权限"
        case .applyFailed(let detail): return detail
        }
    }
}

private final class XPCApplyCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFinished = false
    private let connection: NSXPCConnection
    private let continuation: CheckedContinuation<Result<Void, Error>, Never>

    init(
        connection: NSXPCConnection,
        continuation: CheckedContinuation<Result<Void, Error>, Never>
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        lock.unlock()
        connection.invalidate()
        continuation.resume(returning: result)
    }
}

private final class XPCValueCompletionGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFinished = false
    private let connection: NSXPCConnection
    private let completion: @Sendable (Value) -> Void

    init(
        connection: NSXPCConnection,
        completion: @escaping @Sendable (Value) -> Void
    ) {
        self.connection = connection
        self.completion = completion
    }

    func finish(_ value: Value) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        lock.unlock()
        connection.invalidate()
        completion(value)
    }
}
