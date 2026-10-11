import Foundation

public struct NudgePolicy: Equatable, Sendable {
    public var enabled: Bool
    public var distractingBundleIDs: Set<String>
    public var cooldown: TimeInterval

    public init(enabled: Bool, distractingBundleIDs: Set<String>, cooldown: TimeInterval = 300) {
        self.enabled = enabled
        self.distractingBundleIDs = distractingBundleIDs
        self.cooldown = cooldown
    }

    public init(settings: AppSettings) {
        self.init(
            enabled: settings.nudgesEnabled,
            distractingBundleIDs: Set(settings.distractingBundleIDs),
            cooldown: TimeInterval(settings.nudgeCooldownMinutes * 60)
        )
    }
}

/// Decides when a gentle "still on your task?" nudge is appropriate. It only ever
/// looks at which app came to the front; it never blocks anything.
///
/// Rules: only during a *running* focus session; only for apps the user marked as
/// distracting; at most once per app per cooldown; never again for an app the user
/// allowed for this session. State resets when a new session starts.
public final class NudgeTracker {
    private var sessionID: UUID?
    private var lastNudge: [String: Date] = [:]
    private var allowed: Set<String> = []

    public init() {}

    public func shouldNudge(bundleID: String, state: EngineState, policy: NudgePolicy, now: Date) -> Bool {
        guard policy.enabled,
              state.phase == .focusing,
              let session = state.current, session.status == .running, session.kind.isFocus,
              policy.distractingBundleIDs.contains(bundleID) else { return false }
        if session.id != sessionID {
            sessionID = session.id
            lastNudge = [:]
            allowed = []
        }
        if allowed.contains(bundleID) { return false }
        if let last = lastNudge[bundleID], now.timeIntervalSince(last) < policy.cooldown { return false }
        return true
    }

    public func recordNudge(bundleID: String, now: Date) {
        lastNudge[bundleID] = now
    }

    /// "Allow for this session": no more nudges for this app until the next session.
    public func allowForSession(bundleID: String) {
        allowed.insert(bundleID)
    }
}
