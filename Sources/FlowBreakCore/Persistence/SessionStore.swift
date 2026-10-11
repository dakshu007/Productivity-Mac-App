import Foundation

/// Storage for the timer state and session history.
public protocol SessionPersisting: AnyObject {
    func loadState() throws -> EngineState?
    func saveState(_ state: EngineState) throws
    func loadSessions() throws -> [FocusSession]
    func saveSessions(_ sessions: [FocusSession]) throws
}

/// Storage for opt-in foreground-app usage samples.
public protocol UsagePersisting: AnyObject {
    func loadUsage() throws -> [UsageSample]
    func saveUsage(_ samples: [UsageSample]) throws
}

public enum PersistenceError: Error, LocalizedError, Equatable {
    case unreadable(file: String, underlying: String)
    case unwritable(file: String, underlying: String)
    case unsupportedVersion(file: String, version: Int)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(file, underlying):
            return "FlowBreak couldn't read \(file). A backup copy was kept. (\(underlying))"
        case let .unwritable(file, underlying):
            return "FlowBreak couldn't save \(file). (\(underlying))"
        case let .unsupportedVersion(file, version):
            return "\(file) was written by a newer FlowBreak (format \(version))."
        }
    }
}

/// Versioned envelope written to disk so the format can migrate later.
struct StoredFile<Payload: Codable>: Codable {
    var schemaVersion: Int
    var savedAt: Date
    var payload: Payload
}

/// JSON files under Application Support/FlowBreak. Writes are atomic.
public final class JSONFileStore: SessionPersisting, UsagePersisting {
    public static let schemaVersion = 1

    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("FlowBreak", isDirectory: true)
    }

    public init(directory: URL = JSONFileStore.defaultDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        self.decoder = decoder
    }

    public var stateURL: URL { directory.appendingPathComponent("state.json") }
    public var sessionsURL: URL { directory.appendingPathComponent("sessions.json") }
    public var usageURL: URL { directory.appendingPathComponent("usage.json") }

    public func loadState() throws -> EngineState? {
        try readFile(EngineState.self, from: stateURL)
    }

    public func saveState(_ state: EngineState) throws {
        try writeFile(state, to: stateURL)
    }

    public func loadSessions() throws -> [FocusSession] {
        try readFile([FocusSession].self, from: sessionsURL) ?? []
    }

    public func saveSessions(_ sessions: [FocusSession]) throws {
        try writeFile(sessions, to: sessionsURL)
    }

    public func loadUsage() throws -> [UsageSample] {
        try readFile([UsageSample].self, from: usageURL) ?? []
    }

    public func saveUsage(_ samples: [UsageSample]) throws {
        try writeFile(samples, to: usageURL)
    }

    /// Deletes every FlowBreak data file.
    public func deleteAll() throws {
        for url in [stateURL, sessionsURL, usageURL, directory.appendingPathComponent("tasks.json"), directory.appendingPathComponent("reflections.json")] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func readFile<T: Codable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PersistenceError.unreadable(file: url.lastPathComponent, underlying: error.localizedDescription)
        }
        do {
            let file = try decoder.decode(StoredFile<T>.self, from: data)
            if file.schemaVersion > JSONFileStore.schemaVersion {
                throw PersistenceError.unsupportedVersion(file: url.lastPathComponent, version: file.schemaVersion)
            }
            return file.payload
        } catch let error as PersistenceError {
            throw error
        } catch {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? fileManager.moveItem(at: url, to: backup)
            throw PersistenceError.unreadable(file: url.lastPathComponent, underlying: error.localizedDescription)
        }
    }

    func writeFile<T: Codable>(_ value: T, to url: URL) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = StoredFile(schemaVersion: JSONFileStore.schemaVersion, savedAt: Date(), payload: value)
            let data = try encoder.encode(file)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PersistenceError.unwritable(file: url.lastPathComponent, underlying: error.localizedDescription)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryStore: SessionPersisting, UsagePersisting {
    public var state: EngineState?
    public var sessions: [FocusSession] = []
    public var usage: [UsageSample] = []
    public var failWrites = false
    public private(set) var saveCount = 0

    public init(state: EngineState? = nil, sessions: [FocusSession] = []) {
        self.state = state
        self.sessions = sessions
    }

    public func loadState() throws -> EngineState? { state }
    public func saveState(_ state: EngineState) throws {
        if failWrites { throw PersistenceError.unwritable(file: "state.json", underlying: "test") }
        self.state = state
        saveCount += 1
    }
    public func loadSessions() throws -> [FocusSession] { sessions }
    public func saveSessions(_ sessions: [FocusSession]) throws {
        if failWrites { throw PersistenceError.unwritable(file: "sessions.json", underlying: "test") }
        self.sessions = sessions
    }
    public func loadUsage() throws -> [UsageSample] { usage }
    public func saveUsage(_ samples: [UsageSample]) throws { usage = samples }
}

extension JSONEncoder.DateEncodingStrategy {
    static var iso8601WithFractionalSeconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.formatter.string(from: date))
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601.formatter.date(from: string) ?? ISO8601.plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
    }
}

enum ISO8601 {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
