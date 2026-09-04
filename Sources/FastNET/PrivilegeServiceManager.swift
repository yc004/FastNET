import AppKit
import FastNETShared
import Foundation
import ServiceManagement
import SystemSettingsKit

@MainActor
final class PrivilegeServiceManager: ObservableObject {
    static let shared = PrivilegeServiceManager()

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?
    @Published private(set) var isHelperRunning = false

    private let service = SMAppService.daemon(plistName: FastNETHelperConstants.plistName)

    private init() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }
    var isReady: Bool { isEnabled }

    func refresh() {
        status = service.status
        if status == .enabled {
            startHelper()
        } else {
            isHelperRunning = false
        }
    }

    func requestAuthorization() {
        lastError = nil
        registerCurrentBuild()
    }

    private func registerCurrentBuild() {
        do {
            try service.register()
        } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
            // Registration is persistent; refresh the current user-approval state.
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if status == .requiresApproval {
            lastError = nil
        } else if status == .enabled {
            startHelper()
        }
    }

    func startHelper() {
        guard status == .enabled else { return }
        let connection = makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            connection.invalidate()
            Task { @MainActor in self?.isHelperRunning = false }
        } as? FastNETHelperProtocol
        guard let proxy else {
            connection.invalidate()
            isHelperRunning = false
            return
        }
        connection.resume()
        proxy.ping { [weak self] success in
            connection.invalidate()
            Task { @MainActor in self?.isHelperRunning = success }
        }
    }

    func stopHelper() {
        guard status == .enabled else { return }
        let connection = makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connection.invalidate()
        } as? FastNETHelperProtocol
        guard let proxy else {
            connection.invalidate()
            return
        }
        connection.resume()
        let acknowledgement = DispatchSemaphore(value: 0)
        proxy.stopHelper {
            acknowledgement.signal()
        }
        _ = acknowledgement.wait(timeout: .now() + 1)
        connection.invalidate()
        isHelperRunning = false
    }

    private nonisolated func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: FastNETHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FastNETHelperProtocol.self)
        return connection
    }

    func openApprovalSettings() {
        SystemSettings.open(.loginItems)
    }

    nonisolated func apply(_ request: NetworkConfigurationRequest) async -> Result<Void, Error> {
        do {
            let data = try JSONEncoder().encode(request)
            return await withCheckedContinuation { continuation in
                let connection = makeConnection()
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
