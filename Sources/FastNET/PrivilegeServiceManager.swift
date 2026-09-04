import AppKit
import FastNETShared
import Foundation
import ServiceManagement

@MainActor
final class PrivilegeServiceManager: ObservableObject {
    static let shared = PrivilegeServiceManager()

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?

    private let service = SMAppService.daemon(plistName: FastNETHelperConstants.plistName)

    private init() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }
    var isReady: Bool { isEnabled }

    func refresh() {
        status = service.status
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
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    nonisolated func apply(_ request: NetworkConfigurationRequest) async -> Result<Void, Error> {
        do {
            let data = try JSONEncoder().encode(request)
            return await withCheckedContinuation { continuation in
                let connection = NSXPCConnection(
                    machServiceName: FastNETHelperConstants.machServiceName,
                    options: .privileged
                )
                connection.remoteObjectInterface = NSXPCInterface(with: FastNETHelperProtocol.self)
                connection.interruptionHandler = {
                    connection.invalidate()
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    connection.invalidate()
                    continuation.resume(returning: .failure(error))
                } as? FastNETHelperProtocol
                guard let proxy else {
                    connection.invalidate()
                    continuation.resume(returning: .failure(PrivilegeServiceError.unavailable))
                    return
                }
                connection.resume()
                proxy.applyConfiguration(data as NSData) { success, message in
                    connection.invalidate()
                    if success {
                        continuation.resume(returning: .success(()))
                    } else {
                        continuation.resume(returning: .failure(
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
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "免密码切换服务尚未启用"
        case .applyFailed(let detail): return detail
        }
    }
}
