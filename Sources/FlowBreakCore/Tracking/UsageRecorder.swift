import Foundation

/// One stretch of time an application was frontmost. Only the app's bundle
/// identifier and display name are stored — never window titles, documents,
/// keystrokes, or screenshots.
public struct UsageSample: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), bundleID: String, appName: String, start: Date, end: Date) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public struct UsagePolicy: Equatable, Sendable {
    public var enabled: Bool
    public var privateMode: Bool
    public var excludedBundleIDs: Set<String>

    public init(enabled: Bool, privateMode: Bool, excludedBundleIDs: Set<String>) {
        self.enabled = enabled
        self.privateMode = privateMode
        self.excludedBundleIDs = excludedBundleIDs
    }

    public init(settings: AppSettings) {
        self.init(enabled: settings.appTrackingEnabled, privateMode: settings.privateMode, excludedBundleIDs: Set(settings.excludedBundleIDs))
    }

    public var isRecording: Bool { enabled && !privateMode }

    public func allows(_ bundleID: String) -> Bool {
        isRecording && !excludedBundleIDs.contains(bundleID)
    }
}

/// Turns "app X became frontmost" / "user went idle" events into usage samples.
/// Platform code feeds events in; this type decides what (if anything) is recorded.
/// Nothing is recorded unless the user has enabled tracking.
public final class UsageRecorder {
    /// Samples shorter than this are dropped as noise (e.g. app-switcher flicks).
    public static let minimumSample: TimeInterval = 2

    public private(set) var policy: UsagePolicy
    public private(set) var open: (bundleID: String, appName: String, start: Date)?
    private let emit: (UsageSample) -> Void

    public init(policy: UsagePolicy, emit: @escaping (UsageSample) -> Void) {
        self.policy = policy
        self.emit = emit
    }

    /// The frontmost application changed (or tracking resumed with it frontmost).
    public func appActivated(bundleID: String, appName: String, at date: Date) {
        if let current = open, current.bundleID == bundleID { return }
        close(at: date)
        guard policy.allows(bundleID) else { return }
        open = (bundleID, appName, date)
    }

    /// The user went idle, the screen locked, or the Mac is going to sleep.
    /// `date` should be the last moment the user was active.
    public func suspend(at date: Date) {
        close(at: date)
    }

    public func update(policy newPolicy: UsagePolicy, at date: Date) {
        policy = newPolicy
        if let current = open, !newPolicy.allows(current.bundleID) {
            close(at: date)
        }
    }

    /// Splits the open sample at `date` so long sessions are saved periodically.
    public func checkpoint(at date: Date) {
        guard let current = open else { return }
        close(at: date)
        if policy.allows(current.bundleID) {
            open = (current.bundleID, current.appName, date)
        }
    }

    private func close(at date: Date) {
        guard let current = open else { return }
        open = nil
        let end = max(current.start, date)
        guard end.timeIntervalSince(current.start) >= UsageRecorder.minimumSample else { return }
        emit(UsageSample(bundleID: current.bundleID, appName: current.appName, start: current.start, end: end))
    }
}

public struct UsageAggregate: Equatable, Identifiable, Sendable {
    public var bundleID: String
    public var appName: String
    public var duration: TimeInterval
    public var id: String { bundleID }
}

public enum UsageAggregator {
    /// Total foreground time per app inside `interval`, largest first.
    public static func aggregate(_ samples: [UsageSample], in interval: DateInterval) -> [UsageAggregate] {
        var totals: [String: UsageAggregate] = [:]
        for sample in samples {
            let start = max(sample.start, interval.start)
            let end = min(sample.end, interval.end)
            let overlap = end.timeIntervalSince(start)
            guard overlap > 0 else { continue }
            var entry = totals[sample.bundleID] ?? UsageAggregate(bundleID: sample.bundleID, appName: sample.appName, duration: 0)
            entry.duration += overlap
            entry.appName = sample.appName
            totals[sample.bundleID] = entry
        }
        return totals.values.sorted {
            $0.duration == $1.duration ? $0.appName < $1.appName : $0.duration > $1.duration
        }
    }
}
