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
}