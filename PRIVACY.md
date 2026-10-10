# FlowBreak privacy notes

FlowBreak is local-first. This document describes what the current version actually does.

## What is stored

| Data | Where | When |
| --- | --- | --- |
| Preferences | `UserDefaults` (`app.flowbreak.mac`, key `FlowBreak.settings.v1`) | Always |
| Timer state (current session, break due) | `~/Library/Application Support/FlowBreak/state.json` | Always |
| Focus and break session history (start/end times, pauses, outcome) | `~/Library/Application Support/FlowBreak/sessions.json` | Always |
| Foreground app usage (app name, bundle ID, start/end time) | `~/Library/Application Support/FlowBreak/usage.json` | **Only after you turn on app usage tracking** |

Nothing is uploaded. FlowBreak has no account, server, cloud sync, advertising, fingerprinting, or analytics SDK. It makes no network requests.

## App usage tracking

- **Off by default.** Turning it on asks for confirmation first.
- When on, FlowBreak listens for the public `NSWorkspace` "app activated" notification and records the frontmost app's **name and bundle identifier** with approximate start and end times.
- To exclude time when you're away, FlowBreak reads the system **idle duration** (seconds since the last input event, via `CGEventSource.secondsSinceLastEventType`). It never reads the events themselves. After 2 minutes of inactivity, sleep, screen lock or a user switch, time stops counting.
- It **never** records keystrokes, screenshots, window titles, window contents, document or file names, URLs, or browsing history. It needs no Accessibility or Screen Recording permission.
- **Private mode** (Settings › Privacy) pauses recording. **Excluded apps** are never recorded.
- Durations are **approximate** and labelled that way in the app.

## Website tracking

Not available in this version. Per-website time would need a separate browser extension, which isn't included. FlowBreak never treats a browser's name as a website.

## Notifications

FlowBreak schedules local notifications through `UNUserNotificationCenter`. They are created and delivered on your Mac. macOS Focus modes and Do Not Disturb can hold them back, and FlowBreak doesn't try to get around that.

## Export and deletion

- Settings › Privacy and the Insights window can export sessions (CSV), app usage (CSV), or everything (JSON) to a file you choose.
- **Delete All FlowBreak Data** removes session history and usage records. A session in progress keeps running, and your preferences are kept.
- To remove everything, quit FlowBreak and delete `~/Library/Application Support/FlowBreak` and the app.

## Logging

FlowBreak writes a few diagnostic messages to the unified system log (subsystem `app.flowbreak.mac`), such as "launched" and persistence errors. App names and usage data are never logged.
