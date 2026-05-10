# Ferber Sleep Trainer

An iOS app for tracking and timing the Ferber method of infant crib sleep training.

## Features

- **Progressive interval timers** — Default Ferber intervals (Night 1: 3→5→10 min, etc.) with full customization
- **Night tracking** — Automatically tracks which night you're on
- **Check-in timer** — Configurable duration (60-180 seconds) with alerts when it's time to leave the room
- **Session logging** — Records start time, sleep time, total duration, check-in count and durations
- **History & trends** — Charts showing time-to-sleep and check-ins over nights
- **Dark mode** — Designed for 2am use in a dark room
- **Local notifications** — Alerts for check-in time and when to leave the room

## Requirements

- iOS 18.0+
- Xcode 16+

## Installation

1. Clone this repo
2. Open `FerberSleepTrainer.xcodeproj` in Xcode
3. Select your iPhone as the target device
4. Run (⌘R)

### Apple Developer Account

- **Free tier**: Sign in with your Apple ID in Xcode → Preferences → Accounts. App expires after 7 days and needs re-deploy.
- **Paid tier ($99/year)**: Enroll at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll). App stays installed indefinitely.

## Usage

1. **Start session** — Tap when you put baby in crib
2. **Wait** — Timer counts down to first check-in
3. **Check in** — When alerted, go comfort briefly (1-2 min max)
4. **Leave** — When check-in timer alerts, leave the room
5. **Repeat** — Intervals get progressively longer
6. **Baby fell asleep** — Tap to end session and log

## Ferber Default Intervals

| Night | Wait intervals (minutes) |
|-------|--------------------------|
| 1 | 3, 5, 10 (repeat 10) |
| 2 | 5, 10, 12 (repeat 12) |
| 3 | 10, 12, 15 (repeat 15) |
| 4+ | 12, 15, 17 (repeat 17) |

All intervals are customizable in Settings.

## License

MIT
