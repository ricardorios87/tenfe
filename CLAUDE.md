# Tenfe - Project Guide

## Overview
Tenfe is a macOS menu bar app that displays real-time Madrid Cercanías train schedules and sends notifications when it's time to leave for the station.

## Tech Stack
- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Platform**: macOS 13.0+
- **Architecture**: MVVM with Combine for reactive updates

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
│   ├── StatusBarPopupView.swift    # Menu bar popup with train list
│   ├── SettingsView.swift          # Settings window
│   └── SetupWizardView.swift       # First-launch setup wizard
├── Services/
│   ├── RenfeAPI.swift              # Fetches real train data from Renfe
│   ├── TrainService.swift          # Business logic for train data
│   ├── NotificationManager.swift   # Local notifications handling
│   └── SettingsManager.swift       # UserDefaults persistence
└── Models/
    ├── Train.swift                 # Train model
    └── AppSettings.swift           # Settings model, Route, Station
```

## Key Implementation Details

### Renfe API
- Scrapes `https://horarios.renfe.com/cer/hjcer310.jsp` via POST request
- Madrid núcleo ID: `10`
- Station codes are in `RenfeAPI.renfeStationCodes` dictionary
- HTML parsing extracts departure/arrival times using regex

### Notifications
- Requires proper .app bundle (Xcode build)
- 15-minute warning: triggers 15-10 minutes before leave time
- Time to leave: triggers based on walk time + next train departure
- Test button available in Settings

### Windows
- Menu bar app (LSUIElement = YES, no dock icon)
- Settings and Wizard windows managed by StatusBarController
- Windows use `isReleasedWhenClosed = false` to prevent deallocation

## Common Tasks

### Adding a new station
Edit `RenfeAPI.renfeStationCodes` and `Station.madridStations` in AppSettings.swift

### Testing notifications
1. Build with Xcode
2. Open Settings → Click "Send Test Notification"
3. Check System Settings → Notifications → Tenfe if not appearing

### Debugging API issues
Check the console for print statements from RenfeAPI. The `parseScheduleHTML` method logs parsing details.

## Git
- Personal GitHub: use `github-personal` host in remote URL
- Work GitHub: use default `github.com` host

## Important Notes
- App refreshes train data every 5 minutes automatically
- Settings are persisted in UserDefaults with key "TenfeSettings"
- First launch is tracked with "hasCompletedSetup" UserDefaults key
- Notification state persists across app restarts to avoid duplicate notifications
