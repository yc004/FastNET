import Foundation
import FastNETShared
import Security

private final class HelperService: NSObject, FastNETHelperProtocol {
    func applyConfiguration(
        _ encodedRequest: NSData,
        withReply reply: @escaping (Bool, NSString?) -> Void
    ) {
        do {
            let request = try JSONDecoder().decode(
                NetworkConfigurationRequest.self,
                from: encodedRequest as Data
            )
            try Self.validate(request)

            let defaultDNS = request.appendDefaultDNS && !request.dnsServers.isEmpty
                ? Self.readDefaultDNS(interfaceName: request.interfaceName, fallbackRouter: request.router)
                : []

            if request.usesDHCP {
                try Self.runNetworkSetup(["-setdhcp", request.serviceName])
            } else {
                try Self.runNetworkSetup([
                    "-setmanual", request.serviceName, request.ipAddress,
                    request.subnetMask, request.router
                ])
            }

            let dnsServers = DNSList.merging(primary: request.dnsServers, defaults: defaultDNS)
            let dnsArguments = dnsServers.isEmpty
                ? ["-setdnsservers", request.serviceName, "Empty"]
                : ["-setdnsservers", request.serviceName] + dnsServers
            try Self.runNetworkSetup(dnsArguments)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription as NSString)
        }
    }

    private static func validate(_ request: NetworkConfigurationRequest) throws {
        let services = try runNetworkSetup(["-listallnetworkservices"])
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("An asterisk") }
            .map { $0.hasPrefix("*") ? String($0.dropFirst()) : $0 }
        guard services.contains(request.serviceName) else {
            throw HelperError.invalidRequest("网络服务不存在")
        }
        guard request.serviceName.count <= 128, request.dnsServers.count <= 8 else {
            throw HelperError.invalidRequest("配置内容超出限制")
        }
        if !request.usesDHCP {
            guard isIPv4(request.ipAddress), isIPv4(request.subnetMask), isIPv4(request.router) else {
                throw HelperError.invalidRequest("静态 IPv4 配置无效")
            }
        }
        guard request.dnsServers.allSatisfy(isIPv4) else {
            throw HelperError.invalidRequest("DNS 地址无效")
        }

        let hardware = try runNetworkSetup(["-listallhardwareports"])
        let devices = hardware.split(separator: "\n").compactMap { line -> String? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("Device:") else { return nil }
            return value.replacingOccurrences(of: "Device:", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        guard devices.contains(request.interfaceName) else {
            throw HelperError.invalidRequest("网络接口不存在")
        }
    }

    private static func readDefaultDNS(interfaceName: String, fallbackRouter: String) -> [String] {
        let packet = (try? run("/usr/sbin/ipconfig", ["getpacket", interfaceName])) ?? ""
        let packetDNS = packet.split(separator: "\n").first { $0.contains("domain_name_server") }
            .map(String.init)
            .flatMap { line -> [String]? in
                guard let open = line.firstIndex(of: "{"), let close = line.firstIndex(of: "}") else { return nil }
                return line[line.index(after: open)..<close]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter(isIPv4)
            } ?? []
        if !packetDNS.isEmpty { return packetDNS }
        return isIPv4(fallbackRouter) ? [fallbackRouter] : []
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { (0...255).contains($0) } == true
        }
    }

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        try run("/usr/sbin/networksetup", arguments)
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw HelperError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard ClientValidator.isFastNET(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: FastNETHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

private enum ClientValidator {
    static func isFastNET(_ connection: NSXPCConnection) -> Bool {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)]
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest) == errSecSuccess,
              let guest else { return false }

        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == "com.fastnet.utility",
              let executable = values[kSecCodeInfoMainExecutable as String] as? URL else { return false }

        guard let helperURL = ownExecutableURL() else { return false }
        let expectedApp = helperURL.deletingLastPathComponent().appendingPathComponent("FastNET").standardizedFileURL
        guard executable.standardizedFileURL == expectedApp else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            "identifier \"com.fastnet.utility\"" as CFString,
            [],
            &requirement
        ) == errSecSuccess, let requirement else { return false }
        return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
    }

    private static func ownExecutableURL() -> URL? {
        var ownCode: SecCode?
        var ownStaticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess,
              let ownCode,
              SecCodeCopyStaticCode(ownCode, [], &ownStaticCode) == errSecSuccess,
              let ownStaticCode,
              SecCodeCopySigningInformation(ownStaticCode, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              let executable = values[kSecCodeInfoMainExecutable as String] as? URL else { return nil }
        return executable.standardizedFileURL
    }
}

private enum HelperError: LocalizedError {
    case invalidRequest(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .commandFailed(let message): return message.isEmpty ? "修改网络设置失败" : message
        }
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: FastNETHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
