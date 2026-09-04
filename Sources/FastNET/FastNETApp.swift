import CoreLocation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.module.url(forResource: "FastNET-AppIcon-Master", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenPermissionOnboarding.v2")
        let authorization = CLLocationManager().authorizationStatus
        if PermissionOnboardingPolicy.shouldShow(
            hasSeenOnboarding: hasSeenOnboarding,
            authorization: authorization,
            helperEnabled: PrivilegeServiceManager.shared.isReady
        ) {
            showPermissionOnboarding()
        }
    }

    private func showPermissionOnboarding() {
        let view = PermissionOnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasSeenPermissionOnboarding.v2")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 530),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 FastNET"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        onboardingWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct FastNETApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: ProfileStore
    @StateObject private var network: NetworkController

    init() {
        let store = ProfileStore()
        _store = StateObject(wrappedValue: store)
        let network = NetworkController(store: store)
        _network = StateObject(wrappedValue: network)
        Task { @MainActor in network.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            NativeMenuContent()
                .environmentObject(store)
                .environmentObject(network)
        } label: {
            Label(
                "FastNET",
                systemImage: network.snapshot.isConnected
                    ? FastNETSymbol.menuBarConnected
                    : FastNETSymbol.menuBarDisconnected
            )
            .symbolEffect(.bounce, value: network.snapshot.ssid)
        }
        .menuBarExtraStyle(.menu)

        Window("FastNET 配置", id: "profiles") {
            ProfilesWindow()
                .environmentObject(store)
                .environmentObject(network)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1040, height: 650)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
