import AppKit
import SwiftUI

struct MenuPopoverView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var network: NetworkController
    @Environment(\.openWindow) private var openWindow

    private var currentProfile: WiFiProfile? {
        store.automaticProfile(for: network.snapshot.ssid) ?? store.profiles(for: network.snapshot.ssid).first
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    FastNETBrandIcon()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(network.snapshot.ssid ?? (network.snapshot.isConnected ? "Wi‑Fi 已连接" : "未连接 Wi‑Fi"))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(statusSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusIndicator
                }

                if network.needsWiFiNamePermission {
                    WiFiPermissionCard(
                        buttonTitle: network.wifiPermissionButtonTitle,
                        action: network.requestWiFiNameAccess
                    )
                } else if let profile = currentProfile {
                    ProfileSummary(profile: profile)
                    Button {
                        network.apply(profile)
                    } label: {
                        HStack {
                            if network.applyState == .applying { ProgressView().controlSize(.small) }
                            Text(network.applyState == .applying ? "正在应用…" : "立即应用配置")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(network.applyState == .applying)
                } else if let ssid = network.snapshot.ssid {
                    EmptyProfileCard(ssid: ssid) {
                        openWindow(id: "profiles")
                    }
                }

                if case .failure(let message) = network.applyState {
                    Label(message, systemImage: FastNETSymbol.warning)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

            Divider()

            HStack {
                Toggle("自动切换", isOn: $store.autoSwitchEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("管理配置…") { openWindow(id: "profiles") }
                    .buttonStyle(.plain)
                Menu {
                    Button("刷新") { network.refresh() }
                    Divider()
                    Button("退出 FastNET") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: FastNETSymbol.more)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var statusSubtitle: String {
        if let ip = network.snapshot.ipAddress { return "已连接 · \(ip)" }
        return "等待网络连接"
    }

    @ViewBuilder private var statusIndicator: some View {
        if case .success = network.applyState {
            Image(systemName: FastNETSymbol.success)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
        } else if network.snapshot.isConnected {
            Circle().fill(.green).frame(width: 8, height: 8)
        } else {
            Circle().fill(.secondary.opacity(0.45)).frame(width: 8, height: 8)
        }
    }
}

private struct WiFiPermissionCard: View {
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text("需要读取 Wi‑Fi 名称")
                    .font(.system(size: 13, weight: .semibold))
                Text("macOS 要求位置权限才能提供当前网络名称。FastNET 不会读取或保存您的位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ProfileSummary: View {
    let profile: WiFiProfile

    var body: some View {
        VStack(spacing: 9) {
            SummaryRow(label: "IPv4", value: profile.ipv4Mode == .dhcp ? "自动 (DHCP)" : profile.ipAddress)
            SummaryRow(label: "DNS", value: profile.dnsDisplay)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1)
        }
        .font(.system(size: 12))
    }
}

private struct EmptyProfileCard: View {
    let ssid: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: FastNETSymbol.profile)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("还没有此网络的配置")
                .font(.system(size: 13, weight: .medium))
            Button("为“\(ssid)”创建配置", action: action)
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
