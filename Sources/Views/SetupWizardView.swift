import SwiftUI

@MainActor
struct SetupWizardView: View {
    let settingsManager: SettingsManager
    var onComplete: @MainActor () -> Void

    @State private var currentStep = 0
    @State private var selectedOrigin: String = "Recoletos"
    @State private var selectedDestination: String = "Vicálvaro"
    @State private var leaveTime: Date = Calendar.current.date(from: DateComponents(hour: 18, minute: 30)) ?? Date()
    @State private var walkTime: Int = 5
    @State private var enableNotifications: Bool = true

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content area
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: routeStep
                case 2: scheduleStep
                case 3: notificationsStep
                case 4: completeStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "tram.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tenfe Setup")
                    .font(.headline)
                Text(stepTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Progress indicator
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Welcome"
        case 1: return "Choose your route"
        case 2: return "Set your schedule"
        case 3: return "Enable notifications"
        case 4: return "You're all set!"
        default: return ""
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "tram.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)

            Text("Welcome to Tenfe")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your personal Madrid Cercanías assistant.\nNever miss your train home again.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
    }

    private var routeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("Where do you commute?")
                .font(.title3)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("From")
                        .frame(width: 45, alignment: .trailing)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedOrigin) {
                        ForEach(Station.madridStations, id: \.self) { station in
                            Text(station).tag(station)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                HStack {
                    Text("To")
                        .frame(width: 45, alignment: .trailing)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedDestination) {
                        ForEach(Station.madridStations, id: \.self) { station in
                            Text(station).tag(station)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
            .padding(.vertical, 8)

            Text("Pick your most frequent route")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var scheduleStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("When do you head out?")
                .font(.title3)
                .fontWeight(.medium)

            VStack(alignment: .center, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Leave at")
                        .foregroundColor(.secondary)

                    DatePicker("", selection: $leaveTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .frame(width: 70)
                }

                HStack(spacing: 12) {
                    Text("Walk to station")
                        .foregroundColor(.secondary)

                    TextField("", value: $walkTime, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 45)
                        .multilineTextAlignment(.center)

                    Text("min")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            Text("We'll calculate the best train based on your schedule")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var notificationsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: enableNotifications ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(enableNotifications ? .accentColor : .gray)

            Text("Get notified")
                .font(.title3)
                .fontWeight(.medium)

            Toggle(isOn: $enableNotifications) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable notifications")
                        .fontWeight(.medium)
                    Text("We'll remind you when it's time to leave")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 60)

            if enableNotifications {
                VStack(alignment: .leading, spacing: 6) {
                    Label("15 min warning before departure", systemImage: "checkmark.circle.fill")
                    Label("Alert when it's time to go", systemImage: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundColor(.green)
            }

            Spacer()
        }
        .padding(24)
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)

            Text("You're all set!")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Label("\(selectedOrigin) → \(selectedDestination)", systemImage: "tram.fill")
                Label("Leave at \(formattedTime)", systemImage: "clock")
                Label(enableNotifications ? "Notifications on" : "Notifications off",
                      systemImage: enableNotifications ? "bell.fill" : "bell.slash")
            }
            .font(.callout)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("Click the train icon in your menu bar to see trains")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: leaveTime)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 && currentStep < totalSteps - 1 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    saveAndComplete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func saveAndComplete() {
        let trip = Trip(
            route: Route(origin: selectedOrigin, destination: selectedDestination),
            leaveTime: leaveTime,
            walkTimeMinutes: walkTime,
            enable15MinWarning: enableNotifications,
            enableTimeToLeaveAlert: enableNotifications
        )

        var newSettings = AppSettings()
        newSettings.trips = [trip]
        newSettings.activeTripId = trip.id

        settingsManager.saveSettings(newSettings)

        // Mark setup as complete
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")

        onComplete()
    }
}
