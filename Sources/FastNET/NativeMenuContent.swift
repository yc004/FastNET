import AppKit
import SwiftUI

/// A true macOS status-item menu. SwiftUI maps these declarations to native
/// NSMenuItems instead of presenting a custom popover window.
struct NativeMenuContent: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var network: NetworkController
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var dockIcon = DockIconController.shared

    private var currentProfiles: [WiFiProfile] {
        store.profiles(for: network.snapshot.ssid)
    }

    var body: some View {
        connectionSection

        Divider()

        if !currentProfiles.isEmpty {
            Menu("应用配置") {
                ForEach(currentProfiles) { profile in
                    Button {
                        network.apply(profile)
                    } label: {
                        Label(
                            profile.displayName,
                            systemImage: network.lastAppliedProfileID == profile.id
                                && network.snapshot.ssid == profile.ssid
                                ? "checkmark"
                                : (profile.isAutoApply ? FastNETSymbol.automatic : FastNETSymbol.profile)
                        )
                    }
                    .disabled(network.applyState == .applying)
                }
            }

            if let automatic = store.automaticProfile(for: network.snapshot.ssid) {
                Text("自动应用：\(automatic.displayName)")
            } else {
                Text("没有自动应用的配置")
            }
        }

        if let ssid = network.snapshot.ssid {
            Button {
                createProfileAndOpen(for: ssid)
            } label: {
                Label("新建“\(ssid)”的配置…", systemImage: "plus")
            }
        }

        Toggle("自动切换配置", isOn: $store.autoSwitchEnabled)

        Toggle(
            "在 Dock 中显示 FastNET",
            isOn: Binding(
                get: { dockIcon.isVisible },
                set: { dockIcon.setVisible($0) }
            )
        )

        Divider()

        Button {
            network.refresh()
        } label: {
            Label("刷新网络状态", systemImage: FastNETSymbol.refresh)
        }
        .keyboardShortcut("r")

        Button {
            activateConfigurationWindow()
        } label: {
            Label("管理配置…", systemImage: FastNETSymbol.settings)
        }

        Divider()

        Button("关于 FastNET") {
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Button("退出 FastNET") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var connectionSection: some View {
        if let ssid = network.snapshot.ssid {
            Label(ssid, systemImage: FastNETSymbol.connected)
            if let ip = network.snapshot.ipAddress {
                Text("IP 地址：\(ip)")
            }
        } else if network.snapshot.isConnected {
            Label("Wi‑Fi 已连接", systemImage: FastNETSymbol.connected)
            if let ip = network.snapshot.ipAddress {
                Text("IP 地址：\(ip)")
            }
            Text("Wi‑Fi 名称权限未开启")
        } else {
            Label("未连接 Wi‑Fi", systemImage: FastNETSymbol.disconnected)
        }

        if case .success = network.applyState {
            Label("配置已应用", systemImage: FastNETSymbol.success)
        } else if case .failure(let message) = network.applyState {
            Label("应用失败：\(message)", systemImage: FastNETSymbol.warning)
        }
    }

    private func activateConfigurationWindow() {
        openWindow(id: "profiles")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createProfileAndOpen(for ssid: String) {
        store.createProfile(suggestedSSID: ssid)
        activateConfigurationWindow()
    }
}
