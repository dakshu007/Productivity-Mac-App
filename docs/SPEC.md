# FlowBreak for macOS --- Product & Engineering Specification

**Purpose:** This document is the single source of truth for designing
and building FlowBreak, a polished, native macOS focus and
digital-wellbeing app. Read the entire document before implementation.
Build the real app, not a static mockup.

**Product name:** FlowBreak\
**Platform:** macOS\
**Primary implementation:** Swift, SwiftUI, AppKit\
**Minimum target:** macOS 13+ (raise only if a required API needs it;
document why)\
**Architecture:** Native menu-bar-first utility, local-first,
privacy-first\
**Default focus interval:** 45 minutes\
**Default short break:** 5 minutes\
**Status:** Product specification for a complete first release

------------------------------------------------------------------------

## 1. Product vision

FlowBreak helps people who work for long stretches at a Mac remember to
pause, rest their eyes, move, and return to focused work. It should feel
like a calm, premium macOS utility---not a noisy timer, gamified
dashboard, or surveillance tool.

The app lives primarily in the macOS menu bar. The user should be able
to see their current session, start or pause focus, take a break, snooze
a reminder, and inspect their day without opening a large window.

### Core product principles

1.  **Quiet by default:** useful, unobtrusive, and respectful of the
    user's workflow.
2.  **Reliable:** timers must remain correct through app inactivity,
    system sleep/wake, and relaunch.
3.  **Local-first:** no account, cloud backend, ads, or analytics in the
    MVP.
4.  **Privacy-respecting:** tracking is transparent, opt-in, and limited
    to the minimum data needed.
5.  **Native:** use SwiftUI and AppKit, native menus, native
    notifications, standard macOS keyboard/accessibility behaviors.
6.  **Honest UI:** never show fake statistics, fabricated usage data, or
    controls that do nothing.
7.  **Polished details:** consistent spacing, typography, animation,
    empty states, permission explanations, error handling, and
    dark/light appearance support.

------------------------------------------------------------------------

## 2. Brand identity and logo direction

Claude may generate the logo and design assets. Create a coherent visual
identity before implementing the final UI.

### Brand personality

-   Calm, focused, warm, modern, trustworthy, premium.
-   Not childish, medical, corporate-heavy, or overly gamified.
-   The app should feel at home beside Apple's native menu-bar
    utilities.

### Logo concept

Create a distinctive, simple vector logo that remains legible at 16×16
and 32×32 pixels.

**Preferred concept:** a minimal leaf or sprout integrated with a subtle
circular motion/flow shape. It should communicate a small reset, natural
rhythm, and returning to focus. Keep the silhouette bold and simple;
avoid fine detail, gradients that disappear at small sizes, stock-icon
appearance, or text inside the symbol.

**Color direction:** - Warm amber/gold accent: `#FFBA30` or a carefully
tuned accessible variant. - Ink/charcoal: `#191B18`. - Warm off-white:
`#FBFAF3`. - Secondary neutral: `#6A6A5F`. - Supporting muted green for
a positive active state.

The logo should work on both light and dark backgrounds and in
monochrome. Create: - App icon (1024×1024 source). - macOS `.icns` asset
or a documented process to generate it from the source. - SVG source, if
the design tool supports it. - Small menu-bar template symbol, optimized
for monochrome macOS menu-bar rendering. - Light/dark background preview
sheet.

Do not make the app icon a screenshot of the interface. Do not rely on
emoji as the production logo. Do not use an unlicensed third-party
asset.

------------------------------------------------------------------------

## 3. Visual design system

### Overall aesthetic

Use a clean, native macOS design with generous breathing room, soft warm
surfaces, restrained amber highlights, fine dividers, and carefully
chosen SF Symbols where appropriate. Avoid excessive cards, giant
headings, decorative gradients, or web-dashboard styling inside the
menu-bar popover.

### Colors

Create semantic color tokens and support light and dark mode.

  -----------------------------------------------------------------------
  Token                   Suggested value         Use
  ----------------------- ----------------------- -----------------------
  `accent`                `#FFBA30`               Primary actions,
                                                  progress, active
                                                  details

  `ink`                   `#191B18`               Main dark text / icon
                                                  backing

  `canvasLight`           `#FBFAF3`               Optional warm surface
                                                  in light appearance

  `secondaryText`         `#6A6A5F`               Secondary labels

  `success`               system green /          Active/positive status
                          accessible muted green  

  `warning`               accessible amber        Break due, permission
                                                  warning

  `separator`             semantic system         Dividers
                          separator               
  -----------------------------------------------------------------------

Prefer semantic system colors for text, materials, window backgrounds,
and controls so contrast adapts correctly. Test accent contrast and
adjust if necessary.

### Typography and spacing

-   Use San Francisco system typography.
-   Use monospaced digits for countdowns.
-   Use a consistent spacing scale (4, 8, 12, 16, 20, 24).
-   Prefer 10--14 pt secondary labels and 13--16 pt primary controls,
    adjusted for accessibility.
-   Use subtle transitions; honor Reduce Motion.
-   Support Dynamic Type where practical and keyboard navigation.
-   Do not use emoji as interface icons; use SF Symbols or the custom
    logo.

### Required visual deliverables

Before finalizing implementation, create: 1. Logo/icon variations and
chosen rationale. 2. Menu-bar popover in idle, focus-running, paused,
break-due, and break-running states. 3. Settings window. 4. Daily
insights/statistics window. 5. Break notification concept. 6. First-run
onboarding and permissions explanation. 7. Empty, loading, error, and
permission-denied states. 8. Light and dark appearance checks.

Claude may use its design/image capabilities to create visual assets.
Export the final assets into the project and wire them into the app; do
not leave them as reference images only.

------------------------------------------------------------------------

## 4. Core experience and navigation

### Menu-bar interaction

The menu-bar icon should be minimal and readable. While a focus session
is active, optionally show a compact remaining-time label if it does not
crowd the menu bar. The user must be able to disable the countdown label
in settings.

Clicking the icon opens a compact popover with: - Brand icon and
`FlowBreak` title. - Clear mode/status label. - Large countdown and
progress ring or bar. - Daily focus time and breaks-taken summary. - A
single prominent context-aware primary action. - Secondary actions for
pause/resume, snooze, settings, and opening insights. - A small
unobtrusive footer for app version or quit.

Avoid duplicate buttons that perform the same action. The popover must
resize cleanly and fit typical laptop screens.

### Required states

Implement and visually test all of these: 1. Idle / ready. 2. Focus
running. 3. Focus paused. 4. Break due. 5. Break running. 6. Break
completed. 7. Notifications not authorized. 8. App tracking disabled. 9.
First launch. 10. No statistics yet. 11. App relaunch with an active or
expired session. 12. System sleep and wake.

Every state must have a meaningful action and clear copy.

------------------------------------------------------------------------

## 5. Timer engine --- correctness is critical

Do not implement the timer by subtracting one second from a counter and
assuming the app stays awake. That drifts or breaks when the process is
suspended or the Mac sleeps.

### Required timer model

Persist a session record containing at least: - Unique session ID. -
Session type: focus, Pomodoro focus, short break, long break. - Start
timestamp. - Target end timestamp / deadline. - Paused timestamp or
accumulated paused duration. - Status: running, paused, completed,
cancelled. - Planned duration. - Actual duration when complete. -
Creation and completion timestamps.

Use absolute `Date` deadlines as the source of truth. A UI timer may
refresh once per second, but remaining time must always be recalculated
from the deadline. On wake, app activation, or relaunch, reconcile the
session against current time.

### Timer requirements

-   Starting a focus session uses the configured focus duration (default
    45 minutes).
-   Pause captures the exact remaining time and marks the session
    paused.
-   Resume creates a new deadline from the current time plus remaining
    duration.
-   Starting a break safely closes/pauses the current session according
    to documented behavior.
-   At deadline, transition exactly once to break due/completed.
-   Prevent duplicate notifications and duplicate break counts.
-   Handle midnight crossing without losing session correctness.
-   Handle system time changes reasonably; document behavior.
-   Use a single state machine / timer service, not timer logic
    scattered across views.
-   Add unit tests for transitions, pause/resume, expiration, midnight,
    relaunch, and duplicate completion.
-   Persist data before issuing transitions that depend on it.

### Focus and Pomodoro behavior

-   Focus timer presets: 25, 45, 60 minutes; allow a custom duration in
    settings if reasonable.
-   Pomodoro defaults: 25-minute work, 5-minute short break, 15-minute
    long break.
-   Provide configurable long break after four completed Pomodoro work
    sessions.
-   The user may skip a break, extend it, or return to focus early.
-   Automatic cycles should be opt-in; default should offer the next
    action rather than unexpectedly starting work.

------------------------------------------------------------------------

## 6. Break reminders and notifications

### Default behavior

-   After a focus session finishes, show a native macOS notification:
    "Time to reset --- take a 5-minute break."
-   Provide notification actions where supported: **Take a break**,
    **Snooze 5 min**, **Dismiss**.
-   If the user does not act, repeat reminders every 5 minutes for a
    configurable number of attempts (default 3; maximum 12).
-   Repeated reminders must be cancellable when the user starts a break,
    resumes focus, disables reminders, or dismisses the due state.
-   Do not schedule 12 reminders by default without user consent.
-   A break reminder should not create an unbounded notification loop.
-   The app must explain how notification permissions and macOS Focus
    affect delivery.
-   Provide an in-app fallback indicator for break due if notification
    delivery is suppressed.
-   Add notification sounds toggle and optional quiet hours.

### Permissions and platform limits

-   Request notification permission at an appropriate point with a clear
    explanation.
-   Never imply that the app can override macOS Focus/Do Not Disturb or
    force an alert to remain visible.
-   Use documented public APIs only.
-   Do not attempt to block system controls or manipulate the user's
    input to force breaks.

------------------------------------------------------------------------

## 7. Guided breaks

Build a real break screen/panel with concise, optional activities, not
just static settings labels.

### Break categories and examples

**Eye rest** - Show a simple 20-second countdown for the 20-20-20
practice. - Copy: "Look at something about 20 feet away. Let your eyes
relax."

**Movement** - Shoulder rolls, gentle neck movement, standing, or a
short walk. - Use neutral safety copy: "Move comfortably; skip anything
that causes pain."

**Hydration** - Gentle optional reminder to drink water.

**Mind reset** - A short breathing animation with reduced-motion
support, or a quiet 30-second pause.

Each activity needs: - Clear start, pause, and finish controls. -
Countdown or progress. - Skip activity action. - No medical claims. - No
guilt or shaming copy.

------------------------------------------------------------------------

## 8. Daily insights and statistics

Build a dedicated native insights window. Do not cram every chart into
the menu-bar popover.

### MVP metrics

-   Focus time today.
-   Focus sessions completed.
-   Breaks taken.
-   Break adherence rate (clearly define numerator/denominator).
-   Longest focus session.
-   Pomodoro cycles completed.
-   App usage by foreground application, if tracking is enabled.
-   Website usage by domain, only after browser integration is
    implemented and permission is granted.

### UI requirements

-   Today / 7 days / 30 days filters.
-   Simple charts with accessible labels and useful empty states.
-   Session timeline with start, end, duration, and type.
-   Top app/domain usage only when the user has enabled that feature.
-   Do not show estimates as exact measurements.
-   Explain how each metric is calculated.
-   Provide export to CSV/JSON and clear-all-data controls.
-   Use a local database or well-structured Codable persistence rather
    than fragile unrelated UserDefaults counters.

### Statistics correctness

-   Store session records with timestamps, not just incrementing
    integers.
-   Use the user's local calendar/time zone for day boundaries.
-   Define how sessions crossing midnight are split between days.
-   Keep completed, cancelled, and interrupted sessions distinct.
-   Ensure opening the dashboard does not fabricate or reset data.

------------------------------------------------------------------------

## 9. App and website usage tracking --- privacy-first

This feature must be explicit and opt-in. It must not behave like
employee monitoring or hidden surveillance.

### Foreground app tracking

-   Off by default until the user understands and enables it.
-   Explain that only the frontmost app name and approximate active time
    are recorded.
-   Use `NSWorkspace` / public AppKit APIs.
-   Do not capture keystrokes, screenshots, window contents, or file
    names.
-   Offer app exclusions and pause tracking.
-   Do not track while FlowBreak is in a user-configured private mode.
-   Store locally and provide clear/delete/export controls.

### Website tracking

Website-level tracking is **not possible to implement reliably from the
native app alone** using only the foreground app name. Do not pretend
that browser name equals website name.

For accurate domain-level time: - Implement a separate Safari Web
Extension and/or Chrome extension. - Request only the permissions
necessary for active-tab/domain timing. - Prefer recording domains and
elapsed time, not full URLs, page text, browsing history, or query
strings. - Explain permissions and retention in onboarding. - Pause
tracking in private/incognito windows unless the user explicitly opts in
and the browser supports it. - Make the extension optional; FlowBreak
must work fully without it. - Define a documented local
communication/storage mechanism between extension and Mac app. Avoid
exposing an unauthenticated local network server.

### Privacy requirements

-   Local-first by default; no cloud upload.
-   No advertising, fingerprinting, or analytics SDK.
-   Explicit consent before app/website tracking.
-   Easy pause, exclude, export, and delete controls.
-   Clear privacy page in the app.
-   Never call usage data "exact" when it is sampled or approximate.

------------------------------------------------------------------------

## 10. Settings

Create a well-organized native settings window with clear sections:

### Focus

-   Default focus interval (25 / 45 / 60 / custom).
-   Pomodoro work, short break, long break durations.
-   Long break cadence (default every four completed work sessions).
-   Automatic cycle toggle, off by default.
-   Show/hide countdown in menu bar.

### Reminders

-   Notifications enabled.
-   Repeat interval (default 5 minutes).
-   Repeat count (default 3).
-   Sound toggle.
-   Quiet hours.
-   Reminder behavior after sleep/relaunch.

### Tracking and privacy

-   Foreground app tracking toggle, off by default.
-   Website tracking status and browser extension setup.
-   Excluded apps/domains.
-   Private mode / pause tracking.
-   Export data and delete all local data.

### Appearance and behavior

-   Follow system light/dark mode.
-   Launch at login toggle.
-   Reduce motion respect.
-   Show in Dock toggle only if the app architecture supports it
    cleanly.
-   Keyboard shortcuts, if feasible.

All settings must persist across relaunch. Every control shown must
work; otherwise mark it clearly as unavailable or omit it.

------------------------------------------------------------------------

## 11. First-run onboarding

On first launch, show a short, polished onboarding sequence: 1. Welcome:
"Make room for better focus." 2. Explain focus sessions and breaks. 3.
Ask the user to choose a break interval (default 45 minutes). 4. Explain
optional app usage tracking; keep it off by default. 5. Explain
notification permission and request it after context. 6. Finish with a
"Start first focus session" action.

Keep onboarding skippable and accessible. Do not request tracking or
notification permission before explaining the value. The user can change
everything later.

------------------------------------------------------------------------

## 12. Technical architecture

Use a clear separation of concerns. Suggested structure:

``` text
FlowBreak/
  App/
    FlowBreakApp.swift
    AppDelegate.swift                 # only if needed
  DesignSystem/
    Colors.swift
    Typography.swift
    Spacing.swift
    Components/
  Features/
    MenuBar/
      MenuBarView.swift
      MenuBarViewModel.swift
    Timer/
      TimerEngine.swift
      SessionState.swift
      SessionStore.swift
    Breaks/
      BreakCoordinator.swift
      GuidedBreakView.swift
    Notifications/
      NotificationService.swift
      NotificationActionDelegate.swift
    Insights/
      InsightsWindow.swift
      InsightsViewModel.swift
      Charts/
    Tracking/
      AppUsageTracker.swift
      WebsiteUsageBridge.swift
    Settings/
      SettingsView.swift
      SettingsStore.swift
    Onboarding/
      OnboardingView.swift
    Privacy/
      PrivacyView.swift
  Models/
    FocusSession.swift
    UsageSample.swift
    AppSettings.swift
  Persistence/
    PersistenceController.swift
    Migrations/
  Resources/
    Assets.xcassets/
    PrivacyInfo.xcprivacy             # only if required; accurately describe APIs
  Tests/
    TimerEngineTests.swift
    PersistenceTests.swift
    StatisticsTests.swift
  Scripts/
    build_dmg.sh
    build_universal.sh
    sign_and_notarize.sh
  README.md
  PRIVACY.md
  LICENSE
```

Use Swift Package Manager or an Xcode project as appropriate. Choose the
approach that produces a repeatable, understandable build.

### Persistence

Prefer SwiftData (if deployment target permits) or Codable JSON/database
storage under Application Support. Avoid storing growing session
histories in unrelated UserDefaults keys. Store preferences in
UserDefaults and session/usage records in a structured store. Handle
write failures and migrations.

### Background and lifecycle behavior

-   The app should run as a menu-bar utility and not require a permanent
    Dock icon unless configured.
-   Use lifecycle notifications to reconcile time after sleep/wake and
    activation.
-   Use local notifications for deadlines that must fire when the app is
    not frontmost.
-   Explain that macOS may suppress notifications under Focus modes.
-   Use launch-at-login APIs such as `SMAppService` where available and
    user-authorized.
-   Do not claim that a normal app can run arbitrary code continuously
    through system sleep.

### Quality

-   Use structured logging without collecting sensitive usage data.
-   Provide accessible labels and keyboard support.
-   Avoid force unwraps and unsafe state mutation.
-   Use dependency injection for timer, notification, and persistence
    services where practical.
-   Keep timer state transitions testable without waiting real minutes.
-   No fake data in production UI.
-   No placeholder buttons in the release build.
-   Build and run on a real Mac, resolve all compiler warnings/errors,
    and test notifications and wake/relaunch behavior.

------------------------------------------------------------------------

## 13. DMG, signing, and release

### Local development build

Provide one documented command or Xcode scheme to build and run the app.

### DMG deliverable

The final output should be a real, installable `FlowBreak.dmg`, not just
a script or mockup. The DMG should contain: - `FlowBreak.app`. - An
`/Applications` shortcut. - A clean background/layout if practical, but
keep it simple. - A version number and brief installation instructions.

### Distribution requirements

-   Build and test on macOS.
-   Support Apple Silicon and Intel if feasible; otherwise state the
    supported architecture clearly.
-   Sign the app using a valid Apple Developer ID for public
    distribution.
-   Enable hardened runtime as appropriate.
-   Notarize and staple the app/DMG for Gatekeeper distribution.
-   Do not claim signing/notarization unless it was actually completed.
-   Provide checksums and version information for release artifacts.

### Build scripts

Scripts must: - Stop on errors (`set -euo pipefail`). - Validate
required tools and signing identity. - Avoid silently producing an
unsigned "release" artifact. - Separate local development packaging from
release signing/notarization. - Print the exact output paths and next
steps.

------------------------------------------------------------------------

## 14. Testing and acceptance criteria

Do not mark a feature done merely because it compiles. Verify behavior.

### Timer tests

-   Start, pause, resume, cancel, complete.
-   Focus expires once and triggers one due state.
-   Snooze scheduling and cancellation.
-   Break completion.
-   Pomodoro transitions and long-break cadence.
-   Midnight boundary.
-   Relaunch with running, paused, or expired session.
-   Sleep/wake deadline reconciliation.
-   Time-zone/day-boundary behavior.

### Tracking tests

-   Off by default.
-   No tracking data written before consent.
-   App changes recorded with expected sampling tolerance.
-   Excluded apps are not recorded.
-   Private mode pauses samples.
-   Data export/delete works.
-   Website extension disconnected state is clearly explained.

### UI/accessibility tests

-   Light and dark appearance.
-   Reduced Motion.
-   VoiceOver labels and keyboard navigation.
-   Notification permission denied.
-   Empty insights.
-   Long app names and small laptop windows.
-   No overflowing menu-bar popover.

### Release acceptance checklist

The release is ready only when: - \[ \] App builds cleanly on the target
macOS version. - \[ \] Menu-bar popover is functional in every required
state. - \[ \] Timer remains correct across sleep/wake and relaunch. -
\[ \] Notifications and repeat cancellation behave as documented. - \[
\] Statistics match persisted session records. - \[ \] Tracking is
opt-in, transparent, and deletable. - \[ \] All visible buttons work. -
\[ \] No fake or seeded production statistics. - \[ \] README and
privacy notes match actual behavior. - \[ \] DMG installs and launches
on a clean Mac. - \[ \] Signing/notarization status is honestly
reported.

------------------------------------------------------------------------

## 15. Recommended implementation phases

Do not try to implement every subsystem in one giant untested pass. Work
in phases, compiling and testing after each one.

### Phase 1 --- Native foundation

-   Project setup, app icon, menu bar, visual design system.
-   Focus timer state machine using deadlines.
-   Start/pause/resume and break actions.
-   Local notification permission and due reminder.
-   Basic settings persistence.
-   Build/run on Mac.

### Phase 2 --- Reliability

-   Sleep/wake and relaunch recovery.
-   Persistent reminder policy with cancellation.
-   Notification actions.
-   Unit tests for timer transitions.
-   Edge-case and accessibility fixes.

### Phase 3 --- Breaks and Pomodoro

-   Guided break activities with real countdowns.
-   Pomodoro short/long breaks and cycle tracking.
-   Optional automatic cycles.

### Phase 4 --- Insights

-   Structured local session store.
-   Today / 7 days / 30 days dashboard.
-   Accurate statistics and timeline.
-   Export and clear-data actions.

### Phase 5 --- Privacy-friendly usage tracking

-   Explicit opt-in app tracking.
-   Exclusions, pause/private mode, local usage history.
-   Browser extension design and domain-level tracking integration.
-   Permission and privacy review.

### Phase 6 --- Production release

-   Launch at login.
-   Icon/asset finalization.
-   Universal binary if supported.
-   Automated build checks.
-   DMG creation, Developer ID signing, notarization, clean-machine
    test.

At the end of each phase, summarize what works, what tests were run,
what is incomplete, and the exact command to run it. Do not move forward
with known build errors.

------------------------------------------------------------------------

## 16. Instructions to the coding agent

Act as a senior macOS engineer and product designer.

1.  Read this full specification before changing files.
2.  Inspect the current repository and preserve useful existing work.
3.  If a starter implementation exists, audit it before replacing it;
    identify correctness bugs and gaps.
4.  Make design and architecture decisions consistent with this
    document. If a requirement conflicts with a platform limitation,
    explain the limitation and implement the best honest alternative.
5.  Generate a coherent logo and export the actual app assets.
6.  Build real native interfaces and working functionality. Do not stop
    at mockups, pseudocode, or a feature checklist.
7.  Compile frequently and run automated tests where possible.
8.  Never fabricate successful build, test, signing, notarization, or
    website tracking results.
9.  Prioritize reliability, privacy, accessibility, and a premium visual
    finish over adding many half-working controls.
10. Keep `README.md`, `PRIVACY.md`, and this specification synchronized
    with the real implementation.
11. Before finishing, report the implemented features, remaining gaps,
    test results, build command, output path, and whether the DMG is
    actually built and signed.

**First task:** inspect the repository and toolchain, then complete
Phase 1 end-to-end. Do not merely respond with a plan---start
implementing the working project.
