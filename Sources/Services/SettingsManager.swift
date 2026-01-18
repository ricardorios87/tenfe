import Foundation
import Combine

class SettingsManager: ObservableObject {
    @Published var settings: AppSettings

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

        // Notify observers that settings have changed
        objectWillChange.send()
    }

    func resetToDefaults() {
        settings = AppSettings()
        userDefaults.removeObject(forKey: settingsKey)
        objectWillChange.send()
    }
}