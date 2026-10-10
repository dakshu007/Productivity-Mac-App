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
