import AppKit
@preconcurrency import CoreLocation
import SwiftUI
import SystemSettingsKit

enum PermissionOnboardingPolicy {
    static func shouldShow(
        hasSeenOnboarding: Bool,
        authorization: CLAuthorizationStatus,
        helperEnabled: Bool
    ) -> Bool {
        let isAuthorized = authorization == .authorized || authorization == .authorizedAlways
        return !hasSeenOnboarding || !isAuthorized || !helperEnabled
    }
}

@MainActor
private final class LocationPermissionModel: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus
    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func request() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isDenied {
            SystemSettings.open(.privacy(anchor: .privacyLocationServices))
        } else {
            refresh()
        }
    }

    func requestOnFirstLaunch() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        authorization = manager.authorizationStatus
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }
}

struct PermissionOnboardingView: View {
    @StateObject private var permission = LocationPermissionModel()
    @ObservedObject private var privilege = PrivilegeServiceManager.shared
    @State private var didRequestAutomatically = false
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                FastNETBrandIcon(size: 76)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)

                VStack(spacing: 7) {
                    Text("让每个 Wi‑Fi 都用对配置")
                        .font(.system(size: 24, weight: .bold))
                    Text("首次使用只需完成一项权限设置")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 34)
            .padding(.bottom, 25)

            VStack(spacing: 0) {
                PermissionFeatureRow(
                    symbol: "wifi",
                    title: "识别当前 Wi‑Fi",
                    detail: "读取网络名称，用来匹配您保存的配置"
                )
                Divider().padding(.leading, 45)
                PermissionFeatureRow(
                    symbol: "location.slash.fill",
                    title: "不读取实际位置",
                    detail: "FastNET 不请求定位坐标，也不会保存或上传位置"
                )
                Divider().padding(.leading, 45)
                PermissionFeatureRow(
                    symbol: "lock.shield.fill",
                    title: "切换配置不再重复输入密码",
                    detail: "首次批准系统辅助服务后，IP 和 DNS 切换将自动完成"
                )
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                if permission.isAuthorized && privilege.isReady {
                    Label("所需权限均已启用", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                    Button("开始使用 FastNET", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if !privilege.isReady {
                    if privilege.status == .requiresApproval {
                        Text("请在“登录项与扩展”中允许 FastNET 后台运行")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button("打开系统设置") {
                            privilege.openApprovalSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在请求免密码切换权限…")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    if let error = privilege.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } else if permission.isDenied {
                    Button(action: permission.request) {
                        Text("打开位置服务设置")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("暂时关闭", action: onFinish)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("请在 macOS 弹窗中选择“允许”")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 26)
        }
        .frame(width: 520, height: 530)
        .background(.regularMaterial)
        .onAppear {
            guard !didRequestAutomatically else { return }
            didRequestAutomatically = true
            permission.requestOnFirstLaunch()
            privilege.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
            privilege.refresh()
        }
    }
}

private struct PermissionFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}
