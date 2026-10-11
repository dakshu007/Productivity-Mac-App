import Foundation

/// Describes the newest published build. CI writes it as `latest.json` next to
/// the DMG in the "latest build" release.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public var version: String
    public var build: Int
    public var dmgURL: URL
    public var sha256: String?
    public var releaseNotesURL: URL?
    public var publishedAt: Date?
    public var minimumSystemVersion: String?
    /// True when the DMG is Developer ID signed and notarized.
    public var notarized: Bool?

    public init(version: String, build: Int, dmgURL: URL, sha256: String? = nil, releaseNotesURL: URL? = nil, publishedAt: Date? = nil, minimumSystemVersion: String? = nil, notarized: Bool? = nil) {
        self.version = version
        self.build = build
        self.dmgURL = dmgURL
        self.sha256 = sha256
        self.releaseNotesURL = releaseNotesURL
        self.publishedAt = publishedAt
        self.minimumSystemVersion = minimumSystemVersion
        self.notarized = notarized
    }

    public static func decode(_ data: Data) throws -> UpdateManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return try decoder.decode(UpdateManifest.self, from: data)
    }
}

public enum UpdateComparison {
    /// Numeric, dot-separated comparison ("1.10.0" > "1.9.2"). Non-numeric parts count as 0.
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Whether `manifest` is newer than the running app. The version decides first;
    /// for the same version a higher build number (CI run) is newer.
    public static func isNewer(_ manifest: UpdateManifest, thanVersion version: String, build: Int) -> Bool {
        switch compareVersions(manifest.version, version) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return manifest.build > build
        }
    }

    /// Whether this Mac can run the update.
    public static func isSupported(_ manifest: UpdateManifest, systemVersion: OperatingSystemVersion) -> Bool {
        guard let minimum = manifest.minimumSystemVersion else { return true }
        let current = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        return compareVersions(current, minimum) != .orderedAscending
    }
}
