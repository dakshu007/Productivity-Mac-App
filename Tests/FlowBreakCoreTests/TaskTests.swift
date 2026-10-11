import XCTest
@testable import FlowBreakCore

final class TaskRepositoryTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func makeRepo(_ store: InMemoryTaskStore = InMemoryTaskStore()) -> TaskRepository {
        TaskRepository(store: store, calendar: calendar)
    }

    func testAddTitleOnlyAndRejectEmpty() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "  Write intro  "), at: date(12))
        XCTAssertEqual(task.title, "Write intro")
        XCTAssertEqual(task.status, .inbox)
        XCTAssertEqual(task.priority, .normal)
        XCTAssertThrowsError(try repo.add(TaskDraft(title: "   \n "), at: date(12))) { error in
            XCTAssertEqual(error as? TaskError, .emptyTitle)
        }
        XCTAssertEqual(repo.tasks.count, 1)
    }

    func testAddWithNotesDefinitionOfDoneAndTags() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "Ship page", notes: "Hero copy", definitionOfDone: "Deployed to production", tags: ["#Web", "web", " launch "]), at: date(12))
        XCTAssertEqual(task.definitionOfDone, "Deployed to production")
        XCTAssertEqual(task.notes, "Hero copy")
        XCTAssertEqual(task.tags, ["web", "launch"])
    }

    func testEditPreservesCreationMetadata() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "A"), at: date(12))
        let edited = repo.update(task.id, at: date(13)) {
            $0.title = "B"
            $0.createdAt = self.date(1)
            $0.id = UUID()
        }
        XCTAssertEqual(edited?.id, task.id)
        XCTAssertEqual(edited?.createdAt, date(12))
        XCTAssertEqual(edited?.updatedAt, date(13))
        XCTAssertEqual(edited?.title, "B")
        // Clearing the title is ignored.
        XCTAssertEqual(repo.update(task.id, at: date(14)) { $0.title = "  " }?.title, "B")
    }

    func testCompleteReopenAndUndo() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "A", status: .today), at: date(12))
        let completion = repo.complete(task.id, note: "Sent", at: date(12, 11))
        XCTAssertEqual(repo.task(task.id)?.status, .completed)
        XCTAssertEqual(repo.task(task.id)?.completedAt, date(12, 11))
        XCTAssertEqual(repo.task(task.id)?.completionNote, "Sent")
        XCTAssertNil(repo.complete(task.id, at: date(12, 12)), "completing twice is a no-op")

        repo.undo(try XCTUnwrap(completion), at: date(12, 11, 1))
        XCTAssertEqual(repo.task(task.id)?.status, .today)
        XCTAssertNil(repo.task(task.id)?.completedAt)

        repo.complete(task.id, at: date(12, 13))
        repo.reopen(task.id, at: date(12, 14))
        XCTAssertEqual(repo.task(task.id)?.status, .today)
        XCTAssertNil(repo.task(task.id)?.completedAt)
    }

    func testArchiveRestoreAndDeleteWithSubtasks() throws {
        let repo = makeRepo()
        let parent = try repo.add(TaskDraft(title: "Parent", status: .next), at: date(12))
        let child = try repo.add(TaskDraft(title: "Child", parentID: parent.id), at: date(12))
        repo.archive([parent.id], at: date(13))
        XCTAssertEqual(repo.task(parent.id)?.status, .archived)
        XCTAssertEqual(repo.task(child.id)?.status, .archived, "subtasks are archived with their parent")
        repo.restore([parent.id], at: date(14))
        XCTAssertEqual(repo.task(parent.id)?.status, .next)
        XCTAssertEqual(repo.task(child.id)?.status, .inbox)

        let removed = repo.delete([parent.id])
        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(repo.tasks.isEmpty)
        repo.reinsert(removed)
        XCTAssertEqual(repo.tasks.count, 2)
    }

    func testSubtasksRejectCycles() throws {
        let repo = makeRepo()
        let a = try repo.add(TaskDraft(title: "A"), at: date(12))
        let b = try repo.add(TaskDraft(title: "B", parentID: a.id), at: date(12))
        let c = try repo.add(TaskDraft(title: "C", parentID: b.id), at: date(12))
        XCTAssertThrowsError(try repo.setParent(a.id, parent: c.id, at: date(13))) { XCTAssertEqual($0 as? TaskError, .parentCycle) }
        XCTAssertThrowsError(try repo.setParent(a.id, parent: a.id, at: date(13)))
        // `update` silently refuses cycles too.
        repo.update(a.id, at: date(13)) { $0.parentID = c.id }
        XCTAssertNil(repo.task(a.id)?.parentID)
        XCTAssertEqual(repo.subtasks(of: a.id).map(\.id), [b.id])
    }

    func testListsAndOverdueAcrossMidnight() throws {
        let repo = makeRepo()
        let dueToday = try repo.add(TaskDraft(title: "Due today", status: .next, dueAt: calendar.startOfDay(for: date(12))), at: date(10))
        let dueTomorrow = try repo.add(TaskDraft(title: "Due tomorrow", status: .next, dueAt: calendar.startOfDay(for: date(13))), at: date(10))
        let inbox = try repo.add(TaskDraft(title: "Inbox"), at: date(10))
        let someday = try repo.add(TaskDraft(title: "Someday", status: .someday, dueAt: calendar.startOfDay(for: date(1))), at: date(10))

        let lateEvening = date(12, 23, 59)
        XCTAssertEqual(Set(repo.tasks(in: .today, now: lateEvening).map(\.id)), [dueToday.id])
        XCTAssertFalse(repo.task(dueToday.id)!.isOverdue(now: lateEvening, calendar: calendar))

        let afterMidnight = date(13, 0, 1)
        XCTAssertTrue(repo.task(dueToday.id)!.isOverdue(now: afterMidnight, calendar: calendar))
        XCTAssertEqual(Set(repo.tasks(in: .today, now: afterMidnight).map(\.id)), [dueToday.id, dueTomorrow.id])
        XCTAssertEqual(repo.tasks(in: .inbox, now: afterMidnight).map(\.id), [inbox.id])
        XCTAssertFalse(repo.tasks(in: .today, now: afterMidnight).contains { $0.id == someday.id }, "someday tasks never crowd Today")
    }

    func testSearchMatchesTitleNotesTagsAndProject() throws {
        let repo = makeRepo()
        let a = try repo.add(TaskDraft(title: "Résumé update", notes: "Use new template", project: "Career", tags: ["writing"]), at: date(12))
        let b = try repo.add(TaskDraft(title: "Write blog", tags: ["writing", "blog"]), at: date(12))
        XCTAssertEqual(repo.search("resume").map(\.id), [a.id], "diacritic-insensitive")
        XCTAssertEqual(repo.search("template").map(\.id), [a.id])
        XCTAssertEqual(Set(repo.search("#writing").map(\.id)), [a.id, b.id])
        XCTAssertEqual(repo.search("career resume").map(\.id), [a.id])
        XCTAssertTrue(repo.search("   ").isEmpty)
    }

    func testBigThreeLimitAndWorkload() throws {
        let repo = makeRepo()
        var ids: [UUID] = []
        for i in 0..<4 {
            ids.append(try repo.add(TaskDraft(title: "T\(i)", estimatedMinutes: 30), at: date(12)).id)
        }
        for id in ids.prefix(3) { try repo.setBigThree(id, enabled: true, on: date(12), at: date(12)) }
        XCTAssertThrowsError(try repo.setBigThree(ids[3], enabled: true, on: date(12), at: date(12))) { XCTAssertEqual($0 as? TaskError, .bigThreeFull) }
        XCTAssertEqual(repo.bigThree(on: date(12)).count, 3)
        XCTAssertEqual(repo.task(ids[0])?.status, .today, "Big Three tasks move to Today")
        XCTAssertEqual(repo.plannedMinutes(today: date(12)).minutes, 90)
        XCTAssertTrue(repo.bigThree(on: date(13)).isEmpty, "Big Three is per day")
    }

    func testRecurringTaskCreatesNextInstanceOnceEvenAfterRelaunch() throws {
        let store = InMemoryTaskStore()
        let repo = makeRepo(store)
        var task = try repo.add(TaskDraft(title: "Weekly report", status: .today, dueAt: calendar.startOfDay(for: date(12))), at: date(12))
        task = repo.update(task.id, at: date(12)) { $0.recurrence = .weekly }!
        let completion = repo.complete(task.id, at: date(12, 15))
        let spawnedID = try XCTUnwrap(completion?.spawnedInstanceID)
        XCTAssertEqual(repo.task(spawnedID)?.dueAt, calendar.startOfDay(for: date(19)))
        XCTAssertEqual(repo.task(spawnedID)?.status, .next)
        repo.save()

        let relaunched = makeRepo(store)
        XCTAssertTrue(relaunched.ensureRecurringInstances(at: date(13)).isEmpty, "no duplicate after relaunch")
        XCTAssertEqual(relaunched.tasks.filter { $0.title == "Weekly report" && $0.isOpen }.count, 1)

        // Undo removes the untouched spawned instance.
        repo.undo(try XCTUnwrap(completion), at: date(12, 16))
        XCTAssertNil(repo.task(spawnedID))
        XCTAssertEqual(repo.tasks.filter(\.isOpen).count, 1)
    }

    func testRecurringWeekdaysSkipsWeekend() {
        let friday = date(16) // 2026-10-16 is a Friday
        XCTAssertEqual(calendar.component(.weekday, from: friday), 6)
        let next = RecurrenceRule.weekdays.nextDate(after: friday, calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: next), 2)
    }

    func testPersistenceSurvivesRestartAndFailureIsReported() throws {
        let store = InMemoryTaskStore()
        let repo = makeRepo(store)
        try repo.add(TaskDraft(title: "Persist me", priority: .high), at: date(12))
        XCTAssertTrue(repo.save())
        XCTAssertEqual(makeRepo(store).tasks.first?.title, "Persist me")
        store.failWrites = true
        XCTAssertFalse(repo.save())
        XCTAssertNotNil(repo.lastPersistenceError)
    }

    func testJSONFileRoundTripAndTolerantDecoding() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBreakTaskTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore(directory: dir)
        let repo = TaskRepository(store: store, calendar: calendar)
        let task = try repo.add(TaskDraft(title: "Disk", definitionOfDone: "Saved"), at: date(12))
        repo.addProgressNote(task.id, text: "Half done", sessionID: nil, at: date(12, 11))
        XCTAssertTrue(repo.save())
        let reloaded = TaskRepository(store: JSONFileStore(directory: dir), calendar: calendar)
        XCTAssertEqual(reloaded.task(task.id)?.progressNotes.first?.text, "Half done")
        XCTAssertEqual(reloaded.task(task.id)?.definitionOfDone, "Saved")

        let minimal = Data(#"{"id":"\#(UUID().uuidString)","title":"Old","createdAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: minimal)
        XCTAssertEqual(decoded.status, .inbox)
        XCTAssertEqual(decoded.tags, [])
        XCTAssertFalse(decoded.isPrivate)
    }

    func testDuplicateAndMove() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "Original", status: .today), at: date(12))
        repo.complete(task.id, at: date(12, 11))
        let copy = try XCTUnwrap(repo.duplicate(task.id, at: date(12, 12)))
        XCTAssertEqual(copy.status, .today)
        XCTAssertNil(copy.completedAt)
        repo.move([copy.id], to: .someday, at: date(12, 13))
        XCTAssertEqual(repo.task(copy.id)?.status, .someday)
    }

    func testMarkdownAndCSVExport() throws {
        let repo = makeRepo()
        let task = try repo.add(TaskDraft(title: "Ship", priority: .high, definitionOfDone: "Live", estimatedMinutes: 30, tags: ["web"]), at: date(12))
        try repo.add(TaskDraft(title: "Sub", parentID: task.id), at: date(12))
        let md = TaskExporter.markdown(repo.tasks)
        XCTAssertTrue(md.contains("- [ ] Ship"))
        XCTAssertTrue(md.contains("  - [ ] Sub"))
        XCTAssertTrue(md.contains("Done when: Live"))
        let csv = TaskExporter.csv(repo.tasks)
        XCTAssertTrue(csv.hasPrefix("id,title,status"))
        XCTAssertEqual(csv.split(separator: "\n").count, 3)
    }

    func testChecklistImport() {
        let items = ChecklistImporter.parse("""
        # Groceries
        - [ ] Milk
        - [x] Bread
        * Eggs
        1. Coffee

        plain line
        """)
        XCTAssertEqual(items.map(\.title), ["Milk", "Bread", "Eggs", "Coffee", "plain line"])
        XCTAssertEqual(items.map(\.done), [false, true, false, false, false])
    }
}

final class QuickAddParserTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 1
        return c
    }()
    // Monday 12 October 2026, 10:00 local.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))! }
    func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }

    func testSpecExample() {
        let r = QuickAddParser(calendar: calendar).parse("Review MyKavo SEO tomorrow #marketing !high 30m", now: now)
        XCTAssertEqual(r.title, "Review MyKavo SEO")
        XCTAssertEqual(r.tags, ["marketing"])
        XCTAssertEqual(r.priority, .high)
        XCTAssertEqual(r.estimatedMinutes, 30)
        XCTAssertEqual(r.dueAt, day(13))
        XCTAssertEqual(r.tokens.map(\.kind), [.due, .tag, .priority, .estimate])
    }

    func testEstimatesProjectsAndLists() {
        let p = QuickAddParser(calendar: calendar)
        XCTAssertEqual(p.parse("Deep work 1h30m", now: now).estimatedMinutes, 90)
        XCTAssertEqual(p.parse("Read 1.5h", now: now).estimatedMinutes, 90)
        XCTAssertEqual(p.parse("Call 45min", now: now).estimatedMinutes, 45)
        let r = p.parse("Fix nav +Web_Site @next !!", now: now)
        XCTAssertEqual(r.title, "Fix nav")
        XCTAssertEqual(r.project, "Web Site")
        XCTAssertEqual(r.status, .next)
        XCTAssertEqual(r.priority, .high)
    }

    func testWeekdayOnlyParsedWhenUnambiguous() {
        let p = QuickAddParser(calendar: calendar)
        let inTitle = p.parse("Review Monday report", now: now)
        XCTAssertEqual(inTitle.title, "Review Monday report")
        XCTAssertNil(inTitle.dueAt)
        let atEnd = p.parse("Send invoice friday", now: now)
        XCTAssertEqual(atEnd.title, "Send invoice")
        XCTAssertEqual(atEnd.dueAt, day(16))
        let withBy = p.parse("Submit form by wed please", now: now)
        XCTAssertEqual(withBy.title, "Submit form please")
        XCTAssertEqual(withBy.dueAt, day(14))
        let sameDay = p.parse("Plan monday", now: now)
        XCTAssertEqual(sameDay.dueAt, day(19), "a weekday name means the next one, not today")
    }

    func testRelativeAndISODates() {
        let p = QuickAddParser(calendar: calendar)
        XCTAssertEqual(p.parse("Renew in 3 days", now: now).dueAt, day(15))
        XCTAssertEqual(p.parse("Renew in 2 weeks", now: now).dueAt, day(26))
        XCTAssertEqual(p.parse("Plan next week", now: now).dueAt, day(19))
        XCTAssertEqual(p.parse("Taxes 2026-11-02", now: now).dueAt, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        XCTAssertNil(p.parse("Taxes 2026-02-31", now: now).dueAt, "invalid dates are left in the title")
    }

    func testOnlyTokensKeepsLiteralTitle() {
        let r = QuickAddParser(calendar: calendar).parse("#idea", now: now)
        XCTAssertEqual(r.title, "#idea")
        XCTAssertTrue(r.tokens.isEmpty)
        XCTAssertNil(r.priority)
    }

    func testDraftMovesDueTodayToToday() {
        let r = QuickAddParser(calendar: calendar).parse("Pay rent today", now: now)
        XCTAssertEqual(r.draft(defaultStatus: .inbox, calendar: calendar, now: now).status, .today)
        let later = QuickAddParser(calendar: calendar).parse("Pay rent tomorrow", now: now)
        XCTAssertEqual(later.draft(defaultStatus: .inbox, calendar: calendar, now: now).status, .inbox)
    }
}

final class TaskFocusIntegrationTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let minute: TimeInterval = 60

    func testStartFocusWithTaskPersistsLinkThroughPauseResumeAndRelaunch() {
        let store = InMemoryStore()
        let engine = TimerEngine(store: store, configuration: TimerConfiguration())
        let taskID = UUID()
        engine.startFocus(at: t0, taskID: taskID, intent: "Draft intro")
        engine.pause(at: t0.addingTimeInterval(10 * minute))
        engine.resume(at: t0.addingTimeInterval(12 * minute))
        XCTAssertEqual(engine.current?.taskID, taskID)
        XCTAssertEqual(engine.current?.intent, "Draft intro")
        let relaunched = TimerEngine(store: store, configuration: TimerConfiguration())
        XCTAssertEqual(relaunched.current?.taskID, taskID)
    }

    func testStartFocusWithoutTask() {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0)
        XCTAssertNil(engine.current?.taskID)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        XCTAssertNil(engine.state.pendingCheckIn, "no check-in for sessions without a task")
    }

    func testTimerEndingAsksButNeverCompletesTask() throws {
        let tasks = TaskRepository(store: InMemoryTaskStore())
        let task = try tasks.add(TaskDraft(title: "Write"), at: t0)
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0, taskID: task.id)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        XCTAssertEqual(engine.state.pendingCheckIn, engine.sessions.first?.id)
        XCTAssertEqual(tasks.task(task.id)?.status, .inbox, "the task is untouched by the timer")

        let sessionID = try XCTUnwrap(engine.state.pendingCheckIn)
        engine.recordOutcome(sessionID: sessionID, outcome: .progressMade, note: "Outline done", at: t0.addingTimeInterval(46 * minute))
        XCTAssertNil(engine.state.pendingCheckIn)
        XCTAssertEqual(engine.sessions.first?.outcome, .progressMade)
        XCTAssertEqual(engine.sessions.first?.progressNote, "Outline done")
        XCTAssertEqual(tasks.task(task.id)?.status, .inbox)
    }

    func testReassignSessionKeepsOriginalTaskIntact() throws {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        let a = UUID(), b = UUID()
        engine.startFocus(at: t0, taskID: a)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        let id = try XCTUnwrap(engine.sessions.first?.id)
        XCTAssertTrue(engine.reassign(sessionID: id, to: b, at: t0.addingTimeInterval(46 * minute)))
        XCTAssertEqual(engine.sessions(forTask: b).count, 1)
        XCTAssertTrue(engine.sessions(forTask: a).isEmpty)
    }

    func testBreaksNeverCountAsTaskFocusTime() throws {
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        let taskID = UUID()
        engine.startFocus(at: t0, taskID: taskID)
        engine.startBreak(at: t0.addingTimeInterval(20 * minute))
        engine.reconcile(at: t0.addingTimeInterval(25 * minute))
        let total = TaskInsightsCalculator.focusTime(for: taskID, sessions: engine.sessions, now: t0.addingTimeInterval(30 * minute))
        XCTAssertEqual(total.time, 20 * minute, accuracy: 0.001)
        XCTAssertEqual(total.sessions, 1)
        XCTAssertEqual(engine.state.pendingCheckIn, engine.sessions.first?.id, "ending focus early for a break still asks")
    }

    func testCompletingTaskKeepsSessionHistory() throws {
        let tasks = TaskRepository(store: InMemoryTaskStore())
        let task = try tasks.add(TaskDraft(title: "Write", estimatedMinutes: 30), at: t0)
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0, taskID: task.id)
        engine.stop(at: t0.addingTimeInterval(40 * minute))
        tasks.complete(task.id, at: t0.addingTimeInterval(41 * minute))
        XCTAssertEqual(engine.sessions(forTask: task.id).count, 1)
        let interval = DateInterval(start: t0.addingTimeInterval(-3600), end: t0.addingTimeInterval(3600))
        let summary = TaskInsightsCalculator.summary(tasks: tasks.tasks, sessions: engine.sessions, interval: interval, dayCount: 1, now: t0.addingTimeInterval(3600), hidePrivate: true, calendar: .current)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.byTask.first?.focusTime ?? 0, 40 * minute, accuracy: 0.001)
        XCTAssertEqual(summary.byTask.first?.estimatedMinutes, 30)
        XCTAssertEqual(summary.averageSessionsPerCompletedTask, 1)
    }

    func testPrivateTasksHiddenInInsights() throws {
        let tasks = TaskRepository(store: InMemoryTaskStore())
        let task = try tasks.add(TaskDraft(title: "Therapy notes"), at: t0)
        tasks.update(task.id, at: t0) { $0.isPrivate = true }
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: t0, taskID: task.id)
        engine.reconcile(at: t0.addingTimeInterval(45 * minute))
        let interval = DateInterval(start: t0, end: t0.addingTimeInterval(7200))
        let hidden = TaskInsightsCalculator.summary(tasks: tasks.tasks, sessions: engine.sessions, interval: interval, dayCount: 1, now: t0.addingTimeInterval(7200), hidePrivate: true, calendar: .current)
        XCTAssertEqual(hidden.byTask.first?.title, "Private task")
        let shown = TaskInsightsCalculator.summary(tasks: tasks.tasks, sessions: engine.sessions, interval: interval, dayCount: 1, now: t0.addingTimeInterval(7200), hidePrivate: false, calendar: .current)
        XCTAssertEqual(shown.byTask.first?.title, "Therapy notes")
    }

    func testOldSessionsWithoutTaskFieldsStillDecode() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","kind":"focus","status":"completed","createdAt":0,"startedAt":0,"plannedDuration":60,"segments":[{"start":0,"end":60}],"endedAt":60,"actualDuration":60}
        """.utf8)
        let session = try JSONDecoder().decode(FocusSession.self, from: json)
        XCTAssertNil(session.taskID)
        XCTAssertNil(session.outcome)
    }
}

final class BackupAndReviewTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testBackupRoundTripAndPreview() throws {
        var running = FocusSession(kind: .focus, start: t0, plannedDuration: 600)
        running.taskID = UUID()
        let task = TaskItem(title: "A", createdAt: t0)
        let backup = BackupFile(exportedAt: t0, sessions: [running], tasks: [task], usage: [], reflections: [WeeklyReflection(weekStart: t0, helped: "Quiet mornings", updatedAt: t0)], settings: AppSettings())
        let data = try BackupService.encode(backup)
        let (restored, preview) = try BackupService.validate(data, now: t0)
        XCTAssertEqual(preview.taskCount, 1)
        XCTAssertEqual(preview.sessionCount, 1)
        XCTAssertEqual(preview.reflectionCount, 1)
        XCTAssertTrue(preview.includesSettings)
        XCTAssertEqual(restored.sessions.first?.status, .interrupted, "running sessions are closed safely")
        XCTAssertFalse(preview.warnings.isEmpty)
    }

    func testBackupValidationRejectsBadFiles() throws {
        XCTAssertThrowsError(try BackupService.validate(Data("hello".utf8)))
        let wrongApp = Data(#"{"app":"Other","exportedAt":"2026-10-10T10:00:00.000Z"}"#.utf8)
        XCTAssertThrowsError(try BackupService.validate(wrongApp))
        let newer = Data(#"{"app":"FlowBreak","formatVersion":99,"exportedAt":"2026-10-10T10:00:00.000Z"}"#.utf8)
        XCTAssertThrowsError(try BackupService.validate(newer)) { XCTAssertEqual($0 as? BackupError, .newerVersion(99)) }
        let task = TaskItem(title: "A", createdAt: t0)
        let dupes = BackupFile(exportedAt: t0, sessions: [], tasks: [task, task], usage: [], reflections: [], settings: nil)
        XCTAssertThrowsError(try BackupService.validate(try BackupService.encode(dupes))) { XCTAssertEqual($0 as? BackupError, .duplicateIDs("tasks")) }
    }

    func testBackupRepairsParentCycles() throws {
        var a = TaskItem(title: "A", createdAt: t0)
        var b = TaskItem(title: "B", createdAt: t0)
        a.parentID = b.id
        b.parentID = a.id
        let data = try BackupService.encode(BackupFile(exportedAt: t0, sessions: [], tasks: [a, b], usage: [], reflections: [], settings: nil))
        let (restored, preview) = try BackupService.validate(data, now: t0)
        XCTAssertEqual(restored.tasks.filter { $0.parentID == nil }.count, 1, "the cycle is broken")
        XCTAssertFalse(preview.warnings.isEmpty)
    }

    func testWeeklyReviewMarkdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15))!
        let tasks = TaskRepository(store: InMemoryTaskStore(), calendar: calendar)
        let done = try tasks.add(TaskDraft(title: "Shipped thing", project: "Web"), at: now.addingTimeInterval(-7200))
        let secret = try tasks.add(TaskDraft(title: "Secret", dueAt: calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))), at: now.addingTimeInterval(-7200))
        tasks.update(secret.id, at: now) { $0.isPrivate = true }
        let engine = TimerEngine(store: InMemoryStore(), configuration: TimerConfiguration())
        engine.startFocus(at: now.addingTimeInterval(-3 * 3600), taskID: done.id)
        engine.reconcile(at: now.addingTimeInterval(-3 * 3600 + 45 * 60))
        tasks.complete(done.id, at: now.addingTimeInterval(-3600))

        let review = WeeklyReview.make(tasks: tasks.tasks, sessions: engine.sessions, reflections: [], now: now, hidePrivate: true, calendar: calendar)
        XCTAssertEqual(review.tasksCompleted.map(\.title), ["Shipped thing"])
        XCTAssertEqual(review.carriedOver.map(\.id), [secret.id])
        XCTAssertEqual(review.byProject.first?.name, "Web")
        let md = review.markdown(hidePrivate: true, calendar: calendar)
        XCTAssertTrue(md.contains("- [x] Shipped thing"))
        XCTAssertTrue(md.contains("- [ ] Private task"))
        XCTAssertFalse(md.contains("Secret"))
        XCTAssertTrue(md.contains("Focus time: 45m"))
    }
}
