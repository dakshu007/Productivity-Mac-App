import AppKit
import CoreServices
import CryptoKit
import FlowBreakCore

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateManifest)
    case unsupported(UpdateManifest)
    case downloading(UpdateManifest)
    case downloaded(URL)
    case failed(String)
}

/// Checks the "latest build" release for a newer FlowBreak. Contacts GitHub only
/// when the user asks or has turned on automatic checks. Downloads are verified
/// against the published SHA-256 and marked as downloaded files, so Gatekeeper
/// checks them exactly like a browser download.
@MainActor
final class UpdateService {
    static let defaultManifestURL = URL(string: "https://github.com/dakshu007/Productivity-Mac-App/releases/download/latest-build/latest.json")
    static let checkInterval: TimeInterval = 24 * 3600

    var manifestURL: URL? {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "FBUpdateManifestURL") as? String, let url = URL(string: custom) {
            return url
        }
        return Self.defaultManifestURL
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "FlowBreak-UpdateCheck"]
        return URLSession(configuration: config)
    }()

    func check() async -> UpdateState {
        guard let url = manifestURL else { return .failed("No update address is configured.") }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("The update server answered unexpectedly.")
            }
            let manifest = try UpdateManifest.decode(data)
            guard UpdateComparison.isNewer(manifest, thanVersion: currentVersion, build: currentBuild) else {
                return .upToDate(Date())
            }
            guard UpdateComparison.isSupported(manifest, systemVersion: ProcessInfo.processInfo.operatingSystemVersion) else {
                return .unsupported(manifest)
            }
            return .available(manifest)
        } catch is DecodingError {
            return .failed("The update information couldn't be read.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Downloads the DMG to ~/Downloads, verifies its checksum, and opens it.
    func download(_ manifest: UpdateManifest) async -> UpdateState {
        do {
            let (temporary, response) = try await session.download(from: manifest.dmgURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("The download failed.")
            }
            let data = try Data(contentsOf: temporary)
            if let expected = manifest.sha256?.lowercased(), !expected.isEmpty {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else {
                    return .failed("The download didn't match its published checksum, so it was discarded.")
                }
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let destination = downloads.appendingPathComponent("FlowBreak-\(manifest.version)-\(manifest.build).dmg")
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination, options: .atomic)
            markAsDownloaded(destination, from: manifest.dmgURL)
            NSWorkspace.shared.open(destination)
            return .downloaded(destination)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Adds the standard quarantine attribute so macOS treats the file like any
    /// other download (Gatekeeper still checks it on first launch).
    private func markAsDownloaded(_ file: URL, from source: URL) {
        var url = file
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "FlowBreak",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineDataURLKey as String: source,
        ]
        try? url.setResourceValues(values)
    }
}
