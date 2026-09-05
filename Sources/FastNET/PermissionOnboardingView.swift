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
            VStack(spacing: 13) {
                FastNETBrandIcon(size: 68)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                VStack(spacing: 7) {
                    Text("让每个 Wi‑Fi 都用对配置")
                        .font(.system(size: 24, weight: .bold))
                    Text("安装器与系统授权准备完成后，FastNET 就能自动工作")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 12) {
                PermissionStepCard(
                    number: 1,
                    symbol: "wifi",
                    title: "读取 Wi‑Fi 名称",
                    detail: "仅用于匹配配置，不读取、保存或上传位置",
                    isComplete: permission.isAuthorized,
                    status: locationStatus
                )
                PermissionStepCard(
                    number: 2,
                    symbol: "lock.shield.fill",
                    title: "系统帮助程序",
                    detail: "由安装器一次性安装，切换 IP 和 DNS 时无需重复输入密码",
                    isComplete: privilege.isReady,
                    status: backgroundStatus
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            VStack(spacing: 11) {
                if permission.isAuthorized && privilege.isReady {
                    Label("所需权限均已启用", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                    Button("开始使用 FastNET", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if permission.isDenied {
                    Button(action: permission.request) {
                        Text("打开“位置服务”")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if !permission.isAuthorized {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("请在 macOS 弹窗中选择“允许”")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        privilege.lastError ?? "正在检测系统帮助程序",
                        systemImage: privilege.isChecking ? "hourglass" : "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(privilege.isChecking ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
                    if !privilege.isChecking {
                        Button("重新检测帮助程序") {
                            privilege.requestAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Text("如果仍无法检测，请退出 FastNET 并重新运行安装器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("暂时关闭", action: onFinish)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 22)
        }
        .frame(width: 520, height: 560)
        .background(.regularMaterial)
        .onAppear {
            guard !didRequestAutomatically else { return }
            didRequestAutomatically = true
            permission.requestOnFirstLaunch()
            privilege.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
            privilege.reconcileAuthorization()
        }
        .task {
            while !Task.isCancelled && !privilege.isReady {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                permission.refresh()
                privilege.reconcileAuthorization()
            }
        }
    }

    private var locationStatus: String {
        if permission.isAuthorized { return "已允许" }
        if permission.isDenied { return "需要在系统设置中允许" }
        return "等待系统授权"
    }

    private var backgroundStatus: String {
        if privilege.isReady { return "已安装并运行" }
        if privilege.isChecking { return "正在检测" }
        if privilege.isHelperInstalled { return "需要重新安装" }
        return "尚未安装"
    }
}

private struct PermissionStepCard: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String
    let isComplete: Bool
    let status: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((isComplete ? Color.green : Color.accentColor).opacity(0.12))
                Image(systemName: isComplete ? "checkmark" : symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isComplete ? Color.green : Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isComplete ? Color.green : Color.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }
}
