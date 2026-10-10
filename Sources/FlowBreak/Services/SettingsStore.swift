import Foundation
import FlowBreakCore
import os

enum Log {
    static let app = Logger(subsystem: "app.flowbreak.mac", category: "app")
    static let timer = Logger(subsystem: "app.flowbreak.mac", category: "timer")
    static let notifications = Logger(subsystem: "app.flowbreak.mac", category: "notifications")
    static let tracking = Logger(subsystem: "app.flowbreak.mac", category: "tracking")
}

/// Preferences live in UserDefaults as one versioned JSON blob; session and usage
/// history live in JSON files (see `JSONFileStore`).
final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "FlowBreak.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.app.error("Settings unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            Log.app.error("Settings could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
