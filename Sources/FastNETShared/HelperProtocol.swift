import Foundation

public enum FastNETHelperConstants {
    public static let machServiceName = "com.fastnet.utility.helper.v2"
    public static let plistName = "com.fastnet.utility.helper.v2.plist"
}

public struct NetworkConfigurationRequest: Codable, Sendable {
    public let serviceName: String
    public let interfaceName: String
    public let usesDHCP: Bool
    public let ipAddress: String
    public let subnetMask: String
    public let router: String
    public let dnsServers: [String]
    public let appendDefaultDNS: Bool

    public init(
        serviceName: String,
        interfaceName: String,
        usesDHCP: Bool,
        ipAddress: String,
        subnetMask: String,
        router: String,
        dnsServers: [String],
        appendDefaultDNS: Bool
    ) {
        self.serviceName = serviceName
        self.interfaceName = interfaceName
        self.usesDHCP = usesDHCP
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.router = router
        self.dnsServers = dnsServers
        self.appendDefaultDNS = appendDefaultDNS
    }
}

public enum DNSList {
    public static func merging(primary: [String], defaults: [String]) -> [String] {
        var seen = Set<String>()
        return (primary + defaults).filter { seen.insert($0).inserted }
    }
}

@objc public protocol FastNETHelperProtocol: NSObjectProtocol {
    func applyConfiguration(
        _ encodedRequest: NSData,
        withReply reply: @escaping (Bool, NSString?) -> Void
    )
}
