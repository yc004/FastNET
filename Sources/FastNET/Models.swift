import Foundation

enum IPv4Mode: String, Codable, CaseIterable, Identifiable {
    case dhcp
    case manual

    var id: Self { self }
    var title: String { self == .dhcp ? "自动 (DHCP)" : "手动" }
}

struct WiFiProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var ssid: String
    var note: String
    var ipv4Mode: IPv4Mode
    var ipAddress: String
    var subnetMask: String
    var router: String
    var dnsServers: [String]
    var appendDefaultDNS: Bool
    var isAutoApply: Bool

    init(
        id: UUID = UUID(),
        ssid: String,
        note: String = "",
        ipv4Mode: IPv4Mode = .dhcp,
        ipAddress: String = "",
        subnetMask: String = "255.255.255.0",
        router: String = "",
        dnsServers: [String] = [],
        appendDefaultDNS: Bool = false,
        isAutoApply: Bool = true
    ) {
        self.id = id
        self.ssid = ssid
        self.note = note
        self.ipv4Mode = ipv4Mode
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.router = router
        self.dnsServers = dnsServers
        self.appendDefaultDNS = appendDefaultDNS
        self.isAutoApply = isAutoApply
    }

    private enum CodingKeys: String, CodingKey {
        case id, ssid, note, ipv4Mode, ipAddress, subnetMask, router, dnsServers, appendDefaultDNS, isAutoApply, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ssid = try container.decode(String.self, forKey: .ssid)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        ipv4Mode = try container.decodeIfPresent(IPv4Mode.self, forKey: .ipv4Mode) ?? .dhcp
        ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress) ?? ""
        subnetMask = try container.decodeIfPresent(String.self, forKey: .subnetMask) ?? "255.255.255.0"
        router = try container.decodeIfPresent(String.self, forKey: .router) ?? ""
        dnsServers = try container.decodeIfPresent([String].self, forKey: .dnsServers) ?? []
        appendDefaultDNS = try container.decodeIfPresent(Bool.self, forKey: .appendDefaultDNS) ?? false
        isAutoApply = try container.decodeIfPresent(Bool.self, forKey: .isAutoApply)
            ?? container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ssid, forKey: .ssid)
        try container.encode(note, forKey: .note)
        try container.encode(ipv4Mode, forKey: .ipv4Mode)
        try container.encode(ipAddress, forKey: .ipAddress)
        try container.encode(subnetMask, forKey: .subnetMask)
        try container.encode(router, forKey: .router)
        try container.encode(dnsServers, forKey: .dnsServers)
        try container.encode(appendDefaultDNS, forKey: .appendDefaultDNS)
        try container.encode(isAutoApply, forKey: .isAutoApply)
    }

    var dnsDisplay: String {
        if dnsServers.isEmpty { return "自动获取 DNS" }
        let suffix = appendDefaultDNS ? " · + 默认 DNS" : ""
        return dnsServers.joined(separator: " · ") + suffix
    }

    var displayName: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ipv4Mode == .dhcp ? "DHCP 配置" : (ipAddress.isEmpty ? "静态 IP 配置" : ipAddress)
    }
}

struct NetworkSnapshot: Equatable {
    var ssid: String?
    var interfaceName: String
    var serviceName: String
    var ipAddress: String?
    var subnetMask: String? = nil
    var router: String? = nil
    var dnsServers: [String] = []
    var configurationMode: String? = nil

    /// SSID may be hidden by macOS until Location permission is granted.
    /// An assigned interface address still proves that Wi-Fi is connected.
    var isConnected: Bool { ssid != nil || ipAddress != nil }

    static let disconnected = NetworkSnapshot(
        ssid: nil,
        interfaceName: "en0",
        serviceName: "Wi-Fi",
        ipAddress: nil,
        subnetMask: nil,
        router: nil,
        dnsServers: [],
        configurationMode: nil
    )
}

enum ApplyState: Equatable {
    case idle
    case applying
    case success(Date)
    case failure(String)
}

enum NetworkValidation {
    static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }

    static func validate(_ profile: WiFiProfile) -> String? {
        guard !profile.ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Wi‑Fi 名称不能为空"
        }
        if profile.ipv4Mode == .manual {
            guard isIPv4(profile.ipAddress) else { return "请输入有效的 IPv4 地址" }
            guard isIPv4(profile.subnetMask) else { return "请输入有效的子网掩码" }
            guard isIPv4(profile.router) else { return "请输入有效的路由器地址" }
        }
        if let invalidDNS = profile.dnsServers.first(where: { !isIPv4($0) }) {
            return "DNS 地址“\(invalidDNS)”无效"
        }
        return nil
    }
}
