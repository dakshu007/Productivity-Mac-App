# FlowBreak privacy notes

FlowBreak is local-first. This document describes what the current version actually does.

## What is stored

| Data | Where | When |
| --- | --- | --- |
| Preferences | `UserDefaults` (`app.flowbreak.mac`, key `FlowBreak.settings.v1`) | Always |
| Timer state (current session, break due) | `~/Library/Application Support/FlowBreak/state.json` | Always |
| Focus and break session history (start/end times, pauses, outcome) | `~/Library/Application Support/FlowBreak/sessions.json` | Always |
| Tasks (titles, notes, Done-when, result notes, progress notes, projects, tags, links) | `~/Library/Application Support/FlowBreak/tasks.json` | When you create tasks |
| Weekly reflections | `~/Library/Application Support/FlowBreak/reflections.json` | When you write one |
| Foreground app usage (app name, bundle ID, start/end time) | `~/Library/Application Support/FlowBreak/usage.json` | **Only after you turn on app usage tracking** |

Nothing is uploaded. FlowBreak has no account, server, cloud sync, advertising, fingerprinting, or analytics SDK.

**Network:** FlowBreak contacts the internet only for update checks, and only if you turn them on or press **Check Now**. A check downloads a small public file (`latest.json`) from this project's GitHub releases; no identifiers or personal data are sent. GitHub, like any web server, sees the request's IP address. "Report a Problem" opens your browser, and nothing is sent until you submit the issue yourself.

## App usage tracking

- **Off by default.** Turning it on asks for confirmation first.
- When on, FlowBreak listens for the public `NSWorkspace` "app activated" notification and records the frontmost app's **name and bundle identifier** with approximate start and end times.
- To exclude time when you're away, FlowBreak reads the system **idle duration** (seconds since the last input event, via `CGEventSource.secondsSinceLastEventType`). It never reads the events themselves. After 2 minutes of inactivity, sleep, screen lock or a user switch, time stops counting.
- It **never** records keystrokes, screenshots, window titles, window contents, document or file names, URLs, or browsing history. It needs no Accessibility or Screen Recording permission.
- **Private mode** (Settings › Privacy) pauses recording. **Excluded apps** are never recorded.
- Durations are **approximate** and labelled that way in the app.

## Tasks

- Tasks work entirely offline and need no permissions.
- FlowBreak never infers that a task is complete. A focus timer ending only asks how it went, and only you mark tasks complete.
- **Private** tasks show as "Private task" in Insights and weekly summaries (Settings › Tasks).
- Global shortcuts are **off by default**. They use Carbon's `RegisterEventHotKey`, which only notifies FlowBreak when its own key combination is pressed. FlowBreak never sees other keystrokes and needs no Accessibility permission.
- Backups are files you save yourself. Restoring keeps a safety copy in `~/Library/Application Support/FlowBreak/Backups`.

## Calendar (opt-in)

- Off until you turn on calendar awareness, which asks macOS for calendar access.
- FlowBreak reads only the start time, end time and title of today's and tomorrow's events, in memory, to hold reminders during meetings, show free time and warn about conflicts. Nothing from your calendar is written to FlowBreak's files or sent anywhere.
- Scheduling a focus block adds one event, "Focus: <task>", to the calendar you choose.

## Distraction nudges (opt-in)

- Off by default. When on, FlowBreak watches only which app comes to the front (the same public notification used by app usage tracking), and only during a running focus session.
- Only the number of nudges per session is stored. App names are not stored for nudges.
- "Back to focus" hides that app only when you click it. FlowBreak never blocks or quits apps.

## Website tracking

Not available in this version. Per-website time would need a separate browser extension, which isn't included. FlowBreak never treats a browser's name as a website.

## Notifications

FlowBreak schedules local notifications through `UNUserNotificationCenter`. They are created and delivered on your Mac. macOS Focus modes and Do Not Disturb can hold them back, and FlowBreak doesn't try to get around that.

## Export and deletion

- Settings › Privacy and the Insights window can export sessions (CSV), app usage (CSV), or everything (JSON) to a file you choose.
- **Delete All FlowBreak Data** removes tasks, session history, reflections and usage records. A session in progress keeps running, and your preferences are kept.
- To remove everything, quit FlowBreak and delete `~/Library/Application Support/FlowBreak` and the app.

## Logging

FlowBreak writes a few diagnostic messages to the unified system log (subsystem `app.flowbreak.mac`), such as "launched" and persistence errors. App names and usage data are never logged.
