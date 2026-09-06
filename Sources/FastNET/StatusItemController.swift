import AppKit

/// Owns a native macOS status item so transient UI can be anchored to the
/// actual menu-bar button instead of an estimated screen position.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private weak var store: ProfileStore?
    private weak var network: NetworkController?

    private override init() {
        super.init()
    }

    var anchorFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func configure(store: ProfileStore, network: NetworkController) {
        self.store = store
        self.network = network
        updateIcon(isConnected: network.snapshot.isConnected)
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "FastNET"
        item.button?.setAccessibilityLabel("FastNET")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIcon(isConnected: network?.snapshot.isConnected ?? false)
    }

    func updateIcon(isConnected: Bool) {
        guard let button = statusItem?.button else { return }
        let symbol = isConnected
            ? FastNETSymbol.menuBarConnected
            : FastNETSymbol.menuBarDisconnected
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FastNET")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let store, let network else { return }

        let snapshot = network.snapshot
        if let ssid = snapshot.ssid {
            menu.addItem(infoItem(ssid, symbol: FastNETSymbol.connected))
        } else if snapshot.isConnected {
            menu.addItem(infoItem("Wi‑Fi 已连接", symbol: FastNETSymbol.connected))
        } else {
            menu.addItem(infoItem("未连接 Wi‑Fi", symbol: FastNETSymbol.disconnected))
        }
        if let ip = snapshot.ipAddress {
            menu.addItem(infoItem("IP 地址：\(ip)"))
        }
        if snapshot.isConnected, snapshot.ssid == nil {
            menu.addItem(infoItem("Wi‑Fi 名称权限未开启"))
        }
        switch network.applyState {
        case .success:
            menu.addItem(infoItem("配置已应用", symbol: FastNETSymbol.success))
        case .failure(let message):
            menu.addItem(infoItem("应用失败：\(message)", symbol: FastNETSymbol.warning))
        default:
            break
        }

        menu.addItem(.separator())
        let profiles = store.profiles(for: snapshot.ssid)
        if !profiles.isEmpty {
            let parent = NSMenuItem(title: "应用配置", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "应用配置")
            for profile in profiles {
                let item = actionItem(profile.displayName, action: #selector(applyProfile(_:)))
                item.representedObject = profile.id.uuidString
                item.isEnabled = network.applyState != .applying
                item.state = Self.isCurrentlyApplied(
                    profileID: profile.id,
                    profileSSID: profile.ssid,
                    currentSSID: snapshot.ssid,
                    lastAppliedProfileID: network.lastAppliedProfileID
                ) ? .on : .off
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
            if let automatic = store.automaticProfile(for: snapshot.ssid) {
                menu.addItem(infoItem("自动应用：\(automatic.displayName)"))
            } else {
                menu.addItem(infoItem("没有自动应用的配置"))
            }
        }

        if let ssid = snapshot.ssid {
            let item = actionItem(
                "新建“\(ssid)”的配置…",
                symbol: "plus",
                action: #selector(createProfile(_:))
            )
            item.representedObject = ssid
            menu.addItem(item)
        }

        let autoSwitch = actionItem("自动切换配置", action: #selector(toggleAutoSwitch(_:)))
        autoSwitch.state = store.autoSwitchEnabled ? .on : .off
        menu.addItem(autoSwitch)

        let dock = actionItem("在 Dock 中显示 FastNET", action: #selector(toggleDockIcon(_:)))
        dock.state = DockIconController.shared.isVisible ? .on : .off
        menu.addItem(dock)

        menu.addItem(.separator())
        let refresh = actionItem("刷新网络状态", symbol: FastNETSymbol.refresh, action: #selector(refreshNetwork(_:)))
        refresh.keyEquivalent = "r"
        menu.addItem(refresh)
        menu.addItem(actionItem("管理配置…", symbol: FastNETSymbol.settings, action: #selector(showProfiles(_:))))
        menu.addItem(.separator())
        menu.addItem(actionItem("关于 FastNET", action: #selector(showAbout(_:))))
        let quit = actionItem("退出 FastNET", action: #selector(quit(_:)))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func infoItem(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func actionItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    nonisolated static func isCurrentlyApplied(
        profileID: UUID,
        profileSSID: String,
        currentSSID: String?,
        lastAppliedProfileID: UUID?
    ) -> Bool {
        profileID == lastAppliedProfileID && profileSSID == currentSSID
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let profile = store?.profiles.first(where: { $0.id == id }) else { return }
        network?.apply(profile)
    }

    @objc private func createProfile(_ sender: NSMenuItem) {
        guard let ssid = sender.representedObject as? String else { return }
        store?.createProfile(suggestedSSID: ssid)
        showProfiles(sender)
    }

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        store?.autoSwitchEnabled.toggle()
    }

    @objc private func toggleDockIcon(_ sender: NSMenuItem) {
        DockIconController.shared.setVisible(!DockIconController.shared.isVisible)
    }

    @objc private func refreshNetwork(_ sender: NSMenuItem) {
        network?.refresh()
    }

    @objc private func showProfiles(_ sender: Any?) {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "FastNET 配置" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
