# FlowBreak — Product Audit, Task System & Feature Expansion Roadmap

**Document type:** Product and engineering addendum for the existing FlowBreak specification  
**Platform:** Native macOS app — Swift, SwiftUI, AppKit  
**Product philosophy:** Local-first, privacy-first, calm, reliable, useful for personal productivity  
**Purpose:** Give the coding agent a clear audit baseline, a distinctive task-completion experience, and a large, prioritized feature roadmap.

---

## 1. Important scope note

The supplied file is a **product specification**, not the actual Swift/Xcode source repository. This document audits the requirements in `FlowBreak-Product-Spec.md` and identifies what should be added or verified. It does **not** claim that any feature is already implemented or that source code has been inspected.

Before changing the app, inspect the actual repository, Xcode project, Swift files, assets, tests, and current build. Mark each capability as:

- **Implemented and verified**
- **Implemented but unverified**
- **Partially implemented**
- **Missing**
- **Blocked by platform limitation**

Do not replace existing work before auditing it. Keep a real feature-status checklist updated as code is inspected and tested.

---

# 2. Existing product baseline from the supplied specification

The current specification already calls for the following. Treat these as existing requirements, **not proof that they are implemented**.

## Core app and focus

- Native SwiftUI/AppKit macOS utility, primarily in the menu bar.
- Compact menu-bar popover with current status, countdown, progress, daily summary, and contextual actions.
- Focus sessions with 25-, 45-, and 60-minute presets plus optional custom duration.
- Pause, resume, cancel, break, snooze, skip, extend, and early-return actions.
- Pomodoro cycles: 25-minute work, 5-minute short break, 15-minute long break; long break after four completed work sessions by default.
- Automatic cycles off by default.
- Optional menu-bar countdown label.

## Reliability

- Deadline-based timer engine using absolute dates rather than decrementing a counter.
- Correct pause/resume and expiration behavior.
- Recovery after app relaunch and system sleep/wake.
- Duplicate notification and completion protection.
- Midnight and time-zone boundary handling.
- A single testable timer state machine.
- Unit tests for timer transitions and persistence.

## Breaks and reminders

- Native notifications with Take a Break, Snooze, and Dismiss actions where supported.
- Configurable repeat interval and repeat count.
- Reminder cancellation when the user acts.
- In-app fallback if macOS suppresses a notification.
- Notification sound toggle and quiet hours.
- Guided eye-rest, movement, hydration, and mind-reset activities.
- Accessible controls, reduced-motion support, and non-medical, non-shaming language.

## Insights and privacy

- Today / 7 days / 30 days statistics.
- Focus time, completed sessions, breaks, adherence, longest session, Pomodoro cycles.
- Optional foreground-app tracking, explicitly off by default.
- Website/domain tracking only through a separately implemented browser extension.
- Local persistence, CSV/JSON export, and clear-all-data controls.
- No keystroke logging, screenshots, hidden surveillance, advertising, fingerprinting, or analytics SDKs.

## Settings, onboarding, and release

- Persistent settings for focus, reminders, tracking, privacy, appearance, launch at login, and shortcuts where feasible.
- Skippable onboarding with contextual permission explanations.
- Light/dark appearance, keyboard navigation, VoiceOver labels, and reduced-motion support.
- A proper app icon and menu-bar symbol.
- DMG packaging; Developer ID signing and notarization only when actually completed.
- Tests, honest release status, README, and privacy documentation.

---

# 3. The big missing product layer: a first-class task system

FlowBreak should not only ask, “How long will you focus?” It should ask, **“What will you finish?”**

Build a fast, native task system that connects tasks to focus sessions, breaks, and a satisfying completion ritual. It must remain useful even if the user never enables app-usage tracking.

## 3.1 Task entry: add a task in seconds

The task creator should be accessible from the menu-bar popover, the main window, and a global shortcut if the user enables it.

### Minimum task fields

- Task title — required.
- Optional notes or definition of done.
- Status: Inbox, Today, In Progress, Completed, Archived.
- Priority: Low, Normal, High, Critical.
- Optional due date and reminder.
- Optional estimate in minutes or focus sessions.
- Optional project or category.
- Optional tags.
- Created, updated, completed, and archived timestamps.
- Optional parent task and subtasks.
- Optional recurring rule.
- Optional link to a project, document, URL, or local file.

### Quick-add behavior

- Press a keyboard shortcut to open a tiny task-entry panel.
- Type a title and press Return to save immediately.
- Use an optional syntax such as `Review MyKavo SEO tomorrow #marketing !high 30m`.
- Parsing must be transparent: show the interpreted due date, tag, priority, and estimate before applying ambiguous values.
- `Escape` closes the panel without saving.
- After saving, return focus to the previous app or the active FlowBreak surface.
- Support paste, undo where appropriate, and accessible labels.
- Do not force the user through a large form for a simple task.

### Suggested keyboard shortcuts

Make shortcuts configurable and avoid conflicting with common macOS shortcuts.

- Add task: `⌥⌘T` as a suggested default, subject to conflict checks.
- Start focus on selected task: configurable.
- Complete selected task: configurable.
- Open quick capture: configurable.
- Pause/resume focus: configurable.
- Open today's plan: configurable.

Do not silently install global shortcuts that conflict with other apps.

## 3.2 The task completion experience: “Flow Finish”

Create a distinctive completion interaction called **Flow Finish**. It should feel rewarding without childish points, noisy confetti, or guilt.

### Completion flow

1. The user marks a task complete with a click, keyboard shortcut, or completion gesture.
2. The task row smoothly transforms into a completed state.
3. A compact completion toast appears: **“Done. You moved this forward.”**
4. If the task had an estimate, show a simple comparison: estimated time vs. actual focus time. Never invent actual time; show “not tracked” when unavailable.
5. Offer one optional next action:
   - Start the next planned task.
   - Take a short reset.
   - Close the loop and return to work.
6. Record the completion timestamp and the session/task relationship.
7. Let the user undo completion briefly or reopen a completed task later.

### Visual treatment

- Use a crisp checkmark draw animation or a subtle line-through and fade.
- Use the app's amber accent for the completion moment.
- Respect Reduce Motion; use a static transition when enabled.
- Use haptics only where supported and appropriate, with an optional setting.
- No forced sound, streak pressure, random rewards, or celebratory modal.
- Keep the interaction quick; completion should take less than a second to acknowledge.

### Unique completion mechanic: “Proof of Done”

Each task may have an optional **Proof of Done** field defined before work begins.

Examples:
- “Landing page deployed to production.”
- “Three broken links fixed.”
- “Email sent.”
- “Pull request opened.”
- “20 flashcards reviewed.”

When completing the task, the user can optionally confirm the outcome or add a short result note. This makes completion outcome-based rather than checkbox-based. Never require proof for trivial tasks, and never claim that FlowBreak independently verified an outcome unless a real integration did so.

### Optional completion ritual

After a focus session attached to a task:
- Ask whether the intended outcome was achieved.
- Offer `Completed`, `Made progress`, or `Needs another session`.
- If `Made progress`, keep the task open and record a progress note.
- If `Needs another session`, offer to schedule another focus block.
- Do not auto-complete tasks just because the timer ended.

## 3.3 Task list design

Create a compact native task experience with these views:

- **Inbox:** captured thoughts and untriaged tasks.
- **Today:** tasks chosen for today.
- **Next:** upcoming tasks.
- **In Progress:** tasks currently being worked on.
- **Completed:** completion history with search.
- **Projects:** tasks grouped by project.
- **Someday:** low-pressure ideas with no due date.

Task rows should show title, status, priority, due date if present, estimate if present, and a clear completion control. Avoid showing every piece of metadata at once.

### Task actions

- Add, edit, duplicate, complete, reopen, archive, delete.
- Convert a note into a task.
- Add a subtask.
- Move to Today / Next / Inbox.
- Set or clear a due date.
- Set a focus estimate.
- Start a focus session for the task.
- View associated focus sessions and progress notes.
- Search and filter.
- Undo destructive actions where practical.
- Bulk-complete, bulk-archive, and bulk-move for selected tasks.
- Confirm permanent deletion; archiving should be the safer default.

## 3.4 Task scheduling rules

- Do not automatically fill every minute of the day.
- Show estimated workload for today's tasks as a rough planning aid.
- Clearly distinguish estimated work from actual focus time.
- Warn gently if planned estimates exceed the user's available time.
- Allow tasks to remain unscheduled.
- A missed due date should not create a red guilt-inducing state; show a neutral overdue label.
- Due dates use the user's local time zone and calendar.
- Recurring tasks must generate predictable instances and avoid duplicate generation after relaunch.

---

# 4. Connect tasks and focus sessions

This is the central productivity loop.

## 4.1 Start focus from a task

When the user chooses **Start Focus**, show:
- Task title.
- Definition of done, if configured.
- Focus duration.
- Optional session intention.
- Start button.

Starting a session links its session ID to the task ID. If the user starts a general focus session with no task, allow that too.

## 4.2 During a session

- Keep the active task title visible in the menu-bar popover.
- Offer a one-click way to view task details.
- Allow a private, optional session note.
- Provide a discreet “I got distracted” action only if useful; do not make the user constantly report behavior.
- Allow changing the task, but ask whether the current session should remain linked to the original task.
- Avoid intrusive prompts while the focus timer is running.

## 4.3 At the end of a session

Show a concise check-in:
- **Completed** — task is done; ask before completing if task completion was not explicitly requested.
- **Progress made** — save an optional progress note.
- **Continue later** — keep task open and optionally schedule another session.
- **Wrong task?** — allow reassignment of the session link.

Breaks should remain separate from task work time.

## 4.4 Task and session metrics

- Focus sessions per task.
- Recorded focus time per task.
- Estimated versus actual time when actual time is available.
- Tasks completed this week.
- Tasks started but not completed.
- Average number of sessions per completed task.
- Progress notes and completion history.

Do not turn estimates into exact performance claims. Let users exclude private tasks from insights if desired.

---

# 5. Additional feature bank — 100+ ideas

Use this as a backlog, not a command to build everything at once. Each feature must be evaluated for usefulness, complexity, privacy, accessibility, and maintenance cost.

## A. Task management and planning

1. Quick Add task panel.
2. Daily Big Three priorities.
3. Inbox for quick captures.
4. Today / Next / Someday lists.
5. Projects and project colors.
6. Tags and saved filters.
7. Priority levels.
8. Due dates and optional reminders.
9. Task estimates in minutes.
10. Subtasks and checklists.
11. Recurring tasks.
12. Task templates.
13. Task dependencies (“do this after…”).
14. Definition of Done field.
15. Proof of Done notes.
16. Progress notes per task.
17. Task history and reopen.
18. Archive instead of destructive delete.
19. Duplicate task.
20. Bulk task actions.
21. Drag-and-drop task ordering.
22. Calendar-style planning view.
23. Search across title, notes, tags, and project.
24. Natural-language quick add with a preview.
25. Import/export tasks as JSON or CSV.

## B. Focus and session intelligence

26. Start a session directly from a task.
27. Active task in menu bar.
28. Focus presets and custom durations.
29. Flexible session lengths based on task type.
30. Optional session intention.
31. End-of-session outcome check-in.
32. Session notes.
33. Task-linked session timeline.
34. Resume interrupted session.
35. Focus session recovery after restart.
36. Optional warm-up ritual before a deep-work block.
37. Optional wind-down note after a block.
38. “One more block?” prompt, always optional.
39. Manual session logging for work done away from the app.
40. Focus-session labels: Deep Work, Admin, Learning, Creative.
41. Optional ambient sound.
42. Optional full-screen focus view.
43. Menu-bar countdown toggle.
44. Minimal status-only mode.
45. Session history search.

## C. Breaks and wellbeing

46. Eye-rest countdown.
47. Stretch/movement activity cards.
48. Hydration reminder.
49. Breathing animation.
50. Quiet rest with no animation.
51. Custom break activities.
52. Randomize or rotate break activities.
53. Skip, extend, or end break.
54. Break snooze rules.
55. Quiet hours.
56. Break reminder frequency settings.
57. Optional sound.
58. Break completion history.
59. Gentle reminder after long uninterrupted computer use.
60. “Not now” snooze with a clear next reminder time.
61. Break recommendations based on user-selected preferences.
62. Optional posture check-in, without medical claims.
63. Configurable weekday schedules.
64. Pause reminders during presentations or meetings.
65. A low-stimulation mode for all prompts.

## D. Distraction management

66. Gentle reminder when switching to a user-selected distracting app.
67. App allowlist for focus sessions.
68. App exclusion list for tracking.
69. Optional website blocking via a suitable browser extension or supported mechanism.
70. Manual distraction log.
71. “Save this for later” capture action.
72. Distraction summary after a session, only when enabled.
73. Optional notification quieting through supported macOS settings or shortcuts.
74. Detect repeated app switching without recording keystrokes.
75. Private mode that pauses all usage tracking.
76. Exclude specific apps from reports.
77. One-click pause for tracking.
78. Explain every permission before requesting it.
79. No covert blocking or input manipulation.
80. A clear override option for every blocker.

## E. Insights and reflection

81. Daily focus total.
82. Weekly focus trend.
83. Monthly focus trend.
84. Completed tasks per day/week.
85. Focus time per task.
86. Focus time per project.
87. Planned versus completed tasks.
88. Estimated versus actual duration.
89. Longest focus session.
90. Sessions interrupted or cancelled.
91. Break adherence with a documented formula.
92. Most productive time windows, based only on available data.
93. Task carryover count.
94. Weekly review prompts.
95. A simple “what helped / what distracted me?” reflection.
96. Exportable weekly summary.
97. Calendar heatmap based on real recorded sessions.
98. User-defined goals.
99. Trend comparisons that disclose missing data.
100. Data-quality notes when tracking was paused.
101. Explain every metric calculation.
102. Allow the user to disable any metric they dislike.

## F. Personalization and accessibility

103. Light/dark/system appearance.
104. Reduced Motion support.
105. VoiceOver labels.
106. Full keyboard navigation.
107. Custom focus and break durations.
108. Configurable shortcuts.
109. Configurable sounds.
110. Compact versus expanded popover.
111. Custom workday schedule.
112. Week start preference.
113. Time-zone-safe task due dates.
114. Menu-bar label preferences.
115. Optional launch at login.
116. Optional Dock icon.
117. Adjustable notification verbosity.
118. Larger countdown text.
119. High-contrast-friendly accent selection.
120. No animation mode.
121. Optional completion haptics if supported.
122. Restore default settings.

## G. Reliability and data ownership

123. Local structured persistence for tasks and sessions.
124. Database migration strategy.
125. Atomic writes and recovery from interrupted writes.
126. Duplicate task/session prevention where applicable.
127. Backup to a local JSON file.
128. Restore from a valid backup with preview.
129. Export tasks and sessions separately.
130. Clear all data with a confirmation step.
131. Session reconciliation after sleep/wake.
132. Handle system clock changes.
133. Handle midnight and time-zone boundaries.
134. Data integrity checks.
135. Local diagnostic log that excludes private content by default.
136. A visible last-backup date if backups are enabled.
137. Versioned export format.
138. No fake seeded production statistics.

## H. Workflow and integrations

139. Copy a task as Markdown.
140. Share a task through the macOS share sheet where appropriate.
141. Open a task's URL or file.
142. Create a task from selected text through a supported macOS action.
143. Import tasks from a plain-text checklist.
144. Export tasks to Markdown.
145. Optional Calendar integration with explicit permission.
146. Optional Reminders integration if the user wants Apple Reminders as a source of truth.
147. Optional Shortcuts/App Intents integration.
148. Start/pause focus using a Shortcut.
149. Create a task using a Shortcut.
150. Query today's priorities through a Shortcut.
151. Optional browser extension for domain timing.
152. Optional local-only integration with developer workflows.
153. Do not add cloud sync or accounts unless there is a clear need.
154. Keep integrations independently disableable.

## I. Premium-feeling polish

155. Carefully animated completion checkmark.
156. Smooth reorder animation.
157. A subtle completion toast.
158. Useful empty states with one clear action.
159. Undo toast after completion or archive.
160. Thoughtful loading and error states.
161. Native context menus.
162. Consistent SF Symbols.
163. No fake buttons or inert controls.
164. Stable layout at small screen sizes.
165. Respect macOS appearance and materials.
166. Clear onboarding with a skippable path.
167. Tiny product tips that can be disabled.
168. Version and diagnostic information in About.
169. A “Reset onboarding” option.
170. A visible privacy summary and data controls.

---

# 6. Recommended build priority

Do not ship all 170 ideas as one large rewrite. Deliver a useful, testable increment at each stage.

## P0 — Essential next release

- [ ] Audit the actual Swift/Xcode repository before editing.
- [ ] Add a local task model and persistence.
- [ ] Add Quick Add task entry.
- [ ] Add Inbox and Today lists.
- [ ] Add task completion, reopen, archive, and undo.
- [ ] Add Flow Finish completion animation and toast.
- [ ] Add optional Definition of Done / Proof of Done.
- [ ] Start a focus session from a task.
- [ ] Persist task-session relationships.
- [ ] Add tests for task persistence and task completion.
- [ ] Ensure all data remains local.
- [ ] Keep existing timer behavior intact.

## P1 — Strong daily workflow

- [ ] Daily Big Three.
- [ ] Task estimates and focus-time totals.
- [ ] Progress notes.
- [ ] End-of-session task outcome check-in.
- [ ] Inbox / Today / Next / Completed views.
- [ ] Search and filters.
- [ ] Keyboard shortcuts, configurable and conflict-aware.
- [ ] JSON/CSV export and backup.
- [ ] Weekly review.

## P2 — Focus intelligence

- [ ] Task and project insights.
- [ ] Distraction nudges.
- [ ] Optional ambient sound.
- [ ] Recurring tasks and templates.
- [ ] Calendar/Reminders/Shortcuts integrations after evaluating the simplest native path.
- [ ] Optional browser extension only if domain-level tracking is genuinely wanted.

## P3 — Experimental features

- [ ] Adaptive focus duration.
- [ ] Natural-language task parsing.
- [ ] Personalized focus suggestions.
- [ ] Optional AI-assisted task breakdown.
- [ ] Cross-device sync only if a real need emerges.

AI should not be required for the core task manager. If added, make it optional, disclose any network transfer, and avoid sending private task content without explicit consent.

---

# 7. Data model proposal

Use the repository's existing persistence approach if it is sound. If no suitable approach exists, prefer SwiftData for the supported deployment target or a structured Codable store under Application Support. Do not store growing task history as unrelated UserDefaults keys.

## Task

Suggested fields:

- `id: UUID`
- `title: String`
- `notes: String?`
- `definitionOfDone: String?`
- `completionNote: String?`
- `status: TaskStatus`
- `priority: TaskPriority`
- `createdAt: Date`
- `updatedAt: Date`
- `dueAt: Date?`
- `completedAt: Date?`
- `archivedAt: Date?`
- `estimatedMinutes: Int?`
- `projectID: UUID?`
- `parentTaskID: UUID?`
- `tags: [String]`
- `sortOrder: Double`
- `recurrenceRule: RecurrenceRule?`
- `externalURL: URL?`
- `isPrivate: Bool`

Suggested `TaskStatus`: `inbox`, `today`, `next`, `inProgress`, `completed`, `archived`, `someday`.

Suggested `TaskPriority`: `low`, `normal`, `high`, `critical`.

Avoid persisting derived statistics if they can be calculated reliably from source records.

## FocusSession

Retain the existing session specification and add:

- `taskID: UUID?`
- `projectID: UUID?` only if useful and not derivable from the task
- `sessionIntent: String?`
- `outcome: SessionOutcome?`
- `progressNote: String?`

Suggested `SessionOutcome`: `completed`, `progressMade`, `continueLater`, `wrongTask`, `notRecorded`.

Keep focus time and break time separate. Store timestamps and calculate summaries from records.

## TaskCompletionEvent (optional)

Use a separate event/history model only if task audit history, undo, and reopening cannot be handled cleanly by the existing data model.

Potential fields:
- `id: UUID`
- `taskID: UUID`
- `eventType: TaskEventType`
- `createdAt: Date`
- `note: String?`
- `previousStatus: TaskStatus?`

Do not introduce event sourcing merely for architectural novelty. Choose the simplest reliable model that supports undo and history.

---

# 8. UI layout proposal

## Menu-bar popover

Keep the existing timer first. Add the active task as a compact secondary focus.

When idle:
- Current status and timer.
- `Start Focus` primary action.
- Active task selector.
- `Add Task` quick action.
- Today's completed count and focus time.
- Links to Tasks, Insights, and Settings.

During focus:
- Countdown and progress.
- Active task title.
- Pause/resume.
- Complete task action only if the user intentionally chooses it.
- A subtle route to task details.

When a session ends:
- Session summary.
- Optional task outcome prompt.
- Take a break / start another block / finish.
- Never mark a task complete solely because a timer ended.

## Tasks window

Suggested sections:
- Sidebar: Inbox, Today, Next, Projects, Completed.
- Main list: sortable task rows.
- Detail inspector: notes, definition of done, estimates, subtasks, history.
- Quick-add field always easy to reach.
- Search accessible by keyboard.
- Empty state that suggests adding one task, not a lengthy onboarding sequence.

Keep the design native, calm, compact, and consistent with the existing amber/off-white/charcoal design system. Support light and dark appearances.

---

# 9. Privacy and permission boundaries

- Task management must work without tracking permission.
- Task titles, notes, projects, and completion history stay on-device by default.
- No account, cloud sync, analytics SDK, or AI API is required for the core product.
- If optional AI is added, show what data leaves the Mac and obtain consent before sending it.
- Do not capture keystrokes, screenshots, window contents, or file contents for productivity scoring.
- Do not label foreground-app time as exact focus time.
- Never infer task completion from app switching.
- Provide export, backup, and deletion controls.
- Explain browser extension permissions separately from macOS app permissions.
- Use supported public APIs; do not attempt to defeat macOS Focus or manipulate user input.

---

# 10. Testing and acceptance criteria for the task system

The feature is not complete merely because it compiles.

## Task tests

- [ ] Add task with title only.
- [ ] Add task with notes and definition of done.
- [ ] Empty/whitespace-only titles are rejected or handled clearly.
- [ ] Edit task and preserve creation metadata.
- [ ] Complete and reopen task.
- [ ] Undo completion when available.
- [ ] Archive and restore task.
- [ ] Delete with confirmation.
- [ ] Add subtasks and prevent invalid parent cycles.
- [ ] Sort and filter without losing records.
- [ ] Search finds title, notes, and tags according to documented behavior.
- [ ] Due dates behave across midnight and time-zone changes.
- [ ] Recurring tasks do not duplicate after relaunch.
- [ ] Persistence survives app restart.
- [ ] Export includes the documented fields.
- [ ] Restore validates the backup before replacing data.

## Focus integration tests

- [ ] Start focus with a selected task and persist the link.
- [ ] Start focus without a task.
- [ ] Pause/resume without changing task linkage.
- [ ] Reassign a session without corrupting the original task.
- [ ] A break does not count as task focus time.
- [ ] Ending a timer never auto-completes the task.
- [ ] Progress Made leaves the task open.
- [ ] Completing a task does not delete its session history.
- [ ] Relaunch restores active task/session state safely.

## UX/accessibility tests

- [ ] Quick Add works entirely from the keyboard.
- [ ] Escape cancels quick add without accidental saving.
- [ ] VoiceOver can identify task status and completion controls.
- [ ] Reduce Motion disables the completion animation.
- [ ] Completion can be undone or reopened.
- [ ] No action relies on color alone.
- [ ] Empty, error, and persistence-failure states are useful.
- [ ] No fake task data appears in production.

---

# 11. Suggested implementation plan for the coding agent

**Do not implement the entire backlog in one pass.**

### Step 1 — Repository audit

1. Inspect the actual Xcode project and all source files.
2. Identify the app entry point, menu-bar architecture, timer engine, persistence layer, settings, and tests.
3. Build the current project and record real errors/warnings.
4. Create a feature matrix against the existing product specification.
5. Identify reusable code and risks before changing anything.
6. Report which parts of the repository were actually inspected.

### Step 2 — Task foundation

1. Implement the task model and persistence migration.
2. Add repository/service APIs for create, read, update, complete, archive, restore, and delete.
3. Add unit tests before wiring the UI.
4. Keep existing focus timer APIs stable where possible.

### Step 3 — Quick Add and task list

1. Implement Quick Add.
2. Implement Inbox and Today.
3. Implement status, priority, estimates, and optional Definition of Done.
4. Implement keyboard navigation and accessible controls.
5. Verify persistence through relaunch.

### Step 4 — Flow Finish

1. Add the completion state transition.
2. Add the restrained checkmark animation and completion toast.
3. Add optional Proof of Done and completion note.
4. Add undo/reopen.
5. Respect Reduce Motion.
6. Test duplicate taps and persistence failure.

### Step 5 — Link tasks to focus

1. Add optional `taskID` to focus sessions with a safe migration.
2. Start focus from a task.
3. Show the active task in the menu-bar popover.
4. Add end-of-session outcome choices.
5. Keep timer completion separate from task completion.
6. Verify that focus statistics remain accurate.

### Step 6 — Insights and expansion

Only after P0 works:
1. Add task-based statistics.
2. Add Daily Big Three and weekly review.
3. Add recurring tasks, projects, templates, and integrations as separate increments.
4. Build and test after each increment.
5. Update the README and product specification to match real behavior.

### Required coding-agent behavior

- Read `FlowBreak-Product-Spec.md` completely.
- Inspect the existing repository instead of assuming the spec equals the code.
- Preserve working implementation and design.
- Build native SwiftUI/AppKit interfaces, not web-style mockups.
- Use the existing timer engine if it is correct; fix it only when tests or inspection reveal issues.
- Do not claim builds or tests passed unless actually run.
- Do not create placeholder buttons.
- Do not add unnecessary cloud infrastructure.
- At the end, report implemented features, missing features, tests run, build status, and any known limitations.

---

# 12. Definition of a successful first task release

The first task-system release is successful when:

- [ ] I can add a task in a few seconds.
- [ ] I can choose the task and start a focus session from it.
- [ ] I can see the active task while focusing.
- [ ] I can mark the task complete in one deliberate action.
- [ ] Completion feels satisfying but calm.
- [ ] I can optionally confirm the result using Proof of Done.
- [ ] I can undo completion or reopen a task.
- [ ] Task and session history survives relaunch.
- [ ] Ending a timer never falsely marks work as completed.
- [ ] The task feature works entirely offline.
- [ ] Existing break reminders and timer reliability are not regressed.
- [ ] Tests cover task lifecycle and focus integration.
- [ ] The repository's documentation reflects what actually shipped.

## Product north star

**FlowBreak should help me decide what matters, stay with it, take a real break, and finish work with a clear sense of progress.**

A timer measures time. FlowBreak should help turn that time into meaningful outcomes.
