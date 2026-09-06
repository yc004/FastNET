import SwiftUI

struct ProfilesWindow: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var network: NetworkController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSSID: String?
    @State private var selection: UUID?
    @State private var draft: WiFiProfile?

    private var networkNames: [String] {
        var names = Set(store.ssids)
        if let current = network.snapshot.ssid { names.insert(current) }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var selectedProfiles: [WiFiProfile] {
        store.profiles(for: selectedSSID)
    }

    private var ssidChoices: [String] {
        var values = Set(store.ssids)
        values.formUnion(network.availableSSIDs)
        if let current = network.snapshot.ssid { values.insert(current) }
        if let draft, !draft.ssid.isEmpty { values.insert(draft.ssid) }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            List(networkNames, id: \.self, selection: $selectedSSID) { ssid in
                NetworkListRow(
                    ssid: ssid,
                    profileCount: store.profiles(for: ssid).count,
                    isCurrent: ssid == network.snapshot.ssid
                )
                .tag(ssid)
            }
            .navigationTitle("网络")
            .navigationSplitViewColumnWidth(min: 165, ideal: 190, max: 250)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: networkNames)
        } content: {
            List(selection: $selection) {
                if selectedProfiles.isEmpty {
                    ContentUnavailableView(
                        "没有配置文件",
                        systemImage: FastNETSymbol.profile,
                        description: Text("点击下方 + 新建配置")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(selectedProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isCurrentNetwork: profile.ssid == network.snapshot.ssid,
                            activity: activity(for: profile)
                        )
                            .tag(profile.id)
                    }
                }
            }
            .navigationTitle(selectedSSID ?? "配置文件")
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: store.profiles)
            .navigationSplitViewColumnWidth(min: 205, ideal: 235, max: 310)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 4) {
                    Button { addProfile() } label: { Image(systemName: "plus") }
                        .help("新建配置")
                    Button { removeSelection() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                        .help("删除所选配置")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        } detail: {
            VStack(spacing: 0) {
                CurrentNetworkInfoView(snapshot: network.snapshot)
                Divider()

                if let draft {
                    ProfileEditor(
                        profile: Binding(get: { draft }, set: { self.draft = $0 }),
                        ssidChoices: ssidChoices,
                        isCurrentNetwork: draft.ssid == network.snapshot.ssid,
                        onSave: saveDraft,
                        onApply: {
                            saveDraft()
                            network.apply(draft)
                        }
                    )
                    .id(draft.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: FastNETSymbol.connected)
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("选择一个网络配置")
                            .font(.title3.weight(.semibold))
                        Text("或点按左下角 + 创建新配置")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            network.start()
            if let current = store.automaticProfile(for: network.snapshot.ssid)
                ?? store.profiles(for: network.snapshot.ssid).first {
                selectedSSID = current.ssid
                selection = current.id
            } else if let first = store.profiles.first {
                selectedSSID = first.ssid
                selection = first.id
            } else {
                selectedSSID = network.snapshot.ssid
            }
            syncDraft()
        }
        .onChange(of: selectedSSID) { _, newSSID in
            guard let newSSID else {
                selection = nil
                syncDraft()
                return
            }
            if !store.profiles(for: newSSID).contains(where: { $0.id == selection }) {
                selection = store.automaticProfile(for: newSSID)?.id
                    ?? store.profiles(for: newSSID).first?.id
            }
            syncDraft()
        }
        .onChange(of: selection) { _, newID in
            if let newID, let profile = store.profiles.first(where: { $0.id == newID }) {
                selectedSSID = profile.ssid
            }
            syncDraft()
        }
        .onChange(of: store.lastCreatedProfileID) { _, newID in
            guard let newID, let profile = store.profiles.first(where: { $0.id == newID }) else { return }
            selectedSSID = profile.ssid
            selection = newID
            syncDraft()
        }
        .onChange(of: network.snapshot.ssid) { _, newSSID in
            if selectedSSID == nil { selectedSSID = newSSID }
        }
        .frame(minWidth: 860, minHeight: 520)
    }

    private func syncDraft() {
        if let selection, let profile = store.profiles.first(where: { $0.id == selection }) {
            draft = profile
        } else if draft?.id != selection {
            draft = nil
        }
    }

    private func activity(for profile: WiFiProfile) -> ProfileActivity {
        if network.applyProfileID == profile.id {
            switch network.applyState {
            case .applying: return .applying
            case .failure: return .failed
            case .success where network.lastAppliedProfileID == profile.id: return .applied
            case .idle, .success: break
            }
        }
        if network.lastAppliedProfileID == profile.id,
           network.snapshot.ssid == profile.ssid {
            return .applied
        }
        return .none
    }

    private func addProfile() {
        let profile = store.createProfile(suggestedSSID: selectedSSID ?? network.snapshot.ssid)
        draft = profile
        selectedSSID = profile.ssid
        selection = profile.id
    }

    private func saveDraft() {
        guard let draft, NetworkValidation.validate(draft) == nil else { return }
        store.upsert(draft)
        selectedSSID = draft.ssid
        selection = draft.id
    }

    private func removeSelection() {
        guard let selection, let profile = store.profiles.first(where: { $0.id == selection }) else {
            draft = nil
            self.selection = nil
            return
        }
        let removedSSID = profile.ssid
        store.remove(profile)
        if let next = store.profiles(for: removedSSID).first {
            self.selection = next.id
        } else {
            selectedSSID = networkNames.first
            self.selection = store.profiles(for: selectedSSID).first?.id
        }
        syncDraft()
    }
}

private struct NetworkListRow: View {
    let ssid: String
    let profileCount: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "wifi.circle.fill" : "wifi.circle")
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(ssid).lineLimit(1)
                if isCurrent {
                    Text("当前网络").font(.caption2).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 4)
            Text("\(profileCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 3)
    }
}

private struct CurrentNetworkInfoView: View {
    let snapshot: NetworkSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var networkName: String {
        snapshot.ssid ?? (snapshot.isConnected ? "Wi‑Fi 已连接（名称不可用）" : "未连接 Wi‑Fi")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: snapshot.isConnected ? FastNETSymbol.connected : FastNETSymbol.disconnected)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(snapshot.isConnected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: snapshot.ssid)
                VStack(alignment: .leading, spacing: 1) {
                    Text("当前网络").font(.caption).foregroundStyle(.secondary)
                    Text(networkName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(snapshot.isConnected ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(snapshot.isConnected ? 1 : 0.72)
                    .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.35), value: snapshot.isConnected)
            }

            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                GridRow {
                    NetworkInfoItem(title: "IPv4", value: snapshot.ipAddress ?? "—")
                    NetworkInfoItem(title: "子网掩码", value: snapshot.subnetMask ?? "—")
                    NetworkInfoItem(title: "路由器", value: snapshot.router ?? "—")
                }
                GridRow {
                    NetworkInfoItem(title: "DNS", value: snapshot.dnsServers.isEmpty ? "自动获取" : snapshot.dnsServers.joined(separator: ", "))
                        .gridCellColumns(2)
                    NetworkInfoItem(title: "服务", value: "\(snapshot.serviceName) · \(snapshot.configurationMode ?? snapshot.interfaceName)")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: snapshot)
    }
}

private struct NetworkInfoItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .contentTransition(.interpolate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProfileActivity: Equatable {
    case none
    case applying
    case applied
    case failed
}

private struct ProfileListRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: WiFiProfile
    let isCurrentNetwork: Bool
    let activity: ProfileActivity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: FastNETSymbol.connected)
                .foregroundStyle(isCurrentNetwork ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(profile.displayName).lineLimit(1)
                    if profile.isAutoApply {
                        Image(systemName: FastNETSymbol.automatic)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    Text(profile.ipv4Mode == .dhcp ? "DHCP" : profile.ipAddress)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    activityLabel
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: activity)
    }

    @ViewBuilder
    private var activityLabel: some View {
        switch activity {
        case .none:
            EmptyView()
        case .applying:
            ProfileActivityBadge(
                title: "应用中",
                color: Color.accentColor,
                showsProgress: true
            )
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        case .applied:
            ProfileActivityBadge(
                title: "已应用",
                symbol: "checkmark",
                color: .green
            )
                .symbolEffect(.bounce, value: activity)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        case .failed:
            ProfileActivityBadge(
                title: "失败",
                symbol: "exclamationmark",
                color: .red
            )
                .symbolEffect(.pulse, value: activity)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }
}

private struct ProfileActivityBadge: View {
    let title: String
    var symbol: String?
    let color: Color
    var showsProgress = false

    var body: some View {
        HStack(spacing: 3) {
            if showsProgress {
                ProgressView().controlSize(.mini)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.11), in: Capsule())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ProfileEditor: View {
    @EnvironmentObject private var network: NetworkController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var profile: WiFiProfile
    let ssidChoices: [String]
    let isCurrentNetwork: Bool
    let onSave: () -> Void
    let onApply: () -> Void
    @State private var dnsText = ""
    @State private var didSave = false

    private var validationMessage: String? { NetworkValidation.validate(profile) }
    private var showsApplyStatus: Bool { network.applyProfileID == profile.id }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 13) {
                    Image(systemName: FastNETSymbol.networkProfile)
                        .font(.system(size: 38))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.title2.weight(.semibold))
                        Text(isCurrentNetwork ? "当前已连接" : "Wi‑Fi 专属网络配置")
                            .font(.caption)
                            .foregroundStyle(isCurrentNetwork ? .green : .secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if didSave || showsApplyStatus {
                Section {
                    feedbackView
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Section("配置资料") {
                TextField("备注", text: $profile.note, prompt: Text("例如：公司开发环境、备用 DNS"))
                Picker("应用到 Wi‑Fi", selection: $profile.ssid) {
                    ForEach(ssidChoices, id: \.self) { ssid in
                        Text(ssid).tag(ssid)
                    }
                }
                TextField("SSID", text: $profile.ssid, prompt: Text("也可以手动输入 Wi‑Fi 名称"))
                Text("下拉列表包含当前网络、系统已保存的网络和已有配置中的 SSID。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("配置 IPv4", selection: $profile.ipv4Mode) {
                    ForEach(IPv4Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                if profile.ipv4Mode == .manual {
                    TextField("IP 地址", text: $profile.ipAddress)
                    TextField("子网掩码", text: $profile.subnetMask)
                    TextField("路由器", text: $profile.router)
                }
            } header: {
                Label(
                    "IPv4",
                    systemImage: profile.ipv4Mode == .dhcp ? FastNETSymbol.automatic : FastNETSymbol.manualIPv4
                )
            }

            Section {
                TextField("DNS 服务器", text: $dnsText, prompt: Text("例如 1.1.1.1, 8.8.8.8"))
                    .onChange(of: dnsText) { _, newValue in
                        profile.dnsServers = newValue
                            .components(separatedBy: CharacterSet(charactersIn: ",， \n"))
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                Text("留空时自动获取 DNS；多个地址可用逗号或空格分隔。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("在手动 DNS 后附加默认 DNS", isOn: $profile.appendDefaultDNS)
                    .disabled(profile.dnsServers.isEmpty)
                Text("默认 DNS 优先读取路由器通过 DHCP 提供的地址；静态网络无法读取时使用路由器地址。重复地址会自动移除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("DNS", systemImage: FastNETSymbol.dns)
            }

            Section {
                Toggle("连接此 Wi‑Fi 时自动应用", isOn: $profile.isAutoApply)
                Text(profile.isAutoApply
                    ? "保存后，此 SSID 的其他配置将改为仅手动应用。"
                    : "此配置只会在您从菜单中选择时应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: FastNETSymbol.warning)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("网络配置")
        .toolbar {
            ToolbarItemGroup {
                Button(didSave ? "已保存" : "保存", action: saveWithFeedback)
                    .disabled(validationMessage != nil)
                Button(action: applyWithFeedback) {
                    if showsApplyStatus && network.applyState == .applying {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在应用…")
                        }
                    } else if showsApplyStatus, case .success = network.applyState {
                        Label("已应用", systemImage: "checkmark")
                    } else {
                        Text("保存并应用")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationMessage != nil || !isCurrentNetwork || network.applyState == .applying)
            }
        }
        .onAppear { dnsText = profile.dnsServers.joined(separator: ", ") }
        .onChange(of: profile) { _, _ in
            didSave = false
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: didSave)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: network.applyState)
    }

    @ViewBuilder
    private var feedbackView: some View {
        if showsApplyStatus {
            switch network.applyState {
            case .applying:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("正在应用 IP 和 DNS 配置…")
                }
                .foregroundStyle(.secondary)
            case .success:
                AnimatedFeedbackRow(
                    symbol: "checkmark.circle.fill",
                    text: "配置已成功应用",
                    color: .green,
                    trigger: network.applyState
                )
            case .failure(let message):
                AnimatedFeedbackRow(
                    symbol: FastNETSymbol.warning,
                    text: "应用失败：\(message)",
                    color: .red,
                    trigger: network.applyState
                )
            case .idle:
                if didSave { savedLabel }
            }
        } else if didSave {
            savedLabel
        }
    }

    private var savedLabel: some View {
        AnimatedFeedbackRow(
            symbol: "checkmark.circle.fill",
            text: "配置已保存",
            color: .green,
            trigger: didSave
        )
    }

    private func saveWithFeedback() {
        onSave()
        didSave = true
    }

    private func applyWithFeedback() {
        didSave = false
        network.clearStatus()
        onApply()
    }
}

private struct AnimatedFeedbackRow<Trigger: Equatable>: View {
    let symbol: String
    let text: String
    let color: Color
    let trigger: Trigger

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolEffect(.bounce, value: trigger)
            Text(text)
        }
        .foregroundStyle(color)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            Toggle("连接 Wi‑Fi 后自动切换网络配置", isOn: $store.autoSwitchEnabled)
            Text("FastNET 仅在 Wi‑Fi 发生变化时应用匹配的配置。首次启用辅助服务后，切换配置不再重复要求密码。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 150)
    }
}
