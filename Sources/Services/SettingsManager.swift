import Foundation
import Observation

@Observable
@MainActor
final class SettingsManager {
    var settings: AppSettings

    private let userDefaults = UserDefaults.standard
    private let settingsKey = "TenfeAppSettings"

    init() {
        // Load settings from UserDefaults or use default
        if let data = userDefaults.data(forKey: settingsKey),
           let decodedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decodedSettings
        } else {
            self.settings = AppSettings()
        }
    }

    func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings

        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }

    func resetToDefaults() {
        settings = AppSettings()
        userDefaults.removeObject(forKey: settingsKey)
    }

    // MARK: - Trip CRUD

    func addTrip(_ trip: Trip) {
        var updated = settings
        updated.trips.append(trip)
        if updated.trips.count == 1 {
            updated.activeTripId = trip.id
        }
        saveSettings(updated)
    }

    func updateTrip(_ trip: Trip) {
        var updated = settings
        if let idx = updated.trips.firstIndex(where: { $0.id == trip.id }) {
            updated.trips[idx] = trip
        }
        saveSettings(updated)
    }

    func deleteTrip(id: UUID) {
        var updated = settings
        updated.trips.removeAll { $0.id == id }
        if updated.activeTripId == id {
            updated.activeTripId = updated.trips.first?.id
        }
        saveSettings(updated)
    }

    func setActiveTrip(id: UUID) {
        var updated = settings
        updated.activeTripId = id
        saveSettings(updated)
    }
}
