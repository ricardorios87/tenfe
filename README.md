# Tenfe - Cercanías Madrid Train Notifications

A lightweight macOS menubar app that notifies you when it's time to catch your train home from work.

## Features

- 🚂 Lives quietly in your menubar
- ⏰ Smart notifications (15-min warning + time-to-leave alert)
- 🚉 Customizable route (any Cercanías Madrid stations)
- 📅 Set your work leaving time
- 🚶 Accounts for walking time to station

## Building & Running

### Quick Start

1. Build the app:
```bash
make app
```

2. Run the app:
- Double-click `Tenfe.app` in Finder
- Or run from terminal: `open Tenfe.app`

### Development

```bash
# Build and run in debug mode
make debug

# Open in Xcode
make xcode

# Clean build artifacts
make clean
```

## Setup

1. Click the train icon in your menubar
2. Click "Settings..."
3. Configure:
   - Your route (e.g., Recoletos → Vicálvaro)
   - Leave work time (e.g., 18:30)
   - Walking time to station (e.g., 5 minutes)
4. Save and enjoy automatic notifications!

## How It Works

The app monitors the time and sends you two notifications:
- **15 minutes before leaving**: Shows next 3 available trains
- **Time to leave**: Alerts you when to leave the office to catch the optimal train

## Current Status

✅ **API Integration Complete!** The app now uses:
- Renfe's official API for station data
- Accurate Cercanías Madrid schedules (C-2, C-7 lines for Recoletos → Vicálvaro)
- Smart fallback to cached schedules when offline
- Real journey times between stations

## Data Sources

- **Station Information**: [Renfe Open Data API](https://data.renfe.com)
- **Train Schedules**: Hardcoded from official Cercanías Madrid timetables
- **Updates**: Refreshes every 5 minutes while app is running

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later