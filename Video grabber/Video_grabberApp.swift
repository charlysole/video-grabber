import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AppKit
import Combine
import Darwin
import UserNotifications
import Quartz

// MARK: - AppDelegate (macOS Service)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc func downloadURL(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urlString = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL),
              !urlString.isEmpty else { return }
        DispatchQueue.main.async {
            let vm = DownloaderViewModel.shared
            vm.stagedURLs.append(StagedURL(urlString: urlString))
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Quick Look

final class QuickLookPanelController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPanelController()
    var currentURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { currentURL != nil ? 1 : 0 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        currentURL as QLPreviewItem?
    }
}

@main
struct VideoDownloaderMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .frame(minWidth: 1240, minHeight: 800)
        }
        Settings {
            PreferencesView(vm: DownloaderViewModel.shared)
                .fixedSize()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Video Grabber") {
                    NSApp.orderFrontStandardAboutPanel([
                        NSApplication.AboutPanelOptionKey.applicationName: "Video Grabber",
                        NSApplication.AboutPanelOptionKey.applicationVersion:
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        NSApplication.AboutPanelOptionKey.version:
                            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    ])
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Check for Updates…") {
                    UpdateChecker.shared.checkManually()
                }
                Button("Make a Donation") {
                    NSWorkspace.shared.open(URL(string: "https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD")!)
                }
            }
        }
    }
}

// MARK: - Shell

struct AppShellView: View {
    @StateObject private var vm = DownloaderViewModel.shared
    @AppStorage("hideWelcomeModal") private var hideWelcomeModal = false

    var body: some View {
        ContentView(vm: vm)
            .onAppear {
                if !hideWelcomeModal {
                    vm.showWelcomeModal = true
                }
                vm.requestNotificationPermission()
                UpdateChecker.shared.checkSilently()
            }
            .sheet(isPresented: $vm.showWelcomeModal) {
                WelcomeView(isPresented: $vm.showWelcomeModal)
            }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Binding var isPresented: Bool
    @AppStorage("hideWelcomeModal") private var hideWelcomeModal = false
    @State private var dontShowAgain = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("welcome_title", comment: "Welcome screen title"))
                        .font(.title.bold())

                    Text(NSLocalizedString("welcome_subtitle", comment: "Welcome screen subtitle"))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("welcome_body_1", comment: "Welcome body line 1"))
                Text(NSLocalizedString("welcome_body_2", comment: "Welcome body line 2"))
            }
            .font(.body)

            Toggle(NSLocalizedString("welcome_dont_show_again", comment: "Toggle: don't show again"), isOn: $dontShowAgain)

            HStack {
                Spacer()

                Button(NSLocalizedString("welcome_open_settings", comment: "Button: open settings")) {
                    hideWelcomeModal = dontShowAgain
                    openSettings()
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button(NSLocalizedString("welcome_continue", comment: "Button: continue")) {
                    hideWelcomeModal = dontShowAgain
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Models

struct DownloadPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let domains: [String]
    let ytDlpArgs: [String]
    let supportsAudioFallback: Bool
    let suggestsInspector: Bool

    static let general = DownloadPreset(
        name: "General / Auto",
        description: "Modo general con compatibilidad amplia.",
        domains: [],
        ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
        supportsAudioFallback: true,
        suggestsInspector: false
    )
}

struct DownloadHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let sourceURL: String
    let presetName: String
    let destinationPath: String
    let outputFile: String
    let status: String
}

// Video format for quality selection
struct VideoFormat: Identifiable, Hashable {
    let id: String       // format_id
    let label: String    // human-readable description
    let ext: String
    let resolution: String
    let filesize: Int64?
}

// Playlist entry for multi-select
struct PlaylistEntry: Identifiable, Hashable {
    let id: String       // playlist index or video id
    let title: String
    let url: String
    let thumbnailURL: String?
    var selected: Bool = true
}

struct DownloadJob: Identifiable, Equatable {
    enum Status: String, Codable {
        case queued = "En cola"
        case running = "Descargando"
        case paused = "Pausado"
        case finished = "Completado"
        case failed = "Error"
        case cancelled = "Cancelado"
        case scheduled = "Programado"
        case compressing = "Comprimiendo"

        var localizedLabel: String {
            NSLocalizedString(rawValue, comment: "Job status label")
        }
    }

    let id = UUID()
    var createdAt = Date()
    var sourceURL: String
    var presetName: String
    var destinationFolder: URL
    var status: Status = .queued
    var progressLine: String = "Esperando..."
    var outputFile: String = ""
    var log: String = ""
    var forceNoMP4: Bool = false
    var extractAudioOnlyAsMP3: Bool = false
    var progressPercent: Double?
    var speedText: String = ""
    var etaText: String = ""
    var errorSummary: String = ""
    // New fields
    var thumbnailURL: String? = nil
    var selectedFormat: String? = nil   // format_id for quality selection
    var scheduledAt: Date? = nil        // if set and status == .scheduled, wait until this time
    var downloadSubtitles: Bool = false
    var processPID: Int32? = nil        // for pause/resume via SIGSTOP/SIGCONT
    var targetFileSizeMB: Double? = nil // if set, compress after download to this size
    var verifyIntegrity: Bool = false
    var trimStart: String = ""
    var trimEnd: String = ""
    var convertToFormat: String = ""
    var integrityStatus: String = ""    // "", "ok", "corrupt", "unchecked"
    var mediaInfo: String = ""          // e.g. "1080p · 128 kbps"
}

struct DependencyStatus {
    var ytDlpPath: String?
    var ffmpegPath: String?
    var handBrakeInstalled: Bool

    var hasCoreTools: Bool {
        ytDlpPath != nil && ffmpegPath != nil
    }
}

enum DependencyKind: String, CaseIterable, Identifiable {
    case ytDlp
    case ffmpeg
    case handBrake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "ffmpeg"
        case .handBrake: return NSLocalizedString("dep_handbrake_title", comment: "HandBrake dependency name with optional label")
        }
    }

    var supportsUpdate: Bool { false }
}

struct DependencyInstallState {
    var isInstalled: Bool = false
    var resolvedPath: String?
    var isInstalling: Bool = false
    var statusText: String = ""
    var log: String = ""
    var installedVersion: String? = nil
    var latestVersion: String? = nil
    var isCheckingVersion: Bool = false

    var updateAvailable: Bool {
        guard let installed = installedVersion,
              let latest = latestVersion,
              !installed.isEmpty, !latest.isEmpty else { return false }
        return installed != latest
    }
}

// MARK: - Presets

extension DownloadPreset {
    static let all: [DownloadPreset] = [
        .general,
        .init(
            name: "YouTube",
            description: "Videos y playlists de YouTube.",
            domains: ["youtube.com", "youtu.be"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--yes-playlist", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: false
        ),
        .init(
            name: "Facebook",
            description: "Videos públicos de Facebook.",
            domains: ["facebook.com", "fb.watch"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: false
        ),
        .init(
            name: "Vimeo",
            description: "Videos de Vimeo y reproductores embebidos.",
            domains: ["vimeo.com", "player.vimeo.com"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: false
        ),
        .init(
            name: "X / Twitter",
            description: "Videos públicos en X/Twitter.",
            domains: ["x.com", "twitter.com"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: false
        ),
        .init(
            name: "Instagram",
            description: "Reels y publicaciones públicas.",
            domains: ["instagram.com"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: false
        ),
        .init(
            name: "M3U8 / Streaming",
            description: "Usar con URL .m3u8 directa.",
            domains: ["m3u8"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: true
        ),
        .init(
            name: "Frame.io (URL directa)",
            description: "Usar con la URL directa del archivo, no con la página si está protegida.",
            domains: ["frame.io", "app.frame.io"],
            ytDlpArgs: ["--merge-output-format", "mp4", "--newline", "--progress", "--no-simulate"],
            supportsAudioFallback: true,
            suggestsInspector: true
        )
    ]
}

// MARK: - StagedURL

struct StagedURL: Identifiable, Equatable {
    let id = UUID()
    var urlString: String
    var autoDetectPlatform: Bool = true
    var selectedPreset: DownloadPreset = DownloadPreset.all.first!
    var extractAudioOnlyAsMP3: Bool = false
    var trimEnabled: Bool = false
    var trimStartH: Int = 0
    var trimStartM: Int = 0
    var trimStartS: Int = 0
    var trimEndH: Int = 0
    var trimEndM: Int = 0
    var trimEndS: Int = 0

    var trimStartForFFmpeg: String {
        let t = trimStartH * 3600 + trimStartM * 60 + trimStartS
        return t == 0 ? "" : "\(t)"
    }

    var trimEndForFFmpeg: String {
        let t = trimEndH * 3600 + trimEndM * 60 + trimEndS
        return t == 0 ? "" : "\(t)"
    }
    var convertToFormat: String = ""
    var downloadSubtitles: Bool = false
    var enableTargetFileSize: Bool = false
    var targetFileSizeMB: Double = 50
    var verifyIntegrity: Bool = false
    var isEditing: Bool = false
}

// MARK: - View Model

@MainActor
final class DownloaderViewModel: ObservableObject {
    static let shared = DownloaderViewModel()

    @Published var pastedURLsText: String = ""
    @Published var stagedURLs: [StagedURL] = []
    @Published var newURLInput: String = ""
    @Published var selectedPreset: DownloadPreset = .general
    @Published var autoDetectPlatform = true
    @Published var downloadSubtitles = false
    @Published var enableTargetFileSize = false
    @Published var targetFileSizeMB: Double = 50
    @Published var destinationFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first! {
        didSet { UserDefaults.standard.set(destinationFolder.path, forKey: "destinationFolderPath") }
    }
    @Published var jobs: [DownloadJob] = []
    @Published var runningCount: Int = 0
    @Published var maxConcurrentDownloads: Int = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads").nonZero ?? 2 {
        didSet { UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }
    @Published var selectedJobID: UUID?
    @Published var logViewerJobID: UUID?
    @Published var dependencyState = "Verificando dependencias..."
    @Published var showWelcomeModal = false
    @Published var history: [DownloadHistoryItem] = []
    @Published var captureM3U8Instructions = false
    @Published var dependencyInstallStates: [DependencyKind: DependencyInstallState] = [:]

    // Quality picker
    @Published var qualityPickerJobID: UUID? = nil
    @Published var availableFormats: [VideoFormat] = []
    @Published var isFetchingFormats: Bool = false

    // Playlist picker
    @Published var playlistPickerURL: String? = nil
    @Published var playlistEntries: [PlaylistEntry] = []
    @Published var isFetchingPlaylist: Bool = false
    @Published var showPlaylistSheet: Bool = false

    // Scheduler
    @Published var schedulerJobID: UUID? = nil
    @Published var showSchedulerSheet: Bool = false
    @Published var scheduledDate: Date = Date().addingTimeInterval(3600)

    // History filters
    @Published var historyFilterStatus: String = "Todos"
    @Published var historyFilterPreset: String = "Todos"
    @Published var historyFilterDateFrom: Date? = nil
    @Published var historyFilterDateTo: Date? = nil

    // New feature properties
    @Published var verifyIntegrity: Bool = false
    @Published var quickLookURL: URL? = nil

    private var runningProcesses: [UUID: Process] = [:]
    private let historyURL: URL
    private var schedulerTimers: [UUID: Timer] = [:]

    // Computed backward-compat helper
    var isRunning: Bool { runningCount > 0 }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VideoGrabber", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.historyURL = appSupport.appendingPathComponent("download-history.json")
        loadHistory()

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        if let savedPath = UserDefaults.standard.string(forKey: "destinationFolderPath") {
            let savedURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedURL.path) {
                self.destinationFolder = savedURL
            } else {
                self.destinationFolder = downloadsURL
            }
        }

        applyBrewShellEnvironmentIfAvailable()
        installBundledBinariesIfNeeded()
    }

    var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    var isUsingDownloadsFolder: Bool {
        destinationFolder.path == downloadsFolder.path
    }

    func resetToDownloadsFolder() {
        destinationFolder = downloadsFolder
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Dock progress

    private func updateDockTile() {
        let active = jobs.filter { $0.status == .running || $0.status == .queued || $0.status == .paused || $0.status == .compressing }.count
        let tile = NSApplication.shared.dockTile
        if active == 0 {
            tile.badgeLabel = nil
        } else {
            let runningJob = jobs.first(where: { $0.status == .running || $0.status == .compressing })
            if let pct = runningJob?.progressPercent {
                tile.badgeLabel = "\(Int(pct))%"
            } else {
                tile.badgeLabel = "\(active)"
            }
        }
        tile.display()
    }

    // MARK: - Dependency management

    private func installBundledBinariesIfNeeded() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let stampKey = "bundledBinariesVersion"
        let installedStamp = UserDefaults.standard.string(forKey: stampKey) ?? ""

        guard installedStamp != appVersion else {
            refreshDependencyState()
            return
        }

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VideoGrabber", isDirectory: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for name in ["yt-dlp", "ffmpeg"] {
                guard let bundledPath = Bundle.main.path(forResource: name, ofType: nil) else { continue }

                // Validate that bundled binary is a real Mach-O (not a placeholder)
                guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: bundledPath)) else { continue }
                let magic = [UInt8](handle.readData(ofLength: 4))
                handle.closeFile()
                let validMagic: [[UInt8]] = [
                    [0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE],
                    [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA]
                ]
                guard validMagic.contains(where: { $0 == magic }) else { continue }

                let destURL = appSupportDir.appendingPathComponent(name)
                let tmp = appSupportDir.appendingPathComponent(".\(name).tmp")

                // Copy to temp first — only replace if copy succeeds
                try? FileManager.default.removeItem(at: tmp)
                do {
                    try FileManager.default.copyItem(atPath: bundledPath, toPath: tmp.path)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
                } catch { continue }

                let xa = Process()
                xa.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xa.arguments = ["-dr", "com.apple.quarantine", tmp.path]
                xa.standardOutput = Pipe(); xa.standardError = Pipe()
                try? xa.run(); xa.waitUntilExit()

                // Atomic replace
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.moveItem(at: tmp, to: destURL)
            }

            DispatchQueue.main.async {
                UserDefaults.standard.set(appVersion, forKey: stampKey)
                self?.refreshDependencyState()
            }
        }
    }

    func refreshDependencyState() {
        let deps = detectDependencies()

        dependencyState = [
            deps.ytDlpPath != nil ? "yt-dlp ✓" : "yt-dlp ✗",
            deps.ffmpegPath != nil ? "ffmpeg ✓" : "ffmpeg ✗",
            deps.handBrakeInstalled ? "HandBrake ✓" : "HandBrake opcional ✗"
        ].joined(separator: "   ·   ")

        preserveInstallFlagsAndUpdateStates(with: deps)
        checkInstalledVersions()
    }

    private func checkInstalledVersions() {
        let deps = detectDependencies()

        // ── yt-dlp ──────────────────────────────────────────────────────────
        if let ytDlpPath = deps.ytDlpPath {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let p = Process()
                let pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: ytDlpPath)
                p.arguments = ["--version"]
                p.standardOutput = pipe
                p.standardError = Pipe()
                let version: String
                do {
                    try p.run(); p.waitUntilExit()
                    version = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                } catch { version = "" }
                DispatchQueue.main.async {
                    self?.dependencyInstallStates[.ytDlp]?.installedVersion = version
                }
            }
        }

        // ── ffmpeg ───────────────────────────────────────────────────────────
        if let ffmpegPath = deps.ffmpegPath {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let p = Process()
                let pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: ffmpegPath)
                p.arguments = ["-version"]
                p.standardOutput = pipe
                p.standardError = Pipe()
                var version = ""
                do {
                    try p.run(); p.waitUntilExit()
                    let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let parts = raw.components(separatedBy: " ")
                    if parts.count >= 3 { version = parts[2] }
                } catch {}
                DispatchQueue.main.async {
                    self?.dependencyInstallStates[.ffmpeg]?.installedVersion = version
                }
            }
        }
    }

    private func preserveInstallFlagsAndUpdateStates(with deps: DependencyStatus) {
        let old = dependencyInstallStates

        dependencyInstallStates[.ytDlp] = DependencyInstallState(
            isInstalled: deps.ytDlpPath != nil,
            resolvedPath: deps.ytDlpPath,
            isInstalling: old[.ytDlp]?.isInstalling ?? false,
            statusText: deps.ytDlpPath != nil ? "Instalado" : ((old[.ytDlp]?.statusText.isEmpty == false) ? old[.ytDlp]!.statusText : "No instalado"),
            log: old[.ytDlp]?.log ?? ""
        )

        dependencyInstallStates[.ffmpeg] = DependencyInstallState(
            isInstalled: deps.ffmpegPath != nil,
            resolvedPath: deps.ffmpegPath,
            isInstalling: old[.ffmpeg]?.isInstalling ?? false,
            statusText: deps.ffmpegPath != nil ? "Instalado" : ((old[.ffmpeg]?.statusText.isEmpty == false) ? old[.ffmpeg]!.statusText : "No instalado"),
            log: old[.ffmpeg]?.log ?? ""
        )

        dependencyInstallStates[.handBrake] = DependencyInstallState(
            isInstalled: deps.handBrakeInstalled,
            resolvedPath: deps.handBrakeInstalled ? "/Applications/HandBrake.app" : nil,
            isInstalling: old[.handBrake]?.isInstalling ?? false,
            statusText: deps.handBrakeInstalled ? "Instalado" : ((old[.handBrake]?.statusText.isEmpty == false) ? old[.handBrake]!.statusText : "No instalado"),
            log: old[.handBrake]?.log ?? ""
        )
    }

    func detectDependencies() -> DependencyStatus {
        DependencyStatus(
            ytDlpPath: binaryPath(candidates: [
                appSupportBinaryPath(name: "yt-dlp"),
                bundledBinaryPath(name: "yt-dlp"),
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp"
            ]) ?? shellWhich("yt-dlp"),
            ffmpegPath: binaryPath(candidates: [
                appSupportBinaryPath(name: "ffmpeg"),
                bundledBinaryPath(name: "ffmpeg"),
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg"
            ]) ?? shellWhich("ffmpeg"),
            handBrakeInstalled: FileManager.default.fileExists(atPath: "/Applications/HandBrake.app")
        )
    }

    private func bundledBinaryPath(name: String) -> String {
        (Bundle.main.resourcePath ?? "") + "/" + name
    }

    private func appSupportBinaryPath(name: String) -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VideoGrabber")
            .appendingPathComponent(name).path
    }

    func installDependency(_ kind: DependencyKind) {
        guard dependencyInstallStates[kind]?.isInstalling != true else { return }
        switch kind {
        case .ytDlp, .ffmpeg: break  // bundled with app, updated via app update
        case .handBrake: installHandBrake()
        }
    }

    private func installHandBrake() {
        updateDependencyState(
            .handBrake,
            isInstalling: false,
            status: "Instalación manual",
            appendLog: "HandBrake no se instala desde brew en esta app.\nAbrí su sitio oficial o copiá la app a /Applications.\n"
        )
        if let url = URL(string: "https://handbrake.fr/downloads.php") {
            NSWorkspace.shared.open(url)
        }
    }

    private func runInstaller(
        shellCommand: String,
        kind: DependencyKind,
        successStatus: String,
        fallbackError: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellCommand]
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.updateDependencyState(kind, appendLog: text)
                self?.updateInstallStatusFromOutput(kind, text: text)
            }
        }

        errHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.updateDependencyState(kind, appendLog: text)
                self?.updateInstallStatusFromOutput(kind, text: text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil

                self?.refreshDependencyState()

                let installedNow = self?.isDependencyInstalled(kind) ?? false
                let ok = proc.terminationStatus == 0 && installedNow

                if ok {
                    self?.updateDependencyState(kind, isInstalling: false, status: successStatus, appendLog: "\n\(successStatus)\n")
                } else {
                    self?.updateDependencyState(kind, isInstalling: false, status: "Error", appendLog: "\n\(fallbackError) Código: \(proc.terminationStatus)\n")
                }

                completion?(ok)
            }
        }

        do {
            try process.run()
        } catch {
            updateDependencyState(kind, isInstalling: false, status: "Error al iniciar", appendLog: "\(error.localizedDescription)\n")
            completion?(false)
        }
    }

    private func updateInstallStatusFromOutput(_ kind: DependencyKind, text: String) {
        let lower = text.lowercased()

        if lower.contains("downloading") || lower.contains("fetching") {
            updateDependencyState(kind, status: "Descargando...")
        } else if lower.contains("pouring") || lower.contains("installing") || lower.contains("linking") || lower.contains("caveats") {
            updateDependencyState(kind, status: "Instalando...")
        } else if lower.contains("already installed") {
            updateDependencyState(kind, status: "Ya estaba instalado")
        }
    }

    private func isDependencyInstalled(_ kind: DependencyKind) -> Bool {
        let deps = detectDependencies()

        switch kind {
        case .ytDlp: return deps.ytDlpPath != nil
        case .ffmpeg: return deps.ffmpegPath != nil
        case .handBrake: return deps.handBrakeInstalled
        }
    }

    private func updateDependencyState(_ kind: DependencyKind, isInstalling: Bool? = nil, status: String? = nil, appendLog: String? = nil) {
        var state = dependencyInstallStates[kind] ?? DependencyInstallState()

        if let isInstalling {
            state.isInstalling = isInstalling
        }
        if let status {
            state.statusText = status
        }
        if let appendLog {
            state.log += appendLog
        }

        dependencyInstallStates[kind] = state
    }

    private func applyBrewShellEnvironmentIfAvailable() {
        guard let brewPath = brewExecutablePath() else { return }
        _ = applyShellEnv(from: brewPath)
    }

    @discardableResult
    private func applyShellEnv(from brewPath: String) -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(shellEscapeForDoubleQuotes(brewPath)) shellenv"]

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return false }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                return false
            }

            applyEnvExports(output)
            return true
        } catch {
            return false
        }
    }

    private func applyEnvExports(_ shellenvOutput: String) {
        let lines = shellenvOutput.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("export ") else { continue }

            let exportLine = String(trimmed.dropFirst("export ".count))
            guard let equalIndex = exportLine.firstIndex(of: "=") else { continue }

            let key = String(exportLine[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(exportLine[exportLine.index(after: equalIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }

            value = value.replacingOccurrences(of: "\\:", with: ":")
            value = value.replacingOccurrences(of: "\\ ", with: " ")

            setenv(key, value, 1)
        }
    }

    // MARK: - Queue management

    func clearDownloadedJobs() {
        jobs.removeAll { $0.status == .finished || $0.status == .failed || $0.status == .cancelled }

        if let selected = selectedJobID, !jobs.contains(where: { $0.id == selected }) {
            selectedJobID = jobs.first?.id
        }

        if let logID = logViewerJobID, !jobs.contains(where: { $0.id == logID }) {
            logViewerJobID = nil
        }
    }

    func clearFinishedAndCancelledJobs() {
        jobs.removeAll { $0.status == .finished || $0.status == .failed || $0.status == .cancelled }

        if let selected = selectedJobID, !jobs.contains(where: { $0.id == selected }) {
            selectedJobID = jobs.first?.id
        }

        if let logID = logViewerJobID, !jobs.contains(where: { $0.id == logID }) {
            logViewerJobID = nil
        }
    }

    func removeJob(jobID: UUID) {
        jobs.removeAll { $0.id == jobID }
        schedulerTimers[jobID]?.invalidate()
        schedulerTimers.removeValue(forKey: jobID)

        if selectedJobID == jobID {
            selectedJobID = jobs.first?.id
        }

        if logViewerJobID == jobID {
            logViewerJobID = nil
        }
    }

    func queueURLs() {
        let urls = normalizeURLs(from: pastedURLsText)
        guard !urls.isEmpty else { return }

        for rawURL in urls {
            let url = cleanVideoURL(rawURL)
            let preset = autoDetectPlatform ? detectPreset(for: url) : selectedPreset

            // Check if it's a playlist URL — if so, trigger playlist fetch
            if isPlaylistURL(url) {
                fetchPlaylistEntries(url: url, preset: preset)
                continue
            }

            var job = DownloadJob(
                sourceURL: url,
                presetName: preset.name,
                destinationFolder: destinationFolder,
                extractAudioOnlyAsMP3: false
            )
            job.downloadSubtitles = downloadSubtitles
            job.targetFileSizeMB = enableTargetFileSize ? targetFileSizeMB : nil
            jobs.insert(job, at: 0)
        }

        pastedURLsText = ""
        runNextIfNeeded()
    }

    // MARK: - Staged URL management

    func addStagedURL() {
        let raw = newURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let urls = raw.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for url in urls {
            stagedURLs.append(StagedURL(urlString: url))
        }
        newURLInput = ""
    }

    func removeStagedURL(id: UUID) {
        stagedURLs.removeAll { $0.id == id }
    }

    func updateStagedURL(_ updated: StagedURL) {
        if let idx = stagedURLs.firstIndex(where: { $0.id == updated.id }) {
            stagedURLs[idx] = updated
        }
    }

    func startStagedURLs() {
        guard !stagedURLs.isEmpty else { return }
        let toStart = stagedURLs
        stagedURLs = []
        for staged in toStart {
            let preset: DownloadPreset
            if staged.autoDetectPlatform {
                preset = detectPreset(for: staged.urlString)
            } else {
                preset = staged.selectedPreset
            }
            let cleanedURL = cleanVideoURL(staged.urlString)
            if isPlaylistURL(cleanedURL) {
                fetchPlaylistEntries(url: cleanedURL, preset: preset)
                continue
            }
            var job = DownloadJob(
                sourceURL: cleanedURL,
                presetName: preset.name,
                destinationFolder: destinationFolder,
                extractAudioOnlyAsMP3: staged.extractAudioOnlyAsMP3
            )
            job.downloadSubtitles = staged.downloadSubtitles
            job.targetFileSizeMB = staged.enableTargetFileSize ? staged.targetFileSizeMB : nil
            job.trimStart = staged.trimEnabled ? staged.trimStartForFFmpeg : ""
            job.trimEnd = staged.trimEnabled ? staged.trimEndForFFmpeg : ""
            job.convertToFormat = staged.extractAudioOnlyAsMP3 ? "" : staged.convertToFormat
            job.verifyIntegrity = staged.verifyIntegrity
            jobs.insert(job, at: 0)
        }
        runNextIfNeeded()
    }

    // Enqueue a single job built externally (used by playlist/quality picker)
    func enqueueJob(_ job: DownloadJob) {
        jobs.insert(job, at: 0)
        runNextIfNeeded()
    }

    func rerun(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if jobs[idx].status == .running { return }

        jobs[idx].status = .queued
        jobs[idx].progressLine = "Esperando..."
        jobs[idx].outputFile = ""
        jobs[idx].log = ""
        jobs[idx].progressPercent = nil
        jobs[idx].speedText = ""
        jobs[idx].etaText = ""
        jobs[idx].errorSummary = ""
        jobs[idx].forceNoMP4 = false
        jobs[idx].createdAt = Date()
        jobs[idx].processPID = nil

        selectedJobID = jobs[idx].id

        if logViewerJobID == jobs[idx].id {
            logViewerJobID = nil
        }

        runNextIfNeeded()
    }

    func runNextIfNeeded() {
        while runningCount < maxConcurrentDownloads {
            guard let index = jobs.lastIndex(where: { $0.status == .queued }) else {
                updateDockTile()
                return
            }
            jobs[index].status = .running
            jobs[index].progressLine = "Iniciando descarga..."
            jobs[index].errorSummary = ""
            runningCount += 1
            updateDockTile()
            fetchThumbnailAsync(jobID: jobs[index].id)
            run(jobIndex: index)
        }
        updateDockTile()
    }

    func cancelCurrent() {
        for proc in runningProcesses.values {
            proc.terminate()
        }
        runningProcesses.removeAll()

        for idx in jobs.indices where jobs[idx].status == .running {
            jobs[idx].status = .cancelled
            jobs[idx].progressLine = "Cancelado por el usuario"
            jobs[idx].progressPercent = jobs[idx].progressPercent ?? 0
            jobs[idx].processPID = nil
        }

        runningCount = 0
        updateDockTile()
        runNextIfNeeded()
    }

    func cancelJob(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        if jobs[idx].status == .running {
            runningProcesses[jobID]?.terminate()
            runningProcesses.removeValue(forKey: jobID)

            jobs[idx].status = .cancelled
            jobs[idx].progressLine = "Cancelado por el usuario"
            jobs[idx].progressPercent = jobs[idx].progressPercent ?? 0
            jobs[idx].processPID = nil

            runningCount = max(0, runningCount - 1)
            updateDockTile()
            runNextIfNeeded()
        } else if jobs[idx].status == .queued || jobs[idx].status == .paused || jobs[idx].status == .scheduled {
            schedulerTimers[jobID]?.invalidate()
            schedulerTimers.removeValue(forKey: jobID)
            jobs[idx].status = .cancelled
            jobs[idx].progressLine = "Cancelado por el usuario"
            jobs[idx].progressPercent = jobs[idx].progressPercent ?? 0
            jobs[idx].processPID = nil
            updateDockTile()
        }
    }

    // MARK: - Pause / Resume

    func pauseJob(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        guard jobs[idx].status == .running, let pid = jobs[idx].processPID else { return }

        kill(pid, SIGSTOP)
        jobs[idx].status = .paused
        jobs[idx].progressLine = "Pausado"
        runningCount = max(0, runningCount - 1)
        updateDockTile()
    }

    func resumeJob(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        guard jobs[idx].status == .paused, let pid = jobs[idx].processPID else { return }

        kill(pid, SIGCONT)
        jobs[idx].status = .running
        jobs[idx].progressLine = "Reanudando..."
        runningCount += 1
        updateDockTile()
    }

    func retryWithoutMP4(for jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        jobs[idx].forceNoMP4 = true
        jobs[idx].status = .queued
        jobs[idx].progressLine = "Reintentando sin forzar MP4..."
        jobs[idx].outputFile = ""
        jobs[idx].log = ""
        jobs[idx].progressPercent = nil
        jobs[idx].speedText = ""
        jobs[idx].etaText = ""
        jobs[idx].errorSummary = ""
        jobs[idx].createdAt = Date()
        jobs[idx].processPID = nil

        selectedJobID = jobs[idx].id

        if logViewerJobID == jobs[idx].id {
            logViewerJobID = nil
        }

        runNextIfNeeded()
    }

    func toggleLog(for jobID: UUID) {
        if logViewerJobID == jobID {
            logViewerJobID = nil
        } else {
            logViewerJobID = jobID
        }
    }

    func revealOutput(for job: DownloadJob) {
        guard let outputURL = resolvedOutputURL(for: job) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func openOutput(for job: DownloadJob) {
        guard let outputURL = resolvedOutputURL(for: job) else { return }
        NSWorkspace.shared.open(outputURL)
    }

    func openFolder(for job: DownloadJob) {
        NSWorkspace.shared.open(job.destinationFolder)
    }

    func openDestination() {
        NSWorkspace.shared.open(destinationFolder)
    }

    func openHandBrake() {
        let appURL = URL(fileURLWithPath: "/Applications/HandBrake.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, _ in }
    }

    func openSafariM3U8Helper() {
        captureM3U8Instructions = true
    }

    // MARK: - iCloud Drive

    func openICloudDrive() {
        let iCloudURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloudURL.path) {
            NSWorkspace.shared.open(iCloudURL)
        }
    }

    func setDestinationToICloud() {
        let iCloudURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloudURL.path) {
            destinationFolder = iCloudURL
        }
    }

    // MARK: - Scheduler

    func scheduleJob(jobID: UUID, at date: Date) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].scheduledAt = date
        jobs[idx].status = .scheduled
        jobs[idx].progressLine = "Programado para \(date.formatted(date: .abbreviated, time: .shortened))"
        updateDockTile()

        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            // Immediately promote to queued
            jobs[idx].status = .queued
            jobs[idx].progressLine = "Esperando..."
            runNextIfNeeded()
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let i = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                if self.jobs[i].status == .scheduled {
                    self.jobs[i].status = .queued
                    self.jobs[i].progressLine = "Esperando..."
                    self.runNextIfNeeded()
                }
                self.schedulerTimers.removeValue(forKey: jobID)
            }
        }
        schedulerTimers[jobID] = timer
    }

    // MARK: - Quality picker

    func fetchFormats(for url: String, jobID: UUID) {
        guard let ytDlpPath = detectDependencies().ytDlpPath else { return }
        isFetchingFormats = true
        availableFormats = []
        qualityPickerJobID = jobID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let escaped = ytDlpPath.replacingOccurrences(of: "\"", with: "\\\"")
            process.arguments = ["-lc", "\"\(escaped)\" -J --no-download '\(url)'"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let formats = self.parseFormats(from: data)
                DispatchQueue.main.async {
                    self.availableFormats = formats
                    self.isFetchingFormats = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFetchingFormats = false
                }
            }
        }
    }

    nonisolated private func parseFormats(from data: Data) -> [VideoFormat] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let formats = json["formats"] as? [[String: Any]]
        else { return [] }

        return formats.compactMap { f -> VideoFormat? in
            guard let fid = f["format_id"] as? String else { return nil }
            let ext = f["ext"] as? String ?? "?"
            let width = f["width"] as? Int
            let height = f["height"] as? Int
            let resolution: String
            if let w = width, let h = height {
                resolution = "\(w)x\(h)"
            } else {
                resolution = f["format_note"] as? String ?? "—"
            }
            let filesize = f["filesize"] as? Int64 ?? f["filesize_approx"] as? Int64
            let vcodec = f["vcodec"] as? String ?? ""
            let acodec = f["acodec"] as? String ?? ""
            let codecInfo = [vcodec, acodec].filter { $0 != "none" && !$0.isEmpty }.joined(separator: " / ")
            let label = "\(resolution)  \(ext)  \(codecInfo)"
            return VideoFormat(id: fid, label: label, ext: ext, resolution: resolution, filesize: filesize)
        }
    }

    func applySelectedFormat(_ formatID: String, to jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].selectedFormat = formatID
        qualityPickerJobID = nil
        availableFormats = []
    }

    // MARK: - Playlist

    func isPlaylistURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        // Only treat as playlist when the URL is explicitly a playlist page (no specific video)
        return lower.contains("youtube.com/playlist") ||
               (lower.contains("youtu.be") && lower.contains("list=") && !lower.contains("v="))
    }

    /// Strips playlist context params from watch URLs so only the specific video is downloaded.
    func cleanVideoURL(_ urlString: String) -> String {
        guard let components = URLComponents(string: urlString),
              let host = components.host,
              (host.contains("youtube.com") || host.contains("youtu.be")),
              components.path.contains("/watch"),
              components.queryItems?.contains(where: { $0.name == "v" }) == true
        else { return urlString }
        var cleaned = components
        cleaned.queryItems = components.queryItems?.filter { ["v", "t"].contains($0.name) }
        return cleaned.url?.absoluteString ?? urlString
    }

    func fetchPlaylistEntries(url: String, preset: DownloadPreset) {
        guard let ytDlpPath = detectDependencies().ytDlpPath else { return }
        isFetchingPlaylist = true
        playlistEntries = []
        playlistPickerURL = url
        showPlaylistSheet = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let escaped = ytDlpPath.replacingOccurrences(of: "\"", with: "\\\"")
            process.arguments = ["-lc", "\"\(escaped)\" -j --flat-playlist --no-warnings '\(url)'"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let entries = self.parsePlaylistEntries(from: text)
                DispatchQueue.main.async {
                    self.playlistEntries = entries
                    self.isFetchingPlaylist = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFetchingPlaylist = false
                }
            }
        }
    }

    nonisolated private func parsePlaylistEntries(from text: String) -> [PlaylistEntry] {
        var results: [PlaylistEntry] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let title = json["title"] as? String ?? "Video \(i + 1)"
            let urlStr = json["url"] as? String ?? json["webpage_url"] as? String ?? ""
            let thumb = json["thumbnail"] as? String
            let vid = json["id"] as? String ?? "\(i)"
            results.append(PlaylistEntry(id: vid, title: title, url: urlStr, thumbnailURL: thumb))
        }
        return results
    }

    func enqueueSelectedPlaylistEntries(preset: DownloadPreset) {
        let selected = playlistEntries.filter { $0.selected }
        for entry in selected {
            var job = DownloadJob(
                sourceURL: entry.url,
                presetName: preset.name,
                destinationFolder: destinationFolder,
                extractAudioOnlyAsMP3: false
            )
            job.downloadSubtitles = downloadSubtitles
            job.thumbnailURL = entry.thumbnailURL
            job.targetFileSizeMB = enableTargetFileSize ? targetFileSizeMB : nil
            jobs.insert(job, at: 0)
        }
        playlistEntries = []
        playlistPickerURL = nil
        showPlaylistSheet = false
        runNextIfNeeded()
    }

    // MARK: - Export history

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func exportHistoryAsCSV() -> String {
        var lines = ["ID,Fecha,URL,Preset,Archivo,Estado"]
        for item in filteredHistory {
            let row = [
                item.id.uuidString,
                item.createdAt.formatted(.iso8601),
                item.sourceURL,
                item.presetName,
                item.outputFile,
                item.status
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    func exportHistoryAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(filteredHistory)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func saveExportToFile(content: String, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = filename.hasSuffix(".csv") ? [.commaSeparatedText] : [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Filtered history

    var filteredHistory: [DownloadHistoryItem] {
        history.filter { item in
            let statusOK = historyFilterStatus == "Todos" || item.status == historyFilterStatus
            let presetOK = historyFilterPreset == "Todos" || item.presetName.hasPrefix(historyFilterPreset)
            let fromOK = historyFilterDateFrom == nil || item.createdAt >= historyFilterDateFrom!
            let toOK = historyFilterDateTo == nil || item.createdAt <= historyFilterDateTo!
            return statusOK && presetOK && fromOK && toOK
        }
    }

    // MARK: - Resolve output

    func resolvedOutputURL(for job: DownloadJob) -> URL? {
        let fm = FileManager.default

        if !job.outputFile.isEmpty {
            let directURL = job.destinationFolder.appendingPathComponent(job.outputFile)
            if fm.fileExists(atPath: directURL.path) {
                return directURL
            }
        }

        guard let files = try? fm.contentsOfDirectory(
            at: job.destinationFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let sortedByDate = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }

        return sortedByDate.first
    }

    // MARK: - Download execution

    private func run(jobIndex: Int) {
        let deps = detectDependencies()

        guard let ytDlpPath = deps.ytDlpPath else {
            finish(jobIndex: jobIndex, success: false, message: "No se encontró yt-dlp.")
            return
        }

        guard FileManager.default.fileExists(atPath: ytDlpPath) else {
            finish(jobIndex: jobIndex, success: false, message: "La ruta detectada de yt-dlp no existe: \(ytDlpPath)")
            return
        }

        let job = jobs[jobIndex]

        if job.extractAudioOnlyAsMP3, deps.ffmpegPath == nil {
            finish(jobIndex: jobIndex, success: false, message: "Para extraer audio en MP3 hace falta ffmpeg.")
            return
        }

        let folderIsWritable = FileManager.default.isWritableFile(atPath: jobs[jobIndex].destinationFolder.path)
        guard folderIsWritable else {
            finish(jobIndex: jobIndex, success: false, message: "No hay permisos de escritura en la carpeta de destino.")
            return
        }

        let fileTemplate = "%(title)s.%(ext)s"
        var ytArgs = selectedPresetArgs(for: job.presetName)

        if job.extractAudioOnlyAsMP3 {
            ytArgs = ytArgs.filter { $0 != "--merge-output-format" && $0 != "mp4" }
            ytArgs += ["-x", "--audio-format", "mp3"]
        } else if job.forceNoMP4 {
            ytArgs = ytArgs.filter { $0 != "--merge-output-format" && $0 != "mp4" }
        }

        // Quality selection
        if let formatID = job.selectedFormat, !formatID.isEmpty {
            ytArgs += ["-f", formatID]
        }

        // Subtitles
        if job.downloadSubtitles {
            ytArgs += ["--write-auto-sub", "--sub-lang", "es,en"]
        }

        // Trim
        if !job.trimStart.isEmpty || !job.trimEnd.isEmpty {
            let start = job.trimStart.isEmpty ? "0" : job.trimStart
            let end = job.trimEnd.isEmpty ? "inf" : job.trimEnd
            ytArgs += ["--download-sections", "*\(start)-\(end)", "--force-keyframes-at-cuts"]
        }

        ytArgs += ["--print", "MEDIAINFO:%(resolution)s|%(abr)s"]

        // Tell yt-dlp exactly where ffmpeg is so it doesn't rely on PATH
        if let ffmpegPath = deps.ffmpegPath {
            ytArgs += ["--ffmpeg-location", ffmpegPath]
        }

        ytArgs += [
            "-P", job.destinationFolder.path,
            "-o", fileTemplate,
            job.sourceURL
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        let escapedPath = ytDlpPath.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "\"\(escapedPath)\" " + ytArgs.map { shellEscape($0) }.joined(separator: " ")

        process.arguments = ["-lc", command]
        process.standardOutput = outPipe
        process.standardError = errPipe
        runningProcesses[job.id] = process

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text, to: jobIndex)
                self?.updateDockTile()
            }
        }

        errHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text, to: jobIndex)
            }
        }

        let jobID = job.id
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                self?.runningProcesses.removeValue(forKey: jobID)

                if proc.terminationStatus == 0 {
                    self?.finish(jobIndex: jobIndex, success: true, message: "Descarga finalizada correctamente.")
                } else {
                    let fallbackMessage = self?.jobs.indices.contains(jobIndex) == true
                        ? (self?.jobs[jobIndex].progressLine ?? "")
                        : ""
                    self?.finish(
                        jobIndex: jobIndex,
                        success: false,
                        message: fallbackMessage.isEmpty
                            ? "La descarga terminó con error (código \(proc.terminationStatus))."
                            : fallbackMessage
                    )
                }
            }
        }

        do {
            try process.run()
            // Store PID for pause/resume
            jobs[jobIndex].processPID = process.processIdentifier
        } catch {
            runningProcesses.removeValue(forKey: job.id)
            finish(jobIndex: jobIndex, success: false, message: classifyError(error.localizedDescription))
        }
    }

    private static let suppressedLogPatterns: [String] = [
        "Error solving n challenge request using",
        "Error running deno process",
        "found O n function possibilities",
        "[Om [1m [31merror[Om",
    ]

    private func appendLog(_ text: String, to jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }

        let chunks = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let filtered = chunks.filter { line in
            !Self.suppressedLogPatterns.contains(where: { line.contains($0) })
        }

        if !filtered.isEmpty {
            jobs[jobIndex].log += filtered.joined(separator: "\n") + "\n"
        }

        for line in chunks {
            parseProgress(line, jobIndex: jobIndex)
            parseDestination(line, jobIndex: jobIndex)
            parseFinalState(line, jobIndex: jobIndex)
            parseErrors(line, jobIndex: jobIndex)
            parsePyInstallerError(line, jobIndex: jobIndex)
        }
    }

    private func parseProgress(_ line: String, jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("[download]") || trimmed.contains("[ExtractAudio]") {
            jobs[jobIndex].progressLine = trimmed
        }

        // Pre-download phases: map yt-dlp internal lines to friendly messages
        let lower = trimmed.lowercased()
        if jobs[jobIndex].progressPercent == nil {
            if lower.contains("extracting url") || lower.contains("downloading webpage")
                || lower.contains("downloading tv client") || lower.contains("downloading player")
                || lower.contains("downloading api json") || lower.contains("downloading initial data")
                || lower.contains("downloading json metadata") || lower.contains("setting up session") {
                jobs[jobIndex].progressLine = "Obteniendo información…"
            } else if lower.contains("downloading m3u8") || lower.contains("downloading mpd")
                        || lower.contains("downloading formats") {
                jobs[jobIndex].progressLine = "Procesando streams…"
            } else if lower.contains("downloading 1 format") || lower.contains("downloading 2 format")
                        || lower.contains("downloading 3 format") {
                jobs[jobIndex].progressLine = "Preparando descarga…"
            }
        }

        if let percent = firstMatch(in: trimmed, pattern: #"(\d+(?:\.\d+)?)%"#), let value = Double(percent) {
            jobs[jobIndex].progressPercent = value
        }

        if let speed = firstMatch(in: trimmed, pattern: #"at\s+([^\s]+(?:/s)?)"#) {
            jobs[jobIndex].speedText = speed
        }

        if let eta = firstMatch(in: trimmed, pattern: #"ETA\s+([^\s]+)"#) {
            jobs[jobIndex].etaText = eta
        }

        if trimmed.contains("100%") && jobs[jobIndex].progressPercent == nil {
            jobs[jobIndex].progressPercent = 100
        }

        if trimmed.hasPrefix("MEDIAINFO:") {
            let raw = String(trimmed.dropFirst("MEDIAINFO:".count))
            let parts = raw.components(separatedBy: "|")
            let res = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let abr = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

            var info: [String] = []
            if res == "audio only" {
                info.append("audio")
            } else if let height = res.split(separator: "x").last.flatMap({ Int($0) }) {
                info.append("\(height)p")
            } else if !res.isEmpty && res != "None" {
                info.append(res)
            }
            if !abr.isEmpty && abr != "None", let bitrate = Double(abr) {
                info.append("\(Int(bitrate)) kbps")
            }
            let formatted = info.joined(separator: " · ")
            if !formatted.isEmpty {
                jobs[jobIndex].mediaInfo = formatted
            }
        }
    }

    private func parseDestination(_ line: String, jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }

        if let range = line.range(of: "Destination:") {
            let raw = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                jobs[jobIndex].outputFile = URL(fileURLWithPath: raw).lastPathComponent
            }
        }

        if line.contains("has already been downloaded") {
            // Format: "[download] /full/path/to/file.mp4 has already been downloaded"
            if let endRange = line.range(of: " has already been downloaded"),
               let startRange = line.range(of: "] ") {
                let path = String(line[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    jobs[jobIndex].outputFile = URL(fileURLWithPath: path).lastPathComponent
                }
            }
        }

        if line.contains("[ExtractAudio] Destination:") {
            let value = line.replacingOccurrences(of: "[ExtractAudio] Destination:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                jobs[jobIndex].outputFile = URL(fileURLWithPath: value).lastPathComponent
            }
        }

        // Capture final merged filename (overrides any temp stream filenames)
        for prefix in ["[Merger] Merging formats into \"", "[ffmpeg] Merging formats into \""] {
            if line.contains(prefix), let start = line.range(of: prefix)?.upperBound {
                let rest = String(line[start...])
                if let end = rest.lastIndex(of: "\"") {
                    let raw = String(rest[rest.startIndex..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty {
                        jobs[jobIndex].outputFile = URL(fileURLWithPath: raw).lastPathComponent
                    }
                }
            }
        }
    }

    private func fetchThumbnailAsync(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[idx].thumbnailURL == nil else { return }
        guard let ytDlpPath = detectDependencies().ytDlpPath else { return }
        let url = jobs[idx].sourceURL

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let escaped = ytDlpPath.replacingOccurrences(of: "\"", with: "\\\"")
            process.arguments = ["-lc", "\"\(escaped)\" -J --no-download '\(url)'"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let thumb = json["thumbnail"] as? String else { return }
                DispatchQueue.main.async {
                    guard let i = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[i].thumbnailURL = thumb
                }
            } catch {}
        }
    }

    private func parseFinalState(_ line: String, jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("[Merger] Merging formats into") || trimmed.contains("[ffmpeg] Merging formats into") {
            jobs[jobIndex].progressLine = "Fusionando vídeo y audio…"
        } else if trimmed.contains("[ExtractAudio]") {
            jobs[jobIndex].progressLine = "Extrayendo audio…"
        } else if trimmed.contains("[Fixup") {
            jobs[jobIndex].progressLine = "Aplicando correcciones…"
        } else if trimmed.contains("[ffmpeg]") {
            jobs[jobIndex].progressLine = "Procesando con ffmpeg…"
        }

        if trimmed.contains("has already been downloaded") || trimmed.contains("already downloaded") {
            jobs[jobIndex].progressPercent = 100
            jobs[jobIndex].progressLine = "Archivo ya descargado previamente."
        }
    }

    private func parseErrors(_ line: String, jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }
        // Ignore yt-dlp WARNING: lines — they are non-fatal and the download may still succeed
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("WARNING:") else { return }
        let lower = line.lowercased()
        guard lower.contains("error") || lower.contains("forbidden") || lower.contains("permission denied") || lower.contains("unsupported") else { return }

        let classified = classifyError(line)
        jobs[jobIndex].errorSummary = classified
        jobs[jobIndex].progressLine = classified
    }

    private func parsePyInstallerError(_ line: String, jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[PYI-") || trimmed.contains("Failed to load Python shared library") || trimmed.contains("different Team IDs") else { return }
        let msg = classifyError(trimmed)
        jobs[jobIndex].errorSummary = msg
        jobs[jobIndex].progressLine = msg
    }

    private func classifyError(_ text: String) -> String {
        let lower = text.lowercased()

        if lower.contains("no se encontró yt-dlp") || (lower.contains("yt-dlp") && lower.contains("doesn't exist")) {
            return "Falta la dependencia yt-dlp. Revisá Preferences."
        }
        if lower.contains("failed to load python shared library") || lower.contains("different team ids") || text.contains("[PYI-") {
            return "El binario de yt-dlp no es compatible con esta versión de macOS. Ve a Preferencias → Dependencias y reinstala yt-dlp."
        }
        if lower.contains("ffmpeg") && (lower.contains("not found") || lower.contains("no such file")) {
            return "Falta la dependencia ffmpeg. Revisá Preferences."
        }
        if lower.contains("unsupported url") || lower.contains("unsupported") || lower.contains("no suitable extractor") {
            return "La URL no está soportada por yt-dlp."
        }
        if lower.contains("private video") || lower.contains("video unavailable") || lower.contains("sign in") || lower.contains("members-only") || lower.contains("forbidden") || lower.contains("403") {
            return "El video es privado, restringido o requiere acceso."
        }
        if lower.contains("unable to download webpage") || lower.contains("network is unreachable") || lower.contains("timed out") || lower.contains("temporary failure") || lower.contains("connection") {
            return "Hubo un fallo de red al intentar descargar."
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") || lower.contains("no hay permisos") || lower.contains("read-only") {
            return "Hay un problema de permisos de carpeta o del sistema."
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[valueRange])
    }

    private func finish(jobIndex: Int, success: Bool, message: String) {
        guard jobs.indices.contains(jobIndex) else { return }

        let finalMessage = success ? message : classifyError(message)
        jobs[jobIndex].status = success ? .finished : .failed

        if success {
            jobs[jobIndex].progressPercent = 100
        } else if jobs[jobIndex].progressPercent == nil {
            jobs[jobIndex].progressPercent = 0
        }

        jobs[jobIndex].progressLine = finalMessage
        if !success {
            jobs[jobIndex].errorSummary = finalMessage
        }
        jobs[jobIndex].log += "\n\(finalMessage)\n"
        jobs[jobIndex].processPID = nil

        runningCount = max(0, runningCount - 1)

        if success {
            // If compression target is set and job has an output file, compress first
            if let targetMB = jobs[jobIndex].targetFileSizeMB,
               targetMB > 0,
               !jobs[jobIndex].outputFile.isEmpty,
               !jobs[jobIndex].extractAudioOnlyAsMP3 {
                jobs[jobIndex].status = .compressing
                jobs[jobIndex].progressLine = "Comprimiendo a \(Int(targetMB)) MB..."
                jobs[jobIndex].progressPercent = nil
                updateDockTile()
                runNextIfNeeded()
                compressVideo(jobIndex: jobIndex, targetSizeMB: targetMB)
                return
            }

            // Format conversion
            if !jobs[jobIndex].convertToFormat.isEmpty {
                updateDockTile()
                runNextIfNeeded()
                convertFormat(jobIndex: jobIndex, format: jobs[jobIndex].convertToFormat)
                return
            }

            // Integrity verification
            if jobs[jobIndex].verifyIntegrity {
                updateDockTile()
                runNextIfNeeded()
                verifyFileIntegrity(jobIndex: jobIndex)
                return
            }

            appendToHistory(job: jobs[jobIndex])
            // Copy URL to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jobs[jobIndex].sourceURL, forType: .string)
            // Send notification
            sendNotification(
                title: NSLocalizedString("notif_download_complete", comment: "Notification title: download complete"),
                body: jobs[jobIndex].outputFile.isEmpty ? jobs[jobIndex].sourceURL : jobs[jobIndex].outputFile
            )
        } else {
            sendNotification(
                title: NSLocalizedString("notif_download_error", comment: "Notification title: download error"),
                body: finalMessage
            )
        }

        updateDockTile()
        runNextIfNeeded()
    }

    private func compressVideo(jobIndex: Int, targetSizeMB: Double) {
        guard jobs.indices.contains(jobIndex) else { return }
        let deps = detectDependencies()
        guard let ffmpegPath = deps.ffmpegPath else {
            jobs[jobIndex].status = .failed
            jobs[jobIndex].errorSummary = "ffmpeg no encontrado. No se puede comprimir."
            jobs[jobIndex].progressLine = jobs[jobIndex].errorSummary
            runNextIfNeeded()
            return
        }

        // Use resolvedOutputURL for robust file detection (handles special chars, fallback to newest file)
        guard let inputURL = resolvedOutputURL(for: jobs[jobIndex]) else {
            jobs[jobIndex].status = .failed
            jobs[jobIndex].errorSummary = "No se encontró el archivo descargado para comprimir."
            jobs[jobIndex].progressLine = jobs[jobIndex].errorSummary
            runNextIfNeeded()
            return
        }

        let compressedURL = inputURL.deletingLastPathComponent()
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_compressed")
            .appendingPathExtension(inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension)

        let jobID = jobs[jobIndex].id
        let escapedFFmpeg = shellEscape(ffmpegPath)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Helper: run a zsh command and return (status, stdout)
            func zsh(_ command: String, stderrHandler: ((String) -> Void)? = nil) -> (status: Int32, output: String) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", command]
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                if let handler = stderrHandler {
                    errPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                        handler(text)
                    }
                }
                do { try proc.run(); proc.waitUntilExit() } catch { return (-1, "") }
                errPipe.fileHandleForReading.readabilityHandler = nil
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
            }

            // Step 1: get duration — use ffmpeg -i which prints to stderr, parse Duration line
            let escapedInput = self.shellEscape(inputURL.path)
            let probeResult = zsh("\(escapedFFmpeg) -i \(escapedInput) 2>&1 | grep Duration")
            let durationLine = probeResult.output
            // Parse "Duration: HH:MM:SS.mm"
            var duration: Double = 0
            if let regex = try? NSRegularExpression(pattern: #"Duration:\s*(\d+):(\d+):(\d+\.?\d*)"#),
               let match = regex.firstMatch(in: durationLine, range: NSRange(durationLine.startIndex..., in: durationLine)) {
                let h = Double((durationLine as NSString).substring(with: match.range(at: 1))) ?? 0
                let m = Double((durationLine as NSString).substring(with: match.range(at: 2))) ?? 0
                let s = Double((durationLine as NSString).substring(with: match.range(at: 3))) ?? 0
                duration = h * 3600 + m * 60 + s
            }

            // Fallback: try ffprobe if available
            if duration == 0 {
                let probeCmd = "which ffprobe >/dev/null 2>&1 && ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \(escapedInput)"
                let probeR = zsh(probeCmd)
                duration = Double(probeR.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[idx].log += "\n[Compresión] Archivo: \(inputURL.lastPathComponent) · Duración detectada: \(String(format: "%.1f", duration))s\n"
            }

            guard duration > 0 else {
                DispatchQueue.main.async {
                    guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[idx].status = .failed
                    self.jobs[idx].errorSummary = "No se pudo obtener la duración del video para comprimir."
                    self.jobs[idx].progressLine = self.jobs[idx].errorSummary
                    self.runNextIfNeeded()
                }
                return
            }

            // Step 2: calculate bitrates
            let targetBits = targetSizeMB * 8.0 * 1024.0 * 1024.0
            let audioBitsBps = 128.0 * 1024.0
            let videoBitrateKbps = max(100, (targetBits / duration - audioBitsBps) / 1024.0)
            let videoBitrateStr = String(Int(videoBitrateKbps))

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[idx].progressLine = "Comprimiendo · Pasada 1/2 · \(videoBitrateStr) kbps..."
                self.jobs[idx].log += "[Compresión] Bitrate objetivo: \(videoBitrateStr) kbps\n"
            }

            func parseFFmpegProgress(_ text: String, offset: Double, scale: Double) -> Double? {
                guard let range = text.range(of: #"time=\d+:\d+:\d+\.\d+"#, options: .regularExpression) else { return nil }
                let timeStr = String(text[range]).replacingOccurrences(of: "time=", with: "")
                let parts = timeStr.split(separator: ":").compactMap { Double($0) }
                guard parts.count == 3 else { return nil }
                let elapsed = parts[0] * 3600 + parts[1] * 60 + parts[2]
                return offset + min(scale, (elapsed / duration) * scale)
            }

            let escapedOutput = self.shellEscape(compressedURL.path)
            let logFile = self.shellEscape(inputURL.deletingLastPathComponent().appendingPathComponent("ffmpeg2pass").path)

            // Step 3a: Pass 1
            let pass1 = zsh(
                "\(escapedFFmpeg) -y -i \(escapedInput) -c:v libx264 -b:v \(videoBitrateStr)k -pass 1 -passlogfile \(logFile) -an -f null /dev/null",
                stderrHandler: { text in
                    DispatchQueue.main.async {
                        guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                        if let pct = parseFFmpegProgress(text, offset: 0, scale: 50) {
                            self.jobs[idx].progressPercent = pct
                            self.jobs[idx].progressLine = "Comprimiendo · Pasada 1/2 · \(String(format: "%.0f%%", pct * 2))"
                        }
                    }
                }
            )

            guard pass1.status == 0 else {
                DispatchQueue.main.async {
                    guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[idx].status = .failed
                    self.jobs[idx].errorSummary = "Error en la pasada 1 de compresión (código \(pass1.status))."
                    self.jobs[idx].progressLine = self.jobs[idx].errorSummary
                    self.runNextIfNeeded()
                }
                return
            }

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[idx].progressLine = "Comprimiendo · Pasada 2/2..."
                self.jobs[idx].progressPercent = 50
            }

            // Step 3b: Pass 2
            let pass2 = zsh(
                "\(escapedFFmpeg) -y -i \(escapedInput) -c:v libx264 -b:v \(videoBitrateStr)k -pass 2 -passlogfile \(logFile) -c:a aac -b:a 128k \(escapedOutput)",
                stderrHandler: { text in
                    DispatchQueue.main.async {
                        guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                        if let pct = parseFFmpegProgress(text, offset: 50, scale: 50) {
                            self.jobs[idx].progressPercent = pct
                            self.jobs[idx].progressLine = "Comprimiendo · Pasada 2/2 · \(String(format: "%.0f%%", pct))"
                        }
                    }
                }
            )

            // Clean up two-pass log files
            let logBase = inputURL.deletingLastPathComponent().appendingPathComponent("ffmpeg2pass").path
            try? FileManager.default.removeItem(atPath: logBase + "-0.log")
            try? FileManager.default.removeItem(atPath: logBase + "-0.log.mbtree")

            guard pass2.status == 0 else {
                DispatchQueue.main.async {
                    guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[idx].status = .failed
                    self.jobs[idx].errorSummary = "Error en la pasada 2 de compresión (código \(pass2.status))."
                    self.jobs[idx].progressLine = self.jobs[idx].errorSummary
                    self.runNextIfNeeded()
                }
                return
            }

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[idx].outputFile = compressedURL.lastPathComponent
                self.jobs[idx].status = .finished
                self.jobs[idx].progressPercent = 100
                self.jobs[idx].progressLine = "Compresión completada · \(compressedURL.lastPathComponent)"
                self.jobs[idx].log += "\n[Compresión completada] → \(compressedURL.path)\n"

                // Format conversion after compression?
                if !self.jobs[idx].convertToFormat.isEmpty {
                    self.updateDockTile()
                    self.convertFormat(jobIndex: idx, format: self.jobs[idx].convertToFormat)
                    return
                }

                // Integrity verification after compression?
                if self.jobs.indices.contains(idx) && self.jobs[idx].verifyIntegrity {
                    self.updateDockTile()
                    self.verifyFileIntegrity(jobIndex: idx)
                    return
                }

                self.appendToHistory(job: self.jobs[idx])
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.jobs[idx].sourceURL, forType: .string)
                self.sendNotification(title: NSLocalizedString("notif_compression_complete", comment: "Notification title: compression complete"), body: compressedURL.lastPathComponent)
                self.updateDockTile()
                self.runNextIfNeeded()
            }
        }
    }

    // MARK: - Duration Fetch (for trim pre-fill)

    func fetchDuration(for urlString: String, completion: @escaping (Int, Int, Int) -> Void) {
        guard let ytDlpPath = detectDependencies().ytDlpPath else { return }
        let escaped = shellEscape(urlString)
        let escapedYtDlp = shellEscape(ytDlpPath)
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "\(escapedYtDlp) --print duration \(escaped) 2>/dev/null"]
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let total = Int(Double(raw) ?? 0)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            DispatchQueue.main.async { completion(h, m, s) }
        }
    }

    // MARK: - Format Conversion

    func convertFormat(jobIndex: Int, format: String) {
        guard jobs.indices.contains(jobIndex) else { return }
        let deps = detectDependencies()
        guard let ffmpegPath = deps.ffmpegPath else {
            jobs[jobIndex].status = .failed
            jobs[jobIndex].progressLine = "ffmpeg no encontrado. No se puede convertir."
            jobs[jobIndex].errorSummary = jobs[jobIndex].progressLine
            runNextIfNeeded()
            return
        }

        guard let inputURL = resolvedOutputURL(for: jobs[jobIndex]) else {
            let storedFile = jobs[jobIndex].outputFile
            let folder = jobs[jobIndex].destinationFolder.path
            let folderContents = (try? FileManager.default.contentsOfDirectory(atPath: folder))?.joined(separator: ", ") ?? "(unable to list)"
            jobs[jobIndex].status = .failed
            jobs[jobIndex].progressLine = "No se encontró el archivo para convertir."
            jobs[jobIndex].log += "\n[Debug] outputFile='\(storedFile)' folder='\(folder)' contents=[\(folderContents)]\n"
            jobs[jobIndex].errorSummary = jobs[jobIndex].progressLine
            runNextIfNeeded()
            return
        }

        // When input and output share the same extension, ffmpeg can't write in-place.
        // Use a temp file and swap after a successful conversion.
        let sameExtension = inputURL.pathExtension.lowercased() == format.lowercased()
        let ffmpegOutputURL = sameExtension
            ? inputURL.deletingPathExtension().appendingPathExtension("_tmp.\(format)")
            : inputURL.deletingPathExtension().appendingPathExtension(format)
        let finalOutputURL = sameExtension ? inputURL : ffmpegOutputURL
        let jobID = jobs[jobIndex].id

        jobs[jobIndex].status = .compressing
        jobs[jobIndex].progressLine = "Convirtiendo a \(format.uppercased())..."
        jobs[jobIndex].progressPercent = nil
        updateDockTile()

        let ffmpegArgs: [String]
        switch format {
        case "webm":
            ffmpegArgs = ["-y", "-i", inputURL.path, "-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-c:a", "libopus", ffmpegOutputURL.path]
        case "mkv":
            ffmpegArgs = ["-y", "-i", inputURL.path, "-c:v", "copy", "-c:a", "copy", ffmpegOutputURL.path]
        default: // mov, avi, mp4
            ffmpegArgs = ["-y", "-i", inputURL.path, "-c:v", "libx264", "-preset", "fast", "-crf", "22", "-c:a", "aac", "-b:a", "192k", ffmpegOutputURL.path]
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Probe duration so we can show real progress
            var duration: Double = 0
            let probeProc = Process()
            probeProc.executableURL = URL(fileURLWithPath: ffmpegPath)
            probeProc.arguments = ["-i", inputURL.path]
            probeProc.standardInput = FileHandle.nullDevice
            probeProc.standardOutput = FileHandle.nullDevice
            let probePipe = Pipe()
            probeProc.standardError = probePipe
            try? probeProc.run()
            probeProc.waitUntilExit()
            let probeOutput = String(data: probePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if let regex = try? NSRegularExpression(pattern: #"Duration:\s*(\d+):(\d+):(\d+\.?\d*)"#),
               let match = regex.firstMatch(in: probeOutput, range: NSRange(probeOutput.startIndex..., in: probeOutput)) {
                let h = Double((probeOutput as NSString).substring(with: match.range(at: 1))) ?? 0
                let m = Double((probeOutput as NSString).substring(with: match.range(at: 2))) ?? 0
                let s = Double((probeOutput as NSString).substring(with: match.range(at: 3))) ?? 0
                duration = h * 3600 + m * 60 + s
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ffmpegPath)
            proc.arguments = ffmpegArgs
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice

            let errPipe = Pipe()
            proc.standardError = errPipe

            var stderrOutput = ""

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                stderrOutput += text
                DispatchQueue.main.async {
                    guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[idx].log += text
                    if let range = text.range(of: #"time=\d+:\d+:\d+\.\d+"#, options: .regularExpression) {
                        let timeStr = String(text[range]).replacingOccurrences(of: "time=", with: "")
                        let parts = timeStr.split(separator: ":").compactMap { Double($0) }
                        if parts.count == 3, duration > 0 {
                            let elapsed = parts[0] * 3600 + parts[1] * 60 + parts[2]
                            let pct = min(99, (elapsed / duration) * 100)
                            self.jobs[idx].progressPercent = pct
                            self.jobs[idx].progressLine = "Convirtiendo a \(format.uppercased())… \(String(format: "%.0f%%", pct))"
                        }
                    }
                }
            }

            var runError: String? = nil
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                runError = error.localizedDescription
            }
            errPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = proc.terminationStatus

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }

                if let err = runError {
                    self.jobs[idx].status = .failed
                    self.jobs[idx].progressLine = "Failed to launch ffmpeg: \(err)"
                    self.jobs[idx].errorSummary = self.jobs[idx].progressLine
                    self.jobs[idx].log += "\n[Error] \(err)\n"
                    self.updateDockTile()
                    self.runNextIfNeeded()
                    return
                }

                if exitCode == 0 {
                    if sameExtension {
                        try? FileManager.default.removeItem(at: inputURL)
                        try? FileManager.default.moveItem(at: ffmpegOutputURL, to: finalOutputURL)
                    }
                    self.jobs[idx].outputFile = finalOutputURL.lastPathComponent
                    self.jobs[idx].status = .finished
                    self.jobs[idx].progressPercent = 100
                    self.jobs[idx].progressLine = "Conversion complete · \(finalOutputURL.lastPathComponent)"
                    self.jobs[idx].log += "\n[Conversion complete] → \(finalOutputURL.path)\n"

                    if self.jobs[idx].verifyIntegrity {
                        self.verifyFileIntegrity(jobIndex: idx)
                        return
                    }

                    self.appendToHistory(job: self.jobs[idx])
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.jobs[idx].sourceURL, forType: .string)
                    self.sendNotification(
                        title: NSLocalizedString("notif_download_complete", comment: "Notification title: download complete"),
                        body: finalOutputURL.lastPathComponent
                    )
                } else {
                    self.jobs[idx].status = .failed
                    self.jobs[idx].progressLine = "Conversion to \(format.uppercased()) failed (code \(exitCode)). See log for details."
                    self.jobs[idx].errorSummary = self.jobs[idx].progressLine
                }
                self.updateDockTile()
                self.runNextIfNeeded()
            }
        }
    }

    // MARK: - Integrity Verification

    func verifyFileIntegrity(jobIndex: Int) {
        guard jobs.indices.contains(jobIndex) else { return }

        guard let inputURL = resolvedOutputURL(for: jobs[jobIndex]) else {
            jobs[jobIndex].integrityStatus = "unchecked"
            appendToHistory(job: jobs[jobIndex])
            runNextIfNeeded()
            return
        }

        let jobID = jobs[jobIndex].id
        jobs[jobIndex].progressLine = "Verificando integridad..."

        let escapedInput = shellEscape(inputURL.path)
        // Check any stream (video or audio) so audio-only files like MP3 are not falsely flagged
        let cmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \(escapedInput) 2>&1"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", cmd]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do { try proc.run(); proc.waitUntilExit() } catch {}
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                guard let idx = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                if proc.terminationStatus == 0 && !output.isEmpty {
                    self.jobs[idx].integrityStatus = "ok"
                    self.jobs[idx].progressLine = (self.jobs[idx].progressLine.components(separatedBy: "\n").first ?? "") + " · " + NSLocalizedString("integrity_ok", comment: "Integrity OK")
                } else {
                    self.jobs[idx].integrityStatus = "corrupt"
                    self.jobs[idx].progressLine = NSLocalizedString("integrity_corrupt", comment: "File may be corrupted")
                }
                self.appendToHistory(job: self.jobs[idx])
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.jobs[idx].sourceURL, forType: .string)
                self.sendNotification(
                    title: NSLocalizedString("notif_download_complete", comment: "Notification title: download complete"),
                    body: self.jobs[idx].outputFile.isEmpty ? self.jobs[idx].sourceURL : self.jobs[idx].outputFile
                )
                self.updateDockTile()
            }
        }
    }

    // MARK: - Quick Look

    func openQuickLook(for job: DownloadJob) {
        guard let url = resolvedOutputURL(for: job),
              let panel = QLPreviewPanel.shared() else { return }
        let controller = QuickLookPanelController.shared
        controller.currentURL = url
        panel.dataSource = controller
        panel.delegate = controller
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func toggleQuickLook(for job: DownloadJob) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            openQuickLook(for: job)
        }
    }

    private func appendToHistory(job: DownloadJob) {
        let item = DownloadHistoryItem(
            id: job.id,
            createdAt: job.createdAt,
            sourceURL: job.sourceURL,
            presetName: job.presetName + (job.extractAudioOnlyAsMP3 ? " · Audio MP3" : ""),
            destinationPath: job.destinationFolder.path,
            outputFile: job.outputFile,
            status: job.status.rawValue
        )
        history.insert(item, at: 0)
        saveHistory()
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            print("No se pudo guardar historial: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL)
            history = try JSONDecoder().decode([DownloadHistoryItem].self, from: data)
        } catch {
            history = []
        }
    }

    private func normalizeURLs(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: .whitespaces) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private func detectPreset(for urlString: String) -> DownloadPreset {
        if urlString.lowercased().contains(".m3u8") {
            return DownloadPreset.all.first(where: { $0.name == "M3U8 / Streaming" }) ?? .general
        }

        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return .general
        }

        return DownloadPreset.all.first(where: { preset in
            preset.domains.contains(where: { host.contains($0) })
        }) ?? .general
    }

    private func selectedPresetArgs(for presetName: String) -> [String] {
        DownloadPreset.all.first(where: { $0.name == presetName })?.ytDlpArgs ?? DownloadPreset.general.ytDlpArgs
    }

    nonisolated private func shellEscape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private func shellEscapeForDoubleQuotes(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func binaryPath(candidates: [String]) -> String? {
        candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func brewExecutablePath() -> String? {
        binaryPath(candidates: [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]) ?? shellWhich("brew")
    }

    private func shellWhich(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @ObservedObject var vm: DownloaderViewModel
    @AppStorage("hideWelcomeModal") private var hideWelcomeModal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(NSLocalizedString("prefs_title", comment: "Preferences view title"))
                .font(.largeTitle.bold())

            Text(NSLocalizedString("prefs_subtitle", comment: "Preferences view subtitle"))
                .foregroundStyle(.secondary)

            GroupBox("Downloads") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max simultaneous downloads")
                        Spacer()
                        Stepper("\(vm.maxConcurrentDownloads)", value: $vm.maxConcurrentDownloads, in: 1...10)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }

            GroupBox(NSLocalizedString("prefs_deps_header", comment: "GroupBox: dependencies")) {
                VStack(spacing: 14) {
                    DependencyInstallRow(vm: vm, kind: .ytDlp)
                    DependencyInstallRow(vm: vm, kind: .ffmpeg)
                    DependencyInstallRow(vm: vm, kind: .handBrake)
                }
                .padding(.vertical, 8)
            }

            HStack {
                Button(NSLocalizedString("prefs_recheck", comment: "Button: recheck dependencies")) {
                    vm.refreshDependencyState()
                }

                Button(NSLocalizedString("prefs_show_welcome_again", comment: "Button: show welcome again")) {
                    hideWelcomeModal = false
                    NSApp.keyWindow?.close()
                    vm.showWelcomeModal = true
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct DependencyInstallRow: View {
    @ObservedObject var vm: DownloaderViewModel
    let kind: DependencyKind

    private var state: DependencyInstallState {
        vm.dependencyInstallStates[kind] ?? DependencyInstallState()
    }

    private var canInstall: Bool {
        switch kind {
        case .ytDlp, .ffmpeg: return false
        case .handBrake: return !state.isInstalled && !state.isInstalling
        }
    }

    private var actionButtonLabel: String {
        switch kind {
        case .handBrake:
            return state.isInstalled
                ? NSLocalizedString("dep_installed", comment: "Dependency status: installed")
                : NSLocalizedString("dep_install_btn", comment: "Button: install dependency")
        default: return ""
        }
    }

    private var versionLabel: String? {
        guard state.isInstalled, let v = state.installedVersion, !v.isEmpty else { return nil }
        return "v\(v)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(state.isInstalled ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.headline)

                    Text(state.resolvedPath ?? NSLocalizedString("dep_not_installed_path", comment: "Dependency row: path when not installed"))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(state.statusText.isEmpty ? (state.isInstalled ? NSLocalizedString("dep_installed", comment: "Dependency status: installed") : NSLocalizedString("dep_not_installed", comment: "Dependency status: not installed")) : state.statusText)
                        .font(.caption)
                        .foregroundStyle(state.isInstalled ? .green : .secondary)

                    if let vLabel = versionLabel {
                        Text(vLabel)
                            .font(.caption)
                            .foregroundStyle(state.updateAvailable ? .orange : .secondary)
                    }
                }

                Spacer()

                if state.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 80)
                }

                switch kind {
                case .ytDlp, .ffmpeg:
                    Text("Incluida en la app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .handBrake:
                    Button(actionButtonLabel) {
                        vm.installDependency(kind)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canInstall)
                }
            }

            if state.isInstalling {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if !state.log.isEmpty {
                ScrollView {
                    Text(state.log)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 84)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct JobProgressView: View {
    let job: DownloadJob

    private var tint: Color {
        switch job.status {
        case .finished:
            return .green
        case .failed, .cancelled:
            return .red
        case .paused:
            return .orange
        case .queued, .running, .scheduled:
            return .blue
        case .compressing:
            return .purple
        }
    }

    private var value: Double {
        job.progressPercent ?? 0
    }

    var body: some View {
        ProgressView(value: value, total: 100)
            .tint(tint)
    }
}

struct JobContextMenu: View {
    @ObservedObject var vm: DownloaderViewModel
    let job: DownloadJob

    var body: some View {
        Group {
            if job.status == .running {
                Button(NSLocalizedString("ctx_pause_download", comment: "Context menu: pause download")) {
                    vm.pauseJob(jobID: job.id)
                }
                Button(NSLocalizedString("ctx_cancel_download", comment: "Context menu: cancel download")) {
                    vm.cancelJob(jobID: job.id)
                }
            }

            if job.status == .paused {
                Button(NSLocalizedString("ctx_resume_download", comment: "Context menu: resume download")) {
                    vm.resumeJob(jobID: job.id)
                }
                Button(NSLocalizedString("ctx_cancel_download", comment: "Context menu: cancel download")) {
                    vm.cancelJob(jobID: job.id)
                }
            }

            if job.status == .queued {
                Button(NSLocalizedString("ctx_cancel_download", comment: "Context menu: cancel download")) {
                    vm.cancelJob(jobID: job.id)
                }
            }

            if job.status == .scheduled {
                Button(NSLocalizedString("ctx_cancel_schedule", comment: "Context menu: cancel scheduled download")) {
                    vm.cancelJob(jobID: job.id)
                }
            }

            if job.status == .cancelled || job.status == .failed {
                Button(NSLocalizedString("ctx_restart_download", comment: "Context menu: restart download")) {
                    vm.rerun(jobID: job.id)
                }

                Button(NSLocalizedString("ctx_delete", comment: "Context menu: delete"), role: .destructive) {
                    vm.removeJob(jobID: job.id)
                }
            }

            if job.status == .finished {
                Button(NSLocalizedString("ctx_open_file", comment: "Context menu: open file")) {
                    vm.openOutput(for: job)
                }

                Button(NSLocalizedString("ctx_open_folder", comment: "Context menu: open folder")) {
                    vm.openFolder(for: job)
                }

                Button(NSLocalizedString("quick_look", comment: "Context menu: Quick Look")) {
                    vm.openQuickLook(for: job)
                }

                Button(vm.logViewerJobID == job.id ? NSLocalizedString("ctx_hide_log", comment: "Context menu: hide log") : NSLocalizedString("ctx_show_log", comment: "Context menu: show log")) {
                    vm.selectedJobID = job.id
                    vm.toggleLog(for: job.id)
                }

                Divider()

                Button(NSLocalizedString("ctx_delete", comment: "Context menu: delete"), role: .destructive) {
                    vm.removeJob(jobID: job.id)
                }
            }
        }
    }
}

struct ContextMenuCell<Content: View>: View {
    @ObservedObject var vm: DownloaderViewModel
    let job: DownloadJob
    let alignment: Alignment
    let content: Content

    init(
        vm: DownloaderViewModel,
        job: DownloadJob,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.vm = vm
        self.job = job
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .contextMenu {
                JobContextMenu(vm: vm, job: job)
            }
    }
}

// MARK: - Quality Picker Sheet

struct QualityPickerSheet: View {
    @ObservedObject var vm: DownloaderViewModel
    @State private var selectedFormatID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("quality_picker_title", comment: "Quality picker sheet title"))
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if vm.isFetchingFormats {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("quality_picker_fetching", comment: "Quality picker: fetching formats"))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            } else if vm.availableFormats.isEmpty {
                Text(NSLocalizedString("quality_picker_no_formats", comment: "Quality picker: no formats found"))
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                List(vm.availableFormats, selection: $selectedFormatID) { fmt in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fmt.label)
                            .font(.body)
                        if let size = fmt.filesize {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(fmt.id)
                }
                .frame(minHeight: 250)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("btn_cancel", comment: "Button: cancel")) {
                    vm.qualityPickerJobID = nil
                    vm.availableFormats = []
                }
                .buttonStyle(.bordered)

                Button(NSLocalizedString("quality_picker_apply", comment: "Button: apply quality selection")) {
                    if let jobID = vm.qualityPickerJobID {
                        vm.applySelectedFormat(selectedFormatID, to: jobID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFormatID.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}

// MARK: - Playlist Picker Sheet

struct PlaylistPickerSheet: View {
    @ObservedObject var vm: DownloaderViewModel

    private var detectedPreset: DownloadPreset {
        guard let url = vm.playlistPickerURL else { return .general }
        return DownloadPreset.all.first(where: { preset in
            guard let host = URL(string: url)?.host?.lowercased() else { return false }
            return preset.domains.contains(where: { host.contains($0) })
        }) ?? .general
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("playlist_picker_title", comment: "Playlist picker sheet title"))
                    .font(.title2.bold())
                Spacer()
                Text(String(format: NSLocalizedString("playlist_selected_count", comment: "Playlist: %d/%d selected"), vm.playlistEntries.filter(\.selected).count, vm.playlistEntries.count))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            if vm.isFetchingPlaylist {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("playlist_picker_loading", comment: "Playlist picker: loading entries"))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.playlistEntries.indices, id: \.self) { i in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { vm.playlistEntries[i].selected },
                                    set: { vm.playlistEntries[i].selected = $0 }
                                ))
                                .labelsHidden()

                                if let thumbURL = vm.playlistEntries[i].thumbnailURL,
                                   let url = URL(string: thumbURL) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(Color.secondary.opacity(0.2))
                                    }
                                    .frame(width: 60, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 60, height: 34)
                                }

                                Text(vm.playlistEntries[i].title)
                                    .lineLimit(2)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 88)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(NSLocalizedString("playlist_select_all", comment: "Button: select all playlist entries")) {
                    for i in vm.playlistEntries.indices { vm.playlistEntries[i].selected = true }
                }
                Button(NSLocalizedString("playlist_deselect_all", comment: "Button: deselect all playlist entries")) {
                    for i in vm.playlistEntries.indices { vm.playlistEntries[i].selected = false }
                }
                Spacer()
                Button(NSLocalizedString("btn_cancel", comment: "Button: cancel")) {
                    vm.playlistEntries = []
                    vm.playlistPickerURL = nil
                    vm.showPlaylistSheet = false
                }
                .buttonStyle(.bordered)
                Button(NSLocalizedString("playlist_download_selected", comment: "Button: download selected entries")) {
                    vm.enqueueSelectedPlaylistEntries(preset: detectedPreset)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.playlistEntries.filter(\.selected).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 600, minHeight: 460)
    }
}

// MARK: - Scheduler Sheet

struct SchedulerSheet: View {
    @ObservedObject var vm: DownloaderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("scheduler_title", comment: "Scheduler sheet title"))
                .font(.title2.bold())

            Text(NSLocalizedString("scheduler_subtitle", comment: "Scheduler sheet subtitle"))
                .foregroundStyle(.secondary)

            DatePicker(
                NSLocalizedString("scheduler_date_label", comment: "DatePicker label: date and time"),
                selection: $vm.scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.stepperField)

            HStack {
                Spacer()
                Button(NSLocalizedString("btn_cancel", comment: "Button: cancel")) {
                    vm.showSchedulerSheet = false
                    vm.schedulerJobID = nil
                }
                .buttonStyle(.bordered)

                Button(NSLocalizedString("scheduler_schedule_btn", comment: "Button: schedule")) {
                    if let jobID = vm.schedulerJobID {
                        vm.scheduleJob(jobID: jobID, at: vm.scheduledDate)
                    }
                    vm.showSchedulerSheet = false
                    vm.schedulerJobID = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Main View

struct ContentView: View {
    @ObservedObject var vm: DownloaderViewModel
    @State private var importingFolder = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD")!)
                } label: {
                    Label("Donate", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
                .help("Support Video Grabber")
            }
        }
        .fileImporter(
            isPresented: $importingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let folder = urls.first {
                vm.destinationFolder = folder
            }
        }
        .sheet(isPresented: $vm.captureM3U8Instructions) {
            M3U8HelperView()
        }
        .sheet(isPresented: Binding(
            get: { vm.qualityPickerJobID != nil },
            set: { if !$0 { vm.qualityPickerJobID = nil; vm.availableFormats = [] } }
        )) {
            QualityPickerSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showPlaylistSheet) {
            PlaylistPickerSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showSchedulerSheet) {
            SchedulerSheet(vm: vm)
        }
        // Drag & Drop URLs onto the window
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    var urlString: String?
                    if let url = item as? URL {
                        urlString = url.absoluteString
                    } else if let data = item as? Data {
                        urlString = String(data: data, encoding: .utf8)
                    }
                    if let s = urlString, s.hasPrefix("http") {
                        DispatchQueue.main.async {
                            vm.stagedURLs.append(StagedURL(urlString: s))
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var text: String?
                    if let str = item as? String {
                        text = str
                    } else if let data = item as? Data {
                        text = String(data: data, encoding: .utf8)
                    }
                    if let s = text?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("http") {
                        DispatchQueue.main.async {
                            vm.stagedURLs.append(StagedURL(urlString: s))
                        }
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())

            Text("Video Grabber")
                .font(.largeTitle.bold())

            Text(NSLocalizedString("app_subtitle", comment: "App subtitle in sidebar"))
                .foregroundStyle(.secondary)

            Divider()

            GroupBox {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField(NSLocalizedString("url_placeholder", comment: "URL input placeholder"), text: $vm.newURLInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { vm.addStagedURL() }
                        Button {
                            vm.addStagedURL()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.newURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !vm.stagedURLs.isEmpty {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(vm.stagedURLs) { staged in
                                    StagedURLRow(
                                        staged: staged,
                                        onUpdate: { vm.updateStagedURL($0) },
                                        onRemove: { vm.removeStagedURL(id: staged.id) }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
            } label: {
                Text(NSLocalizedString("sidebar_urls_label", comment: "GroupBox label: URLs to download"))
            }

            GroupBox(NSLocalizedString("sidebar_destination_header", comment: "GroupBox: destination folder")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.destinationFolder.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)

                    HStack {
                        if vm.isUsingDownloadsFolder {
                            Button(NSLocalizedString("sidebar_choose_folder", comment: "Button: choose folder")) {
                                importingFolder = true
                            }
                        } else {
                            Button(NSLocalizedString("sidebar_set_to_downloads", comment: "Button: set destination to downloads folder")) {
                                vm.resetToDownloadsFolder()
                            }
                        }
                        Button(NSLocalizedString("sidebar_open_folder", comment: "Button: open folder")) {
                            vm.openDestination()
                        }
                        Button(NSLocalizedString("sidebar_icloud_drive", comment: "Button: set iCloud Drive as destination")) {
                            vm.setDestinationToICloud()
                        }
                    }
                }
            }

            Button {
                vm.startStagedURLs()
            } label: {
                Label(NSLocalizedString("sidebar_start", comment: "Button: start downloads"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.stagedURLs.isEmpty)

            Button(NSLocalizedString("sidebar_cancel_current", comment: "Button: cancel current download")) {
                vm.cancelCurrent()
            }
            .disabled(!vm.isRunning)

            HStack {
                Button(NSLocalizedString("sidebar_capture_m3u8", comment: "Button: capture m3u8")) {
                    vm.openSafariM3U8Helper()
                }

                Button(NSLocalizedString("sidebar_open_handbrake", comment: "Button: open HandBrake")) {
                    vm.openHandBrake()
                }
            }

        }
        .padding(20)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380)
    }

    private var detailView: some View {
        TabView {
            queueTab
                .tabItem { Label(NSLocalizedString("tab_queue", comment: "Tab: download queue"), systemImage: "list.bullet.rectangle") }

            historyTab
                .tabItem { Label(NSLocalizedString("tab_history", comment: "Tab: history"), systemImage: "clock.arrow.circlepath") }
        }
    }

    private var queueTab: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("queue_title", comment: "Queue tab title"))
                        .font(.title2.bold())
                    Text(NSLocalizedString("queue_hint", comment: "Queue tab double-click hint"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(NSLocalizedString("sidebar_clear", comment: "Button: clear finished downloads"), role: .destructive) {
                    vm.clearDownloadedJobs()
                }
                .buttonStyle(.bordered)
                .disabled(!vm.jobs.contains(where: { $0.status == .finished || $0.status == .cancelled || $0.status == .failed }))
            }
            .padding(20)

            Divider()

            Table(vm.jobs, selection: $vm.selectedJobID) {
                TableColumn(NSLocalizedString("col_created", comment: "Table column: created date")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .width(min: 120, ideal: 145)

                TableColumn("") { job in
                    ContextMenuCell(vm: vm, job: job) {
                        if let thumbURL = job.thumbnailURL, let url = URL(string: thumbURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color.secondary.opacity(0.15))
                            }
                            .frame(width: 48, height: 27)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .width(56)

                TableColumn(NSLocalizedString("col_preset", comment: "Table column: preset")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        Text(job.presetName + (job.extractAudioOnlyAsMP3 ? " · MP3" : ""))
                    }
                }
                .width(min: 110, ideal: 140)

                TableColumn(NSLocalizedString("col_url", comment: "Table column: URL")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        Text(job.sourceURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                TableColumn(NSLocalizedString("col_progress", comment: "Table column: progress")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        VStack(alignment: .leading, spacing: 4) {
                            JobProgressView(job: job)

                            HStack(spacing: 8) {
                                if let pct = job.progressPercent {
                                    Text(String(format: "%.1f%%", pct))
                                } else if job.status == .running {
                                    Text("Descarga en curso…")
                                } else {
                                    Text("—")
                                }
                                if job.status == .running && !job.speedText.isEmpty { Text(job.speedText) }
                                if job.status == .running && !job.etaText.isEmpty { Text("ETA \(job.etaText)") }
                                if !job.mediaInfo.isEmpty { Text(job.mediaInfo) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 200, ideal: 260)

                TableColumn(NSLocalizedString("col_status", comment: "Table column: status")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        HStack(spacing: 4) {
                            Text(job.status.localizedLabel)
                            if job.integrityStatus == "ok" {
                                Text("✓").foregroundStyle(.green).font(.caption)
                            } else if job.integrityStatus == "corrupt" {
                                Text("⚠️").font(.caption)
                            }
                        }
                    }
                }
                .width(min: 100, ideal: 130)

                TableColumn(NSLocalizedString("col_file", comment: "Table column: output file")) { job in
                    ContextMenuCell(vm: vm, job: job) {
                        Text(job.outputFile.isEmpty ? "—" : job.outputFile)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .width(min: 160, ideal: 230)
            }
            .padding(.horizontal, 12)
            .onKeyPress(.space) {
                if let job = vm.jobs.first(where: { $0.id == vm.selectedJobID }),
                   job.status == .finished {
                    vm.toggleQuickLook(for: job)
                    return .handled
                }
                return .ignored
            }
            .onTapGesture(count: 2) {
                if let selectedJobID = vm.selectedJobID {
                    vm.rerun(jobID: selectedJobID)
                }
            }

            Divider()

            if let selected = vm.jobs.first(where: { $0.id == vm.selectedJobID }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("detail_title", comment: "Detail panel title"))
                                .font(.headline)
                            Text(selected.outputFile.isEmpty ? NSLocalizedString("detail_no_file_yet", comment: "Detail: no output file detected yet") : selected.outputFile)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()

                        // Pause / Resume
                        if selected.status == .running {
                            Button(NSLocalizedString("detail_pause", comment: "Button: pause download")) {
                                vm.pauseJob(jobID: selected.id)
                            }
                            .buttonStyle(.bordered)
                        }
                        if selected.status == .paused {
                            Button(NSLocalizedString("detail_resume", comment: "Button: resume download")) {
                                vm.resumeJob(jobID: selected.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        // Scheduler
                        if selected.status == .queued || selected.status == .scheduled {
                            Button(NSLocalizedString("detail_schedule", comment: "Button: schedule download")) {
                                vm.schedulerJobID = selected.id
                                vm.scheduledDate = Date().addingTimeInterval(3600)
                                vm.showSchedulerSheet = true
                            }
                            .buttonStyle(.bordered)
                        }

                        // Quality picker
                        if selected.status == .queued || selected.status == .scheduled {
                            Button(NSLocalizedString("detail_quality", comment: "Button: pick quality")) {
                                vm.fetchFormats(for: selected.sourceURL, jobID: selected.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        if selected.status == .failed && !selected.extractAudioOnlyAsMP3 {
                            Button(NSLocalizedString("detail_retry_no_mp4", comment: "Button: retry without MP4")) {
                                vm.retryWithoutMP4(for: selected.id)
                            }
                        }

                        Button(NSLocalizedString("detail_open_file", comment: "Button: open output file")) {
                            vm.openOutput(for: selected)
                        }

                        Button(NSLocalizedString("detail_open_folder", comment: "Button: open containing folder")) {
                            vm.openFolder(for: selected)
                        }

                        if selected.status == .finished {
                            Button(NSLocalizedString("quick_look", comment: "Button: Quick Look")) {
                                vm.openQuickLook(for: selected)
                            }
                        }

                        Button(vm.logViewerJobID == selected.id ? NSLocalizedString("detail_hide_log", comment: "Button: hide log") : NSLocalizedString("detail_show_log", comment: "Button: show log")) {
                            vm.toggleLog(for: selected.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        JobProgressView(job: selected)

                        HStack(spacing: 12) {
                            Text(selected.progressPercent != nil ? String(format: "%.1f%%", selected.progressPercent!) : NSLocalizedString("detail_no_percent", comment: "No progress percentage available"))
                            if selected.status == .running && !selected.speedText.isEmpty { Text(String(format: NSLocalizedString("detail_speed_fmt", comment: "Speed label: %@ is the speed value"), selected.speedText)) }
                            if selected.status == .running && !selected.etaText.isEmpty { Text("ETA: \(selected.etaText)") }
                            if let sched = selected.scheduledAt, selected.status == .scheduled {
                                Text(String(format: NSLocalizedString("detail_scheduled_fmt", comment: "Scheduled label: %@ is formatted date"), sched.formatted(date: .abbreviated, time: .shortened)))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !selected.errorSummary.isEmpty && (selected.status == .failed || selected.status == .cancelled) {
                        Text(selected.errorSummary)
                            .foregroundStyle(.red)
                    }

                    if vm.logViewerJobID == selected.id {
                        ScrollView {
                            Text(selected.log.isEmpty ? NSLocalizedString("detail_no_log_yet", comment: "No log output yet") : selected.log)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView(NSLocalizedString("detail_select_download", comment: "Prompt to select a download"), systemImage: "tray")
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filter bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("history_title", comment: "History tab title"))
                        .font(.title2.bold())
                    Spacer()
                    Button(NSLocalizedString("history_export_csv", comment: "Button: export CSV")) {
                        vm.saveExportToFile(
                            content: vm.exportHistoryAsCSV(),
                            filename: "historial-video-grabber.csv"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button(NSLocalizedString("history_export_json", comment: "Button: export JSON")) {
                        vm.saveExportToFile(
                            content: vm.exportHistoryAsJSON(),
                            filename: "historial-video-grabber.json"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button(NSLocalizedString("history_clear", comment: "Button: clear all history"), role: .destructive) {
                        vm.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.history.isEmpty)
                }

                HStack(spacing: 12) {
                    // Status filter
                    Picker(NSLocalizedString("history_filter_status", comment: "Picker label: filter by status"), selection: $vm.historyFilterStatus) {
                        Text(NSLocalizedString("filter_all", comment: "Filter option: all")).tag("Todos")
                        Text(NSLocalizedString("filter_completed", comment: "Filter option: completed")).tag("Completado")
                        Text(NSLocalizedString("filter_error", comment: "Filter option: error")).tag("Error")
                        Text(NSLocalizedString("filter_cancelled", comment: "Filter option: cancelled")).tag("Cancelado")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)

                    // Preset filter
                    Picker(NSLocalizedString("history_filter_platform", comment: "Picker label: filter by platform"), selection: $vm.historyFilterPreset) {
                        Text(NSLocalizedString("filter_all", comment: "Filter option: all")).tag("Todos")
                        ForEach(DownloadPreset.all) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    // Date from
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("history_date_from", comment: "Date filter label: from"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { vm.historyFilterDateFrom ?? Date.distantPast },
                                set: { vm.historyFilterDateFrom = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(width: 110)
                        if vm.historyFilterDateFrom != nil {
                            Button(action: { vm.historyFilterDateFrom = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Date to
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("history_date_to", comment: "Date filter label: to"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { vm.historyFilterDateTo ?? Date() },
                                set: { vm.historyFilterDateTo = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(width: 110)
                        if vm.historyFilterDateTo != nil {
                            Button(action: { vm.historyFilterDateTo = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Text(String(format: NSLocalizedString("history_results_count", comment: "Result count label: %d is the count"), vm.filteredHistory.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            Divider()

            Table(vm.filteredHistory) {
                TableColumn(NSLocalizedString("col_date", comment: "History table column: date")) { item in
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(NSLocalizedString("copy", comment: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.createdAt.formatted(date: .abbreviated, time: .shortened), forType: .string)
                            }
                        }
                }
                .width(min: 120, ideal: 145)

                TableColumn(NSLocalizedString("col_preset", comment: "Table column: preset")) { item in
                    Text(item.presetName)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(NSLocalizedString("copy", comment: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.presetName, forType: .string)
                            }
                        }
                }
                .width(min: 110, ideal: 140)

                TableColumn(NSLocalizedString("col_url", comment: "Table column: URL")) { item in
                    Text(item.sourceURL)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(NSLocalizedString("copy", comment: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.sourceURL, forType: .string)
                            }
                        }
                }

                TableColumn(NSLocalizedString("col_file", comment: "Table column: output file")) { item in
                    Text(item.outputFile)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(NSLocalizedString("copy", comment: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.outputFile, forType: .string)
                            }
                        }
                }

                TableColumn(NSLocalizedString("col_status", comment: "Table column: status")) { item in
                    Text(item.status)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(NSLocalizedString("copy", comment: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.status, forType: .string)
                            }
                        }
                }
                .width(min: 100, ideal: 120)
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }
}

// MARK: - Staged URL Row

struct StagedURLRow: View {
    let stagedID: UUID
    let onUpdate: (StagedURL) -> Void
    let onRemove: () -> Void
    @State private var local: StagedURL
    @State private var showPopover = false

    init(staged: StagedURL, onUpdate: @escaping (StagedURL) -> Void, onRemove: @escaping () -> Void) {
        self.stagedID = staged.id
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        self._local = State(initialValue: staged)
    }

    var body: some View {
        HStack(spacing: 6) {
            if local.isEditing {
                TextField("", text: $local.urlString, onCommit: { local.isEditing = false })
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand { local.isEditing = false }
            } else {
                Text(local.urlString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { local.isEditing = true }
            }

            Button {
                showPopover = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                StagedURLSettingsView(staged: $local)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .onChange(of: local) { _, updated in
            onUpdate(updated)
        }
    }
}

// MARK: - Staged URL Settings Popover

struct StagedURLSettingsView: View {
    @Binding var staged: StagedURL
    @State private var isFetchingDuration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("staged_settings_title", comment: "Popover title: per-URL settings"))
                .font(.headline)

            Divider()

            Toggle(NSLocalizedString("sidebar_auto_detect", comment: "Toggle: auto-detect platform"), isOn: $staged.autoDetectPlatform)
            if !staged.autoDetectPlatform {
                Picker(NSLocalizedString("sidebar_manual_preset", comment: "Picker: manual preset"), selection: $staged.selectedPreset) {
                    ForEach(DownloadPreset.all) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            Toggle(NSLocalizedString("sidebar_extract_mp3", comment: "Toggle: extract MP3"), isOn: $staged.extractAudioOnlyAsMP3)

            Toggle(NSLocalizedString("trim_video", comment: "Toggle: trim video"), isOn: $staged.trimEnabled)
                .onChange(of: staged.trimEnabled) { _, enabled in
                    if !enabled {
                        staged.trimStartH = 0; staged.trimStartM = 0; staged.trimStartS = 0
                        staged.trimEndH = 0; staged.trimEndM = 0; staged.trimEndS = 0
                    } else {
                        isFetchingDuration = true
                        DownloaderViewModel.shared.fetchDuration(for: staged.urlString) { h, m, s in
                            isFetchingDuration = false
                            staged.trimEndH = h; staged.trimEndM = m; staged.trimEndS = s
                        }
                    }
                }
            if staged.trimEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    TimecodeEditor(label: "Start", h: $staged.trimStartH, m: $staged.trimStartM, s: $staged.trimStartS)
                    HStack {
                        TimecodeEditor(label: "End  ", h: $staged.trimEndH, m: $staged.trimEndM, s: $staged.trimEndS)
                        if isFetchingDuration {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            if !staged.extractAudioOnlyAsMP3 {
                Picker("Formato de salida", selection: $staged.convertToFormat) {
                    Text("Conservar el formato original").tag("")
                    Text("Máxima compatibilidad (H.264 + AAC)").tag("mp4")
                    Divider()
                    Text("MKV").tag("mkv")
                    Text("AVI").tag("avi")
                    Text("MOV").tag("mov")
                    Text("WebM").tag("webm")
                }
                .pickerStyle(.menu)
            }

            Divider()

            Toggle(NSLocalizedString("sidebar_subtitles", comment: "Toggle: download subtitles"), isOn: $staged.downloadSubtitles)

            HStack(spacing: 8) {
                Toggle(NSLocalizedString("sidebar_compress_target", comment: "Toggle: compress to target size"), isOn: $staged.enableTargetFileSize)
                if staged.enableTargetFileSize {
                    HStack(spacing: 4) {
                        TextField("MB", value: $staged.targetFileSizeMB, format: .number)
                            .frame(width: 55)
                            .textFieldStyle(.roundedBorder)
                        Text("MB").foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(NSLocalizedString("verify_integrity", comment: "Toggle: verify file integrity"), isOn: $staged.verifyIntegrity)
        }
        .padding(16)
        .frame(minWidth: 260)
    }
}

// MARK: - Timecode Editor

struct TimecodeEditor: View {
    let label: String
    @Binding var h: Int
    @Binding var m: Int
    @Binding var s: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            IntTimeField(value: $h, maxValue: 99)
            Text("h").font(.caption2).foregroundStyle(.secondary)
            Text(":").foregroundStyle(.tertiary)
            IntTimeField(value: $m, maxValue: 59)
            Text("m").font(.caption2).foregroundStyle(.secondary)
            Text(":").foregroundStyle(.tertiary)
            IntTimeField(value: $s, maxValue: 59)
            Text("s").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct IntTimeField: View {
    @Binding var value: Int
    let maxValue: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .frame(width: 32)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = value == 0 ? "0" : "\(value)" }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                if let n = Int(digits) {
                    let clamped = min(n, maxValue)
                    value = clamped
                    if n > maxValue { text = "\(clamped)" }
                } else if digits.isEmpty {
                    value = 0
                }
            }
            .onChange(of: value) { _, new in
                let s = "\(new)"
                if text != s { text = s }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    text = "\(value)"
                }
            }
    }
}

// MARK: - M3U8 Helper

struct M3U8HelperView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("m3u8_title", comment: "M3U8 helper title"))
                .font(.title.bold())

            Text(NSLocalizedString("m3u8_description", comment: "M3U8 helper description"))
                .foregroundStyle(.secondary)

            GroupBox(NSLocalizedString("m3u8_workflow_header", comment: "M3U8 recommended workflow header")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("m3u8_step_1", comment: "M3U8 step 1"))
                    Text(NSLocalizedString("m3u8_step_2", comment: "M3U8 step 2"))
                    Text(NSLocalizedString("m3u8_step_3", comment: "M3U8 step 3"))
                    Text(NSLocalizedString("m3u8_step_4", comment: "M3U8 step 4"))
                    Text(NSLocalizedString("m3u8_step_5", comment: "M3U8 step 5"))
                }
            }

            GroupBox(NSLocalizedString("m3u8_future_header", comment: "M3U8 future evolution header")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("m3u8_future_1", comment: "M3U8 future item 1"))
                    Text(NSLocalizedString("m3u8_future_2", comment: "M3U8 future item 2"))
                    Text(NSLocalizedString("m3u8_future_3", comment: "M3U8 future item 3"))
                }
                .font(.callout)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 420)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

// MARK: - Update Checker

final class UpdateChecker {
    static let shared = UpdateChecker()
    private let releasesURL = URL(string: "https://api.github.com/repos/charlysole/video-grabber/releases/latest")!
    private var progressWindow: NSWindow?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Called on launch — only shows UI if an update is available.
    func checkSilently() {
        fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let info) where self.isNewer(info.version):
                DispatchQueue.main.async { self.showUpdateAlert(version: info.version, dmgURL: info.dmgURL, manual: false) }
            default:
                break
            }
        }
    }

    /// Called from the menu — always shows a result.
    func checkManually() {
        fetch { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    if self.isNewer(info.version) {
                        self.showUpdateAlert(version: info.version, dmgURL: info.dmgURL, manual: true)
                    } else {
                        self.showUpToDateAlert()
                    }
                case .failure:
                    self.showErrorAlert()
                }
            }
        }
    }

    private func fetch(completion: @escaping (Result<(version: String, dmgURL: URL?), Error>) -> Void) {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VideoGrabber/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error { completion(.failure(error)); return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 404 means no releases exist yet — treat as "up to date"
            if statusCode == 404 { completion(.success((self.currentVersion, nil))); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(.failure(URLError(.cannotParseResponse))); return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            var dmgURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                let dmgAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                dmgURL = (dmgAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
            }
            completion(.success((version, dmgURL)))
        }.resume()
    }

    private func isNewer(_ remote: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = currentVersion.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private func showUpdateAlert(version: String, dmgURL: URL?, manual: Bool) {
        let alert = NSAlert()
        alert.messageText = "Update Available — v\(version)"
        alert.informativeText = "You are running v\(currentVersion). Version \(version) is available."
        alert.addButton(withTitle: dmgURL != nil ? "Install Update" : "Download Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let dmgURL {
                downloadAndInstall(dmgURL: dmgURL, version: version)
            } else {
                NSWorkspace.shared.open(URL(string: "https://github.com/charlysole/video-grabber/releases/latest")!)
            }
        }
    }

    private func downloadAndInstall(dmgURL: URL, version: String) {
        let dmgDest    = URL(fileURLWithPath: "/tmp/VGUpdate.dmg")
        let mountPoint = "/tmp/VGMount"
        let appName    = "Video Grabber.app"

        showProgressPanel(title: "Downloading v\(version)…")

        URLSession.shared.downloadTask(with: dmgURL) { [weak self] tempURL, _, error in
            guard let self else { return }

            DispatchQueue.main.async { self.dismissProgressPanel() }

            if let error {
                DispatchQueue.main.async { self.showInstallErrorAlert(error.localizedDescription) }
                return
            }
            guard let tempURL else { return }

            // Move downloaded DMG to /tmp
            try? FileManager.default.removeItem(at: dmgDest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dmgDest)
            } catch {
                DispatchQueue.main.async { self.showInstallErrorAlert(error.localizedDescription) }
                return
            }

            // Mount the DMG
            guard self.runShell("hdiutil attach \"\(dmgDest.path)\" -nobrowse -quiet -mountpoint \"\(mountPoint)\"") == 0 else {
                DispatchQueue.main.async { self.showInstallErrorAlert("Could not mount the update disk image.") }
                return
            }

            // Ask user to confirm before requesting admin password
            DispatchQueue.main.async {
                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Ready to Install v\(version)"
                confirmAlert.informativeText = "Video Grabber will close and reopen with the new version. Your admin password is required to replace the app in /Applications."
                confirmAlert.addButton(withTitle: "Install & Restart")
                confirmAlert.addButton(withTitle: "Cancel")

                guard confirmAlert.runModal() == .alertFirstButtonReturn else {
                    _ = self.runShell("hdiutil detach \"\(mountPoint)\" -quiet")
                    try? FileManager.default.removeItem(at: dmgDest)
                    return
                }

                // Run the privileged copy synchronously via AppleScript.
                // Only the cp+xattr steps need admin — open and terminate are done
                // by the app itself (as the correct user), avoiding the root-context problem.
                let escapedMount   = mountPoint.replacingOccurrences(of: "'", with: "'\\''")
                let escapedAppName = appName.replacingOccurrences(of: "'", with: "'\\''")
                let appleScript = """
                do shell script "cp -Rf '\(escapedMount)/\(escapedAppName)' '/Applications/' && xattr -dr com.apple.quarantine '/Applications/\(escapedAppName)' && hdiutil detach '\(escapedMount)' -quiet" with administrator privileges
                """

                DispatchQueue.global(qos: .userInitiated).async {
                    var asError: NSDictionary?
                    NSAppleScript(source: appleScript)?.executeAndReturnError(&asError)

                    // Clean up DMG regardless
                    try? FileManager.default.removeItem(at: dmgDest)

                    if let asError {
                        // -128 = user cancelled the auth dialog — no error to show
                        let errorNumber = asError["NSAppleScriptErrorNumber"] as? Int ?? 0
                        _ = self.runShell("hdiutil detach \"\(mountPoint)\" -quiet")
                        if errorNumber != -128 {
                            let msg = asError["NSAppleScriptErrorMessage"] as? String ?? "Installation failed."
                            DispatchQueue.main.async { self.showInstallErrorAlert(msg) }
                        }
                        return
                    }

                    // Copy succeeded — open the new version (as the current user) then quit
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(appName)"))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }.resume()
    }

    private func showProgressPanel(title: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 76),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.center()

        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = true
        bar.frame = NSRect(x: 20, y: 28, width: 280, height: 20)
        bar.startAnimation(nil)
        panel.contentView?.addSubview(bar)
        panel.makeKeyAndOrderFront(nil)
        progressWindow = panel
    }

    private func dismissProgressPanel() {
        progressWindow?.close()
        progressWindow = nil
    }

    @discardableResult
    private func runShell(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func showInstallErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Video Grabber v\(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub. Please check your internet connection."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
