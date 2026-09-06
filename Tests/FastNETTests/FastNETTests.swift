import Foundation
import AppKit
import CoreLocation
import Testing
import FastNETShared
@testable import FastNET

@Test func parsesCurrentSSID() {
    #expect(NetworkController.parseSSID("Current Wi-Fi Network: Studio 5G\n") == "Studio 5G")
    #expect(NetworkController.parseSSID("You are not associated with an AirPort network.\n") == nil)
}

@Test func parsesWiFiDevice() {
    let output = """
    Hardware Port: Wi-Fi
    Device: en1
    Ethernet Address: 00:00:00:00:00:00

    Hardware Port: Thunderbolt Bridge
    Device: bridge0
    """
    let result = NetworkController.parseWiFiHardware(output)
    #expect(result.0 == "Wi-Fi")
    #expect(result.1 == "en1")
}

@Test func validatesProfiles() {
    let good = WiFiProfile(ssid: "Office", ipv4Mode: .manual, ipAddress: "192.168.1.20", subnetMask: "255.255.255.0", router: "192.168.1.1", dnsServers: ["1.1.1.1"])
    #expect(NetworkValidation.validate(good) == nil)
    var bad = good
    bad.ipAddress = "999.1.1.1"
    #expect(NetworkValidation.validate(bad) != nil)
}

@Test func parsesRenamedWiFiService() {
    let output = """
    An asterisk (*) denotes that a network service is disabled.
    (1) Office Wireless
    (Hardware Port: Wi-Fi, Device: en1)
    """
    #expect(NetworkController.parseWiFiService(output, device: "en1") == "Office Wireless")
}

@Test func distinguishesHiddenSSIDFromDisconnection() {
    let connectedButHidden = NetworkSnapshot(
        ssid: nil,
        interfaceName: "en0",
        serviceName: "Wi-Fi",
        ipAddress: "192.168.43.4"
    )
    #expect(connectedButHidden.isConnected)
    #expect(!NetworkSnapshot.disconnected.isConnected)
}

@MainActor
@Test func newProfileIsImmediatelyInsertedIntoSidebarData() {
    let suiteName = "FastNETTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ProfileStore(defaults: defaults)

    let created = store.createProfile(suggestedSSID: "Office Wi-Fi")

    #expect(store.profiles.contains(where: { $0.id == created.id }))
    #expect(store.profiles(for: "Office Wi-Fi").contains(created))
}

@MainActor
@Test func allowsMultipleProfilesButOnlyOneAutomaticProfilePerSSID() {
    let suiteName = "FastNETTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ProfileStore(defaults: defaults)

    var office = WiFiProfile(ssid: "Office", note: "办公 DHCP", isAutoApply: true)
    store.upsert(office)
    var development = WiFiProfile(
        ssid: "Office",
        note: "开发板静态地址",
        ipv4Mode: .manual,
        ipAddress: "192.168.1.20",
        subnetMask: "255.255.255.0",
        router: "192.168.1.1",
        isAutoApply: true
    )
    store.upsert(development)

    #expect(store.profiles(for: "Office").count == 2)
    #expect(store.automaticProfile(for: "Office")?.id == development.id)
    #expect(store.profiles(for: "Office").filter(\.isAutoApply).count == 1)

    office.note = "手动备用"
    development.note = "开发环境"
    #expect(development.displayName == "开发环境")
}

@Test func migratesLegacyProfileWithoutNote() throws {
    let legacy = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "ssid": "Legacy Wi-Fi",
      "ipv4Mode": "dhcp",
      "ipAddress": "",
      "subnetMask": "255.255.255.0",
      "router": "",
      "dnsServers": [],
      "isEnabled": true
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(WiFiProfile.self, from: legacy)
    #expect(profile.note.isEmpty)
    #expect(!profile.appendDefaultDNS)
    #expect(profile.isAutoApply)
}

@Test func appendsDefaultDNSAfterManualServersAndRemovesDuplicates() {
    let result = DNSList.merging(
        primary: ["1.1.1.1", "8.8.8.8"],
        defaults: ["192.168.1.1", "1.1.1.1"]
    )
    #expect(result == ["1.1.1.1", "8.8.8.8", "192.168.1.1"])
}

@Test func menuBarSymbolsExistInTheTargetSDK() {
    #expect(NSImage(systemSymbolName: FastNETSymbol.menuBarConnected, accessibilityDescription: nil) != nil)
    #expect(NSImage(systemSymbolName: FastNETSymbol.menuBarDisconnected, accessibilityDescription: nil) != nil)
}

@Test func menuMarksOnlyTheAppliedProfileOnTheCurrentWiFi() {
    let appliedID = UUID()
    #expect(StatusItemController.isCurrentlyApplied(
        profileID: appliedID,
        profileSSID: "Office",
        currentSSID: "Office",
        lastAppliedProfileID: appliedID
    ))
    #expect(!StatusItemController.isCurrentlyApplied(
        profileID: UUID(),
        profileSSID: "Office",
        currentSSID: "Office",
        lastAppliedProfileID: appliedID
    ))
    #expect(!StatusItemController.isCurrentlyApplied(
        profileID: appliedID,
        profileSSID: "Office",
        currentSSID: "Home",
        lastAppliedProfileID: appliedID
    ))
}

@Test func comparesReleaseVersionsNumerically() {
    #expect(VersionComparison.isNewer("v1.9.0", than: "1.8.0"))
    #expect(VersionComparison.isNewer("1.10.0", than: "1.9.9"))
    #expect(!VersionComparison.isNewer("1.8.0", than: "1.8.0"))
    #expect(!VersionComparison.isNewer("1.7.9", than: "1.8.0"))
}

@Test func decodesGitHubReleaseAndFindsTheDMG() throws {
    let payload = """
    {
      "tag_name": "v1.9.0",
      "name": "FastNET 1.9.0",
      "body": "更新说明",
      "html_url": "https://github.com/yc004/FastNET/releases/tag/v1.9.0",
      "assets": [
        {
          "name": "FastNET-1.9.0-macOS.dmg",
          "browser_download_url": "https://example.com/FastNET-1.9.0-macOS.dmg",
          "size": 4096
        }
      ]
    }
    """.data(using: .utf8)!
    let release = try JSONDecoder().decode(FastNETRelease.self, from: payload)
    #expect(release.version == "1.9.0")
    #expect(release.diskImage?.name == "FastNET-1.9.0-macOS.dmg")
}

@Test func parsesCurrentNetworkDetails() {
    let output = """
    DHCP Configuration
    IP address: 192.168.1.23
    Subnet mask: 255.255.255.0
    Router: 192.168.1.1
    """
    let info = NetworkController.parseNetworkInfo(output)
    #expect(info.mode == "DHCP")
    #expect(info.ipAddress == "192.168.1.23")
    #expect(info.subnetMask == "255.255.255.0")
    #expect(info.router == "192.168.1.1")
    #expect(NetworkController.parseDNSServers("1.1.1.1\n8.8.8.8\n") == ["1.1.1.1", "8.8.8.8"])
    #expect(NetworkController.parseDNSServers("There aren't any DNS Servers set on Wi-Fi.\n").isEmpty)
}

@Test func dockIconIsVisibleByDefaultAndCanBeDisabled() {
    let suiteName = "FastNETTests.Dock.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    #expect(DockIconPreference.value(from: defaults))
    defaults.set(false, forKey: DockIconPreference.key)
    #expect(!DockIconPreference.value(from: defaults))
}

@Test func permissionOnboardingReturnsUntilPermissionIsGranted() {
    #expect(PermissionOnboardingPolicy.shouldShow(hasSeenOnboarding: false, authorization: .notDetermined, helperEnabled: false))
    #expect(PermissionOnboardingPolicy.shouldShow(hasSeenOnboarding: true, authorization: .notDetermined, helperEnabled: true))
    #expect(PermissionOnboardingPolicy.shouldShow(hasSeenOnboarding: true, authorization: .denied, helperEnabled: true))
    #expect(PermissionOnboardingPolicy.shouldShow(hasSeenOnboarding: true, authorization: .authorized, helperEnabled: false))
    #expect(!PermissionOnboardingPolicy.shouldShow(hasSeenOnboarding: true, authorization: .authorized, helperEnabled: true))
}
