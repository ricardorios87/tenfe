# Tenfe - Project Guide

## Overview
Tenfe is a macOS menu bar app that displays real-time Madrid Cercanías train schedules and sends notifications when it's time to leave for the station. Supports multiple trips with per-trip notification settings.

## Tech Stack
- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Platform**: macOS 13.0+
- **Architecture**: MVVM with `@Observable` (Observation framework) for reactive updates

## Build Instructions

### Using Xcode (recommended for full functionality)
```bash
xcodebuild -project Tenfe.xcodeproj -scheme Tenfe -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Tenfe-*/Build/Products/Debug/Tenfe.app
```

### Using Swift Package Manager (limited - no notifications)
```bash
swift build
.build/debug/Tenfe
```

**Note**: SPM builds don't create a proper .app bundle, so notifications won't work. Always use Xcode for testing notifications.

## Project Structure
```
Sources/
├── TenfeApp.swift              # App entry point
├── Controllers/
│   └── StatusBarController.swift   # Main controller, manages windows and status bar
├── Views/
│   ├── StatusBarPopupView.swift    # Menu bar popup with train list + trip tabs
│   ├── SettingsView.swift          # Settings window (trip list + per-trip edit)
│   └── SetupWizardView.swift       # First-launch setup wizard
├── Services/
│   ├── RenfeAPI.swift              # GTFS + HTML fallback train data fetcher
│   ├── TrainService.swift          # Business logic for train data
│   ├── NotificationManager.swift   # Local notifications handling (per-trip)
│   └── SettingsManager.swift       # UserDefaults persistence + trip CRUD
└── Models/
    ├── Train.swift                 # Train model, Route struct
    └── AppSettings.swift           # Trip, AppSettings, Station
```

## Key Implementation Details

### Renfe API (`RenfeAPI.swift`)

The app uses a two-tier data strategy:

**Primary: GTFS static + GTFS-RT realtime**
- Downloads the GTFS zip daily from `https://ssl.renfe.com/ftransit/Fichero_CER_FOMENTO/fomento_transit.zip`
- Cached in `~/Library/Caches/com.tenfe.gtfs/` with a date marker to avoid re-downloading
- Parses `calendar.txt`, `routes.txt`, `trips.txt` to find today's Madrid service
- Filters `stop_times.txt` (273MB+) via piped `grep` to avoid writing full file to disk
- Madrid services use service IDs starting with `"10"`, núcleo ID `"10"`
- Station codes (e.g. Atocha = `"18000"`) serve as both Renfe codes and GTFS `stop_id`s
- Applies real-time delays and cancellations from `https://gtfsrt.renfe.com/trip_updates.json` (JSON GTFS-RT feed)
- Supports overnight trips: GTFS times can exceed 24:00 (e.g. `25:30` = 1:30 AM next day)

**Fallback: HTML scraping**
- Scrapes `https://horarios.renfe.com/cer/hjcer310.jsp` via POST if GTFS fails
- POST params: `nucleo`, `o` (origin code), `d` (dest code), `df` (date YYYYMMDD), `ho` (hour), `hd=26`
- Parses HTML tables with regex to extract departure/arrival times and line numbers
- Line names extracted from CSS classes matching `_10C(\d+)` pattern

**Key types:**
- `RenfeAPI` is an `actor` (thread-safe), accessed via `RenfeAPI.shared`
- Station codes live in `RenfeAPI.renfeStationCodes` dictionary
- `SSLTolerantDelegate` handles Renfe's potentially problematic SSL certificates
- Returns up to 20 future trains sorted by departure time

### Multi-Trip Support

- `Trip` struct holds route, schedule, and notification settings per trip
- `AppSettings` stores `trips: [Trip]` and `activeTripId: UUID?`
- Backward-compatible computed accessors (`route`, `leaveTime`, etc.) delegate to `activeTrip`
- Custom `Codable` migration: decodes legacy single-route format into a single `Trip`
- `SettingsManager` provides CRUD: `addTrip()`, `updateTrip()`, `deleteTrip(id:)`, `setActiveTrip(id:)`
- Popup shows trip tab chips when multiple trips exist; tapping switches the active trip and reloads trains immediately

### Notifications (`NotificationManager.swift`)
- Requires proper .app bundle (Xcode build)
- 15-minute warning: triggers 15-10 minutes before departure time
- Time to leave: triggers based on walk time + next train departure
- Notifications fire only for the active trip
- Persisted state (last notification dates) is namespaced per trip ID: `TenfeLastWarningDate_<uuid>`
- Test button available in Settings

### Windows
- Menu bar app (LSUIElement = YES, no dock icon)
- Settings and Wizard windows managed by StatusBarController
- Windows use `isReleasedWhenClosed = false` to prevent deallocation

## Common Tasks

### Adding a new station
1. Add the station code to `RenfeAPI.renfeStationCodes` (same code works for both GTFS and HTML)
2. Add the station name to `Station.madridStations` in `AppSettings.swift`

### Testing notifications
1. Build with Xcode
2. Open Settings → Click "Send Test Notification"
3. Check System Settings → Notifications → Tenfe if not appearing

### Debugging API issues
- Console prints are prefixed with `[Tenfe]`
- GTFS loading logs: service ID, trip count, stop times count
- On GTFS failure, logs the error and falls back to HTML automatically
- GTFS cache is at `~/Library/Caches/com.tenfe.gtfs/` — delete to force re-download

## Git
- Personal GitHub: use `github-personal` host in remote URL
- Work GitHub: use default `github.com` host

## Important Notes
- App refreshes train data every 5 minutes automatically
- Settings are persisted in UserDefaults with key `"TenfeAppSettings"`
- First launch is tracked with `"hasCompletedSetup"` UserDefaults key
- Notification state persists across app restarts to avoid duplicate notifications
- Settings observer polls every 100ms for changes (route, active trip, notification toggles)
- Trip switching from the popup triggers immediate route refresh (bypasses observer delay)
