# FlowBreak — implementation status

This file is updated alongside the code. It says plainly what is done and what has been verified, and how.

## How it is built and verified

- Development happens in a Linux container, which can't compile AppKit/SwiftUI. **All compilation, unit tests and packaging run on GitHub Actions `macos-15` runners** (`.github/workflows/build.yml`).
- Each CI run does the following:
  1. `swift test` runs the core unit tests.
  2. A universal (arm64 + x86_64) release build is made.
  3. A DMG is packaged.
  4. The DMG is mounted and checked for the app, the `/Applications` link, a valid ad-hoc code signature, and both architectures.
  5. The packaged binary is launched with `--smoke-test`, which exercises the timer engine and persistence and renders the menu-bar icon.
  6. The built app renders every UI state in light and dark with `--render-previews`, using a temporary store. The screenshots are uploaded as an artifact and attached to the release. These were reviewed visually during development; curated sheets are in `Design/Screenshots/`.
- Latest verified CI run: 44/44 XCTest cases passed. The universal (x86_64 + arm64) build succeeded, the DMG verified and mounted, and the smoke test passed.
- **Not verified by CI:** interactive UI behaviour (popover, windows, notifications appearing, real sleep/wake, launch at login, VoiceOver). These need a person on a real Mac; see the manual checklist below.

## Signing

- CI builds are **ad-hoc signed and not notarized**, and the DMG name ends in `-unsigned`. No Apple Developer ID is configured for this repository.
- `Scripts/sign_and_notarize.sh` and the workflow's optional signing path implement Developer ID signing, hardened runtime, notarization and stapling. They have **not been run**, because no credentials are available.

## Phase summary

| Phase | State |
| --- | --- |
| 1 — Native foundation | Done: menu-bar app, design system, logo/icon assets, deadline-based timer state machine, start/pause/resume/stop/break, notifications, settings persistence. |
| 2 — Reliability | Done in code + unit tests: relaunch and sleep reconciliation, completes-exactly-once, clock-rollback handling, finite repeat reminders with automatic cancellation, notification actions, persistence error surfacing and corrupt-file backup. Real sleep/wake needs manual testing. |
| 3 — Breaks & Pomodoro | Done: guided break window (eye rest, movement, hydration, breathing with Reduce Motion), extend, end early, Pomodoro cycles with configurable long-break cadence, opt-in auto cycles. |
| 4 — Insights | Done: Today/7/30 days, metrics with definitions, chart, timeline, CSV/JSON export, delete-all. |
| 5 — Usage tracking | App tracking done (opt-in, exclusions, private mode, idle cut-off, export/delete). **Website tracking is not implemented** (it needs a browser extension); the UI says so. |
| 6 — Release | Universal binary, DMG, checksums, CI artifact and releases done. Launch at login implemented via `SMAppService`. Developer ID signing/notarization scripted but not executed (no credentials). |

## Automated tests (Tests/FlowBreakCoreTests)

- Timer: start, pause/resume exact remaining, stop, expires once, deadline-not-wake-time completion, break from due/during focus, extend, snooze/skip, Pomodoro long-break cadence, auto-cycle and its no-fabrication-after-sleep rule, relaunch running/paused/expired, inconsistent-state repair, clock rollback, persistence failure surfacing, clear history.
- Reminders: initial + repeats, 12-reminder cap, cancellation by state, past reminders dropped, snooze rescheduling, disabled, quiet hours across midnight.
- Statistics: empty state, midnight split across a DST week, pause exclusion, adherence/breaks/longest, running session, Pomodoro cycles.
- Persistence/tracking: JSON round-trip, corrupt file backup, settings migration defaults/clamping, CSV escaping, off-by-default tracking, exclusions, private mode, aggregation clipping.

## Manual checklist for a real Mac

- [ ] Install from the DMG; first-launch Gatekeeper flow as described in README.
- [ ] Onboarding appears once; Skip works; the notification permission prompt appears only after pressing "Allow Notifications".
- [ ] Popover in every state: idle, focusing, paused, break due, snoozed, on break, break complete.
- [ ] Notification at focus end with Take a break / Snooze 5 min / Dismiss; the repeats stop after acting.
- [ ] Notifications denied: banner in popover, "Break" shown in menu bar when due.
- [ ] Sleep the Mac past a deadline: on wake the session is complete at its deadline and one catch-up notice appears.
- [ ] Quit and relaunch during a running, paused, and expired session.
- [ ] Insights with no data, then with data; export CSV/JSON; delete all data.
- [ ] App tracking off by default; enable, exclude an app, private mode.
- [ ] Launch at login toggle (may require approval in Login Items).
- [ ] Light/Dark appearance, Reduce Motion, VoiceOver labels, keyboard Return/⌘,/⌘Q.

---

# Task system release (1.1) — status against docs/ROADMAP.md

Status legend:
- **Verified (tests):** covered by XCTest on CI.
- **Verified (render):** shown in a CI-rendered screenshot of the real view.
- **Unverified (interactive):** the code is built, but it needs a person on a real Mac (keyboard, panels, haptics, global shortcuts).
- **Missing:** not built yet.

## P0 — Essential next release

| Item | Status |
| --- | --- |
| Audit the repository first | Done. The existing timer engine was kept unchanged apart from additive task fields; all earlier tests still pass. |
| Local task model and persistence (`tasks.json`, atomic, versioned, tolerant decoding) | Verified (tests) |
| Quick Add task entry with parse preview | Verified (tests) for the parser, Verified (render) for the panel. Global shortcut and return-to-previous-app are unverified (interactive). |
| Inbox and Today lists | Verified (tests + render) |
| Complete, reopen, archive, undo | Verified (tests). The undo toast is Verified (render). |
| Flow Finish animation and toast | Verified (render) for static states. The animation and haptic are unverified (interactive). |
| Optional Definition of Done / Proof of Done | Verified (render) |
| Start a focus session from a task | Verified (tests + render) |
| Persist task–session relationships | Verified (tests), including relaunch, pause/resume, reassign and old-file decoding |
| Tests for task persistence and completion | Verified (tests): 34 new test cases (78 in total) |
| All data local | Yes. There is no networking code in the app. |
| Existing timer behaviour intact | Verified (tests): all original timer tests pass unchanged |

## P1 — Strong daily workflow

| Item | Status |
| --- | --- |
| Daily Big Three | Verified (tests + render) |
| Task estimates and focus-time totals | Verified (tests + render) |
| Progress notes | Verified (tests + render) |
| End-of-session outcome check-in (never auto-completes) | Verified (tests + render) |
| Inbox / Today / Next / In Progress / Someday / Completed / Archived / Projects views | Verified (render) |
| Search (title, notes, Done-when, project, `#tag`) | Verified (tests) |
| Configurable, conflict-aware global shortcuts (off by default) | Unverified (interactive). If registration fails, the error is shown in Settings › Tasks. |
| JSON/CSV export and backup, restore with preview | Verified (tests) for validation, export and cycle repair. The file dialogs are unverified (interactive). |
| Weekly review with reflection and Markdown export | Verified (tests + render) |

## P2 and beyond

| Item | Status |
| --- | --- |
| Task and project insights | Verified (tests + render) |
| Recurring tasks (no duplicates after relaunch) | Verified (tests) |
| Subtasks with cycle prevention | Verified (tests) |
| Checklist import (text/Markdown) and task Markdown export | Verified (tests) |
| Copy task as Markdown, open task link | Unverified (interactive) |
| Private tasks hidden in insights and summaries | Verified (tests) |
| Distraction nudges, ambient sound, Calendar/Reminders/Shortcuts integrations, browser extension | Missing (by design for this release) |
| Task templates, dependencies, calendar planning view | Missing |
| AI features, sync | Missing (not planned without an explicit need and consent design) |

## Known limitations

- Due dates are stored as the local start of day. If you change time zones, a task due "today" can shift by a day.
- The Quick Add parser understands English date words only.
- Global shortcuts come from a fixed set of combinations; there's no shortcut recorder yet.

---

# 1.2 — integrations

| Item | Status |
| --- | --- |
| #1 Real-Mac testing | Your part. Added **Copy Diagnostics** and **Report a Problem** (pre-filled GitHub issue) so problems are easy to report. |
| #2 Signing & updates | Signing/notarization pipeline ready; step-by-step guide in `docs/SIGNING.md` (needs your Apple Developer account). Opt-in update checks via CI-published `latest.json`, with checksum-verified download — verified (tests + CI publishes the manifest). Fully automatic in-place updates (Sparkle) are deliberately deferred until builds are Developer ID–signed. |
| #3 Shortcuts / Siri / Spotlight | 9 App Intents + phrases. CI checks that the metadata is embedded in the app bundle. **Actually running them from the Shortcuts app is unverified (interactive).** |
| #4 Calendar awareness | Hold reminders during meetings, free time, conflict warnings, schedule focus blocks. Planning logic is verified (tests), the views are verified (render), and EventKit access is unverified (interactive, needs permission). |
| #5 Distraction nudges | Policy verified (tests), nudge view verified (render). App-switch detection on a real Mac is unverified (interactive). |
