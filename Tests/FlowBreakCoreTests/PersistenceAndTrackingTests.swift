import XCTest
@testable import FlowBreakCore

final class PersistenceTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBreakTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripThroughJSONFiles() throws {
        let store = JSONFileStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = TimerEngine(store: store, configuration: TimerConfiguration())
        engine.startFocus(at: start)
        engine.pause(at: start.addingTimeInterval(90))
        XCTAssertNil(engine.lastPersistenceError)

        let reloaded = TimerEngine(store: JSONFileStore(directory: directory), configuration: TimerConfiguration())
        XCTAssertEqual(reloaded.phase, .focusing)
        XCTAssertEqual(reloaded.current?.status, .paused)
        XCTAssertEqual(reloaded.current?.remainingAtPause ?? 0, 45 * 60 - 90, accuracy: 0.01)
        XCTAssertEqual(reloaded.sessions.count, 1)
    }

    func testCorruptFileIsBackedUpAndReported() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = JSONFileStore(directory: directory)
        try Data("not json".utf8).write(to: store.sessionsURL)
        let engine = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertNotNil(engine.lastPersistenceError)
        XCTAssertTrue(engine.sessions.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.contains("corrupt") })
    }

    func testSettingsDecodeMissingKeysWithDefaults() throws {
        let json = Data(#"{"focusMinutes": 60, "repeatCount": 99}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.focusMinutes, 60)
        XCTAssertEqual(settings.repeatCount, 12, "clamped to the maximum")
        XCTAssertEqual(settings.shortBreakMinutes, 5)
        XCTAssertFalse(settings.appTrackingEnabled, "tracking is off by default")
    }

    func testCSVEscapesFormulasAndCommas() {
        XCTAssertEqual(DataExporter.escape("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(DataExporter.escape("Foo, Inc"), "\"Foo, Inc\"")
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormatter.clock(45 * 60), "45:00")
        XCTAssertEqual(DurationFormatter.clock(3725), "1:02:05")
        XCTAssertEqual(DurationFormatter.clock(0.2), "00:01")
        XCTAssertEqual(DurationFormatter.short(125 * 60), "2h 05m")
        XCTAssertEqual(DurationFormatter.short(0), "0m")
    }
}

final class UsageTrackingTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testOffByDefaultRecordsNothing() {
        var samples: [UsageSample] = []
        let recorder = UsageRecorder(policy: UsagePolicy(settings: AppSettings())) { samples.append($0) }
        recorder.appActivated(bundleID: "com.apple.Safari", appName: "Safari", at: t0)
        recorder.appActivated(bundleID: "com.apple.mail", appName: "Mail", at: t0.addingTimeInterval(60))
        recorder.suspend(at: t0.addingTimeInterval(120))
        XCTAssertTrue(samples.isEmpty)
    }

    func testRecordsSwitchesAndExcludesApps() {
        var samples: [UsageSample] = []
        let policy = UsagePolicy(enabled: true, privateMode: false, excludedBundleIDs: ["com.secret.app"])
        let recorder = UsageRecorder(policy: policy) { samples.append($0) }
        recorder.appActivated(bundleID: "com.apple.Safari", appName: "Safari", at: t0)
        recorder.appActivated(bundleID: "com.secret.app", appName: "Secret", at: t0.addingTimeInterval(60))
        recorder.appActivated(bundleID: "com.apple.mail", appName: "Mail", at: t0.addingTimeInterval(90))
        recorder.suspend(at: t0.addingTimeInterval(150))
        XCTAssertEqual(samples.map(\.appName), ["Safari", "Mail"])
        XCTAssertEqual(samples.map(\.duration), [60, 60])
    }

    func testPrivateModePausesRecording() {
        var samples: [UsageSample] = []
        let recorder = UsageRecorder(policy: UsagePolicy(enabled: true, privateMode: false, excludedBundleIDs: [])) { samples.append($0) }
        recorder.appActivated(bundleID: "a", appName: "A", at: t0)
        recorder.update(policy: UsagePolicy(enabled: true, privateMode: true, excludedBundleIDs: []), at: t0.addingTimeInterval(30))
        recorder.appActivated(bundleID: "b", appName: "B", at: t0.addingTimeInterval(40))
        recorder.suspend(at: t0.addingTimeInterval(100))
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.duration, 30)
    }

    func testAggregateClipsToInterval() {
        let samples = [
            UsageSample(bundleID: "a", appName: "A", start: t0, end: t0.addingTimeInterval(100)),
            UsageSample(bundleID: "b", appName: "B", start: t0.addingTimeInterval(100), end: t0.addingTimeInterval(130)),
            UsageSample(bundleID: "a", appName: "A", start: t0.addingTimeInterval(130), end: t0.addingTimeInterval(200)),
        ]
        let result = UsageAggregator.aggregate(samples, in: DateInterval(start: t0.addingTimeInterval(50), end: t0.addingTimeInterval(180)))
        XCTAssertEqual(result.map(\.bundleID), ["a", "b"])
        XCTAssertEqual(result.first?.duration, 100)
    }
}
