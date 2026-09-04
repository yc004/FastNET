import AppKit
import SwiftUI

enum AutoSwitchHUDState: Equatable {
    case applying(profile: String, ssid: String)
    case success(profile: String, ssid: String)
    case failure(profile: String, message: String)
}

@MainActor
private final class AutoSwitchHUDModel: ObservableObject {
    @Published var state: AutoSwitchHUDState = .applying(profile: "", ssid: "")
    @Published var isPresented = false
}

@MainActor
final class AutoSwitchHUDController {
    static let shared = AutoSwitchHUDController()

    private let model = AutoSwitchHUDModel()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showApplying(profile: String, ssid: String) {
        present(.applying(profile: profile, ssid: ssid))
    }

    func showSuccess(profile: String, ssid: String) {
        present(.success(profile: profile, ssid: ssid), dismissAfter: 2.4)
    }

    func showFailure(profile: String, message: String) {
        present(.failure(profile: profile, message: message), dismissAfter: 4)
    }

    private func present(_ state: AutoSwitchHUDState, dismissAfter delay: TimeInterval? = nil) {
        dismissTask?.cancel()
        model.state = state

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            model.isPresented = !shouldAnimate
            panel.orderFrontRegardless()
            if shouldAnimate {
                Task { @MainActor [weak self] in
                    await Task.yield()
                    withAnimation(.spring(duration: 0.34, bounce: 0.26)) {
                        self?.model.isPresented = true
                    }
                }
            }
        } else {
            model.isPresented = true
            panel.orderFrontRegardless()
        }

        guard let delay else { return }
        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if let panel, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                withAnimation(.easeIn(duration: 0.2)) {
                    self?.model.isPresented = false
                }
                try? await Task.sleep(for: .milliseconds(210))
                guard !Task.isCancelled else { return }
                panel.orderOut(nil)
            } else {
                self?.model.isPresented = false
                panel?.orderOut(nil)
            }
            self?.dismissTask = nil
        }
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 288, height: 78)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: AutoSwitchHUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let anchor = StatusItemController.shared.anchorFrame
        let screen = anchor.flatMap { target in
            NSScreen.screens.first(where: { $0.frame.intersects(target) })
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let targetX = anchor?.midX ?? (frame.maxX - 170)
        let tailInset: CGFloat = 22
        let proposedX = targetX - panel.frame.width + tailInset
        let x = min(max(proposedX, frame.minX + 10), frame.maxX - panel.frame.width - 10)
        panel.setFrameOrigin(NSPoint(
            x: x,
            y: frame.maxY - panel.frame.height + 6
        ))
    }
}

private struct AutoSwitchHUDView: View {
    @ObservedObject var model: AutoSwitchHUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 10) {
                statusIcon
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.top, 8)
            .frame(width: 288, height: 78)
            .glassEffect(.regular.tint(glassTint), in: MenuBarMessageBubbleShape())
        }
        .scaleEffect(
            model.isPresented ? 1 : 0.14,
            anchor: UnitPoint(x: 0.924, y: 0)
        )
        .offset(y: model.isPresented ? 0 : -5)
        .opacity(model.isPresented ? 1 : 0)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.state)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.state {
        case .applying:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: model.state)
        case .failure:
            Image(systemName: FastNETSymbol.warning)
                .font(.system(size: 21))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, value: model.state)
        }
    }

    private var title: String {
        switch model.state {
        case .applying: return "正在自动切换网络配置"
        case .success: return "网络配置已自动应用"
        case .failure: return "自动切换失败"
        }
    }

    private var detail: String {
        switch model.state {
        case .applying(let profile, let ssid), .success(let profile, let ssid):
            return "\(ssid) · \(profile)"
        case .failure(let profile, let message):
            return "\(profile) · \(message)"
        }
    }

    private var glassTint: Color {
        switch model.state {
        case .applying: return .accentColor.opacity(0.08)
        case .success: return .green.opacity(0.1)
        case .failure: return .red.opacity(0.1)
        }
    }
}

private struct MenuBarMessageBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 8
        let tailCenter = rect.maxX - 22
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + tailHeight,
            width: rect.width,
            height: rect.height - tailHeight
        )
        var path = Path(roundedRect: body, cornerRadius: 15)
        path.move(to: CGPoint(x: tailCenter - 7, y: body.minY + 1))
        path.addQuadCurve(
            to: CGPoint(x: tailCenter, y: rect.minY),
            control: CGPoint(x: tailCenter - 3, y: body.minY - 1)
        )
        path.addQuadCurve(
            to: CGPoint(x: tailCenter + 7, y: body.minY + 1),
            control: CGPoint(x: tailCenter + 3, y: body.minY - 1)
        )
        path.closeSubpath()
        return path
    }
}
