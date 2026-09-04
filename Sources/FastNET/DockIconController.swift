import AppKit
import Foundation

enum DockIconPreference {
    static let key = "showDockIcon"

    static func value(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

@MainActor
final class DockIconController: ObservableObject {
    static let shared = DockIconController()

    @Published private(set) var isVisible: Bool
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isVisible = DockIconPreference.value(from: defaults)
    }

    func apply() {
        NSApplication.shared.setActivationPolicy(isVisible ? .regular : .accessory)
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        defaults.set(visible, forKey: DockIconPreference.key)
        apply()
    }
}
