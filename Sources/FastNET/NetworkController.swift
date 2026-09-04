import AppKit
@preconcurrency import CoreLocation
import CoreWLAN
import Foundation
import FastNETShared
import SystemSettingsKit

@MainActor
final class NetworkController: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate {
    @Published private(set) var snapshot: NetworkSnapshot = .disconnected
    @Published private(set) var applyState: ApplyState = .idle
    @Published private(set) var lastAppliedSSID: String?
    @Published private(set) var applyProfileID: UUID?
    @Published private(set) var lastAppliedProfileID: UUID?
    @Published private(set) var locationAuthorization: CLAuthorizationStatus
    @Published private(set) var availableSSIDs: [String] = []

    private weak var store: ProfileStore?
    private let locationManager: CLLocationManager
    private var timer: Timer?
    private var previousSSID: String?

    init(store: ProfileStore) {
        self.store = store
        let manager = CLLocationManager()
        self.locationManager = manager
        self.locationAuthorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var needsWiFiNamePermission: Bool {
        snapshot.isConnected && snapshot.ssid == nil
    }

    var wifiPermissionButtonTitle: String {
        locationAuthorization == .notDetermined ? "允许读取 Wi‑Fi 名称" : "打开隐私设置"
    }

    func requestWiFiNameAccess() {
        switch locationAuthorization {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            refresh()
        case .denied, .restricted:
            SystemSettings.open(.privacy(anchor: .privacyLocationServices))
        @unknown default:
            refresh()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorization = manager.authorizationStatus
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            refresh()
        }
    }

    func start() {
        refresh()
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func refresh() {
        Task {
            let next = await Self.readSnapshot()
            let detectedSSIDs = await Self.readKnownSSIDs(interfaceName: next.interfaceName)
            let changed = next.ssid != previousSSID
            snapshot = next
            availableSSIDs = Array(Set(detectedSSIDs + [next.ssid].compactMap { $0 })).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            previousSSID = next.ssid
            if changed,
               let profile = store?.automaticProfile(for: next.ssid),
               store?.autoSwitchEnabled == true {
                apply(profile)
            }
        }
    }

    func apply(_ profile: WiFiProfile) {
        applyProfileID = profile.id
        lastAppliedProfileID = nil
        guard NetworkValidation.validate(profile) == nil else {
            applyState = .failure(NetworkValidation.validate(profile) ?? "配置无效")
            return
        }
        applyState = .applying
        let service = snapshot.serviceName
        Task {
            let request = NetworkConfigurationRequest(
                serviceName: service,
                interfaceName: snapshot.interfaceName,
                usesDHCP: profile.ipv4Mode == .dhcp,
                ipAddress: profile.ipAddress,
                subnetMask: profile.subnetMask,
                router: profile.router,
                dnsServers: profile.dnsServers,
                appendDefaultDNS: profile.appendDefaultDNS
            )
            let result = await PrivilegeServiceManager.shared.apply(request)
            switch result {
            case .success:
                lastAppliedSSID = profile.ssid
                lastAppliedProfileID = profile.id
                applyState = .success(Date())
                try? await Task.sleep(for: .seconds(1))
                refresh()
            case .failure(let error):
                applyState = .failure(error.localizedDescription)
            }
        }
    }

    func clearStatus() {
        applyState = .idle
        applyProfileID = nil
    }

    private nonisolated static func readSnapshot() async -> NetworkSnapshot {
        await Task.detached(priority: .utility) {
            let hardware = shell("/usr/sbin/networksetup", ["-listallhardwareports"])
            let (_, device) = parseWiFiHardware(hardware.output)
            let order = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
            let service = parseWiFiService(order.output, device: device)
            let coreWLANSsid = CWWiFiClient.shared().interface(withName: device)?.ssid()
            let fallback = shell("/usr/sbin/networksetup", ["-getairportnetwork", device])
            let ssid = coreWLANSsid ?? parseSSID(fallback.output)
            let ip = shell("/usr/sbin/ipconfig", ["getifaddr", device]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let networkInfo = parseNetworkInfo(
                shell("/usr/sbin/networksetup", ["-getinfo", service]).output
            )
            let dns = parseDNSServers(
                shell("/usr/sbin/networksetup", ["-getdnsservers", service]).output
            )
            return NetworkSnapshot(
                ssid: ssid,
                interfaceName: device,
                serviceName: service,
                ipAddress: ip.isEmpty ? networkInfo.ipAddress : ip,
                subnetMask: networkInfo.subnetMask,
                router: networkInfo.router,
                dnsServers: dns,
                configurationMode: networkInfo.mode
            )
        }.value
    }

    private nonisolated static func readKnownSSIDs(interfaceName: String) async -> [String] {
        await Task.detached(priority: .utility) {
            guard let profiles = CWWiFiClient.shared()
                .interface(withName: interfaceName)?
                .configuration()?
                .networkProfiles else { return [] }
            return profiles.compactMap { ($0 as? CWNetworkProfile)?.ssid }
        }.value
    }

    nonisolated static func parseSSID(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["Current Wi-Fi Network: ", "Current AirPort Network: "]
        for marker in markers where trimmed.hasPrefix(marker) {
            let value = String(trimmed.dropFirst(marker.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    nonisolated static func parseWiFiHardware(_ output: String) -> (String, String) {
        let blocks = output.components(separatedBy: "\n\n")
        for block in blocks where block.contains("Hardware Port: Wi-Fi") || block.contains("Hardware Port: AirPort") {
            let lines = block.components(separatedBy: .newlines)
            let port = lines.first(where: { $0.hasPrefix("Hardware Port:") })?
                .replacingOccurrences(of: "Hardware Port:", with: "")
                .trimmingCharacters(in: .whitespaces) ?? "Wi-Fi"
            let device = lines.first(where: { $0.hasPrefix("Device:") })?
                .replacingOccurrences(of: "Device:", with: "")
                .trimmingCharacters(in: .whitespaces) ?? "en0"
            return (port, device)
        }
        return ("Wi-Fi", "en0")
    }

    nonisolated static func parseWiFiService(_ output: String, device: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.contains("Device: \(device)") {
            guard index > 0 else { continue }
            let serviceLine = lines[index - 1].trimmingCharacters(in: .whitespaces)
            if let closeParen = serviceLine.firstIndex(of: ")") {
                let name = serviceLine[serviceLine.index(after: closeParen)...]
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return "Wi-Fi"
    }

    nonisolated static func parseNetworkInfo(
        _ output: String
    ) -> (mode: String?, ipAddress: String?, subnetMask: String?, router: String?) {
        let lines = output.components(separatedBy: .newlines)
        let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mode: String?
        if first.localizedCaseInsensitiveContains("DHCP") {
            mode = "DHCP"
        } else if first.localizedCaseInsensitiveContains("manual") {
            mode = "手动"
        } else {
            mode = nil
        }

        func value(after prefix: String) -> String? {
            guard let line = lines.first(where: { $0.localizedCaseInsensitiveComparePrefix(prefix) }) else {
                return nil
            }
            let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value == "none" ? nil : value
        }

        return (
            mode,
            value(after: "IP address:"),
            value(after: "Subnet mask:"),
            value(after: "Router:")
        )
    }

    nonisolated static func parseDNSServers(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { NetworkValidation.isIPv4($0) }
    }

    private nonisolated static func shell(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }

}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }
}

enum NetworkError: LocalizedError {
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .applyFailed(let detail): return detail
        }
    }
}
