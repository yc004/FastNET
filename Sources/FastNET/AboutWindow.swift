import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 FastNET"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutFastNETView())
        window.center()
        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutFastNETView: View {
    @ObservedObject private var updates = UpdateService.shared

    private let repositoryURL = URL(string: "https://github.com/yc004/FastNET")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var updateButtonTitle: String {
        switch updates.state {
        case .available, .ready: return "安装可用更新…"
        case .checking: return "正在检查…"
        case .downloading: return "正在下载…"
        default: return "检查更新…"
        }
    }

    private var updateActionDisabled: Bool {
        switch updates.state {
        case .checking, .downloading: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                FastNETBrandIcon(size: 104)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                Text("FastNET")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("让每个 Wi‑Fi 都用对配置")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("版本 \(version)（\(build)）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 44)
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("软件更新", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Spacer()
                    Button(updateButtonTitle) {
                        switch updates.state {
                        case .available, .ready: updates.presentCurrentUpdate()
                        default: updates.checkForUpdates()
                        }
                    }
                    .disabled(updateActionDisabled)
                }

                if !updates.statusText.isEmpty {
                    Text(updates.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("自动检查软件更新", isOn: $updates.automaticallyChecksForUpdates)
                Toggle("在后台自动下载新版本", isOn: $updates.automaticallyDownloadsUpdates)
                    .disabled(!updates.automaticallyChecksForUpdates)

                Divider()

                Button {
                    NSWorkspace.shared.open(repositoryURL)
                } label: {
                    HStack {
                        Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 32)

            Spacer(minLength: 20)
            Text("Copyright © 2026 FastNET")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 22)
        }
        .frame(width: 470, height: 560)
        .background(.background)
    }
}
