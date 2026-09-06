import AppKit
import Foundation

struct FastNETRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        private enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var diskImage: Asset? {
        assets.first { $0.name.localizedCaseInsensitiveCompare("FastNET-\(version)-macOS.dmg") == .orderedSame }
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case available(FastNETRelease)
    case downloading(FastNETRelease)
    case ready(FastNETRelease, URL)
    case upToDate
    case failed(String)
}

enum VersionComparison {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: \.isNumber)) ?? 0
            }
    }
}

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var state: UpdateState = .idle
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: Keys.automaticChecks)
            scheduleChecks()
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet { defaults.set(automaticallyDownloadsUpdates, forKey: Keys.automaticDownloads) }
    }

    private enum Keys {
        static let automaticChecks = "updates.automaticChecks"
        static let automaticDownloads = "updates.automaticDownloads"
        static let lastPromptedVersion = "updates.lastPromptedVersion"
        static let lastPromptedDate = "updates.lastPromptedDate"
    }

    private static let releasesURL = URL(
        string: "https://api.github.com/repos/yc004/FastNET/releases/latest"
    )!
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let promptCooldown: TimeInterval = 12 * 60 * 60

    private let defaults: UserDefaults
    private var timer: Timer?
    private var initialCheckTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.automaticallyChecksForUpdates = defaults.object(forKey: Keys.automaticChecks) as? Bool ?? true
        self.automaticallyDownloadsUpdates = defaults.object(forKey: Keys.automaticDownloads) as? Bool ?? false
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var statusText: String {
        switch state {
        case .idle: return ""
        case .checking: return "正在检查更新…"
        case .available(let release): return "FastNET \(release.version) 可用"
        case .downloading(let release): return "正在后台下载 FastNET \(release.version)…"
        case .ready(let release, _): return "FastNET \(release.version) 已下载"
        case .upToDate: return "当前已是最新版本"
        case .failed(let message): return "检查失败：\(message)"
        }
    }

    func start() {
        scheduleChecks()
        guard automaticallyChecksForUpdates else { return }
        initialCheckTask?.cancel()
        initialCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.checkForUpdates(userInitiated: false)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        initialCheckTask?.cancel()
        operationTask?.cancel()
    }

    func checkForUpdates(userInitiated: Bool = true) {
        guard operationTask == nil else { return }
        state = .checking
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            do {
                let release = try await Self.fetchLatestRelease()
                guard VersionComparison.isNewer(release.version, than: currentVersion) else {
                    state = .upToDate
                    if userInitiated { presentUpToDateAlert() }
                    return
                }
                guard release.diskImage != nil else {
                    throw UpdateError.missingDiskImage
                }
                state = .available(release)
                if automaticallyDownloadsUpdates {
                    try await download(release)
                } else if userInitiated || shouldPresent(release) {
                    if presentAvailableAlert(release) {
                        try await download(release)
                    }
                }
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
                if userInitiated { presentErrorAlert(error.localizedDescription) }
            }
        }
    }

    func presentCurrentUpdate() {
        switch state {
        case .available(let release):
            if presentAvailableAlert(release) { beginDownload(release) }
        case .ready(let release, let url):
            presentReadyAlert(release, fileURL: url)
        default:
            checkForUpdates()
        }
    }

    private func scheduleChecks() {
        timer?.invalidate()
        timer = nil
        guard automaticallyChecksForUpdates else { return }
        let nextTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in UpdateService.shared.checkForUpdates(userInitiated: false) }
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    private func beginDownload(_ release: FastNETRelease) {
        guard operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { operationTask = nil }
            do {
                try await download(release)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
                presentErrorAlert(error.localizedDescription)
            }
        }
    }

    private static func fetchLatestRelease() async throws -> FastNETRelease {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FastNET-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        return try JSONDecoder().decode(FastNETRelease.self, from: data)
    }

    private func download(_ release: FastNETRelease) async throws {
        guard let asset = release.diskImage else { throw UpdateError.missingDiskImage }
        state = .downloading(release)
        var request = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 180)
        request.setValue("FastNET-Updater", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }

        let directory = try updateDirectory()
        let destination = directory.appendingPathComponent(asset.name, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        state = .ready(release, destination)
        presentReadyAlert(release, fileURL: destination)
    }

    private func updateDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("FastNET/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func shouldPresent(_ release: FastNETRelease) -> Bool {
        let previousVersion = defaults.string(forKey: Keys.lastPromptedVersion)
        let previousDate = defaults.object(forKey: Keys.lastPromptedDate) as? Date
        guard previousVersion == release.version, let previousDate else { return true }
        return Date().timeIntervalSince(previousDate) >= Self.promptCooldown
    }

    private func recordPrompt(_ release: FastNETRelease) {
        defaults.set(release.version, forKey: Keys.lastPromptedVersion)
        defaults.set(Date(), forKey: Keys.lastPromptedDate)
    }

    @discardableResult
    private func presentAvailableAlert(_ release: FastNETRelease) -> Bool {
        recordPrompt(release)
        let alert = updateAlert(
            title: "FastNET \(release.version) 可用",
            message: releaseNotes(release),
            primaryButton: "下载并更新",
            secondaryButton: "稍后"
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentReadyAlert(_ release: FastNETRelease, fileURL: URL) {
        recordPrompt(release)
        let alert = updateAlert(
            title: "FastNET \(release.version) 已下载",
            message: "更新安装镜像已准备好。打开后运行安装器即可完成更新。",
            primaryButton: "打开安装镜像",
            secondaryButton: "稍后"
        )
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fileURL)
        }
    }

    private func presentUpToDateAlert() {
        _ = updateAlert(
            title: "FastNET 已是最新版本",
            message: "当前版本为 \(currentVersion)。",
            primaryButton: "好"
        ).runModal()
    }

    private func presentErrorAlert(_ message: String) {
        _ = updateAlert(
            title: "无法检查更新",
            message: message,
            primaryButton: "好"
        ).runModal()
    }

    private func updateAlert(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String? = nil
    ) -> NSAlert {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApplication.shared.applicationIconImage
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton { alert.addButton(withTitle: secondaryButton) }
        return alert
    }

    private func releaseNotes(_ release: FastNETRelease) -> String {
        let notes = release.body?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(600)
        guard let notes, !notes.isEmpty else {
            return "GitHub 已发布 FastNET 的新版本。"
        }
        return String(notes)
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case missingDiskImage

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub 返回了无效的更新信息，请稍后重试。"
        case .missingDiskImage: return "这个版本没有可用的 macOS DMG 安装镜像。"
        }
    }
}
