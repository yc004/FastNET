import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [WiFiProfile] = []
    @Published private(set) var lastCreatedProfileID: UUID?
    @Published var autoSwitchEnabled: Bool {
        didSet { defaults.set(autoSwitchEnabled, forKey: Keys.autoSwitch) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let profiles = "wifiProfiles.v1"
        static let autoSwitch = "autoSwitchEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoSwitchEnabled = defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.profiles),
           let saved = try? decoder.decode([WiFiProfile].self, from: data) {
            profiles = saved
            normalizeAutomaticProfiles()
        }
    }

    func profiles(for ssid: String?) -> [WiFiProfile] {
        guard let ssid else { return [] }
        return profiles.filter { $0.ssid == ssid }
    }

    func automaticProfile(for ssid: String?) -> WiFiProfile? {
        profiles(for: ssid).first { $0.isAutoApply }
    }

    var ssids: [String] {
        Array(Set(profiles.map(\.ssid))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func upsert(_ profile: WiFiProfile) {
        if profile.isAutoApply {
            for index in profiles.indices where profiles[index].ssid == profile.ssid && profiles[index].id != profile.id {
                profiles[index].isAutoApply = false
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        sortProfiles()
        save()
    }

    @discardableResult
    func createProfile(suggestedSSID: String? = nil) -> WiFiProfile {
        let preferred = suggestedSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ssid: String
        if let preferred, !preferred.isEmpty {
            ssid = preferred
        } else {
            let base = "新 Wi‑Fi"
            var candidate = base
            var suffix = 2
            while profiles(for: candidate).isEmpty == false {
                candidate = "\(base) \(suffix)"
                suffix += 1
            }
            ssid = candidate
        }
        let existingCount = profiles(for: ssid).count
        let profile = WiFiProfile(
            ssid: ssid,
            note: existingCount == 0 ? "" : "配置 \(existingCount + 1)",
            isAutoApply: automaticProfile(for: ssid) == nil
        )
        upsert(profile)
        lastCreatedProfileID = profile.id
        return profile
    }

    func remove(_ profile: WiFiProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }

    private func normalizeAutomaticProfiles() {
        var automaticSSIDs = Set<String>()
        for index in profiles.indices where profiles[index].isAutoApply {
            if automaticSSIDs.contains(profiles[index].ssid) {
                profiles[index].isAutoApply = false
            } else {
                automaticSSIDs.insert(profiles[index].ssid)
            }
        }
        sortProfiles()
        save()
    }

    private func sortProfiles() {
        profiles.sort {
            let ssidOrder = $0.ssid.localizedCaseInsensitiveCompare($1.ssid)
            if ssidOrder != .orderedSame { return ssidOrder == .orderedAscending }
            if $0.isAutoApply != $1.isAutoApply { return $0.isAutoApply }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
