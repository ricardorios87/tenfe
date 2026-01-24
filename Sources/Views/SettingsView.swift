import SwiftUI

@MainActor
struct SettingsView: View {
    let settingsManager: SettingsManager
    var notificationManager: NotificationManager?
    var onRunWizard: (@MainActor () -> Void)?
    var onClose: (@MainActor () -> Void)?

    @State private var selectedOrigin: String = ""
    @State private var selectedDestination: String = ""
    @State private var leaveTime: Date = Date()
    @State private var walkTime: Int = 5
    @State private var enable15Min: Bool = true
    @State private var enableTimeToLeave: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    routeSection
                    scheduleSection
                    notificationsSection
                    wizardSection
                }
                .padding(24)
            }

            Divider()

            // Footer buttons
            footerButtons
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Sections

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Route", systemImage: "arrow.triangle.swap")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                HStack {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.green)
                        Text("From")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)

                    Picker("", selection: $selectedOrigin) {
                        ForEach(Station.madridStations, id: \.self) { station in
                            Text(station).tag(station)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.red)
                        Text("To")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)

                    Picker("", selection: $selectedDestination) {
                        ForEach(Station.madridStations, id: \.self) { station in
                            Text(station).tag(station)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedule", systemImage: "clock.fill")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                HStack {
                    HStack {
                        Image(systemName: "briefcase.fill")
                            .foregroundColor(.orange)
                        Text("Leave work")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120, alignment: .leading)

                    Spacer()

                    DatePicker("", selection: $leaveTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .frame(width: 80)
                }

                HStack {
                    HStack {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.blue)
                        Text("Walk time")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120, alignment: .leading)

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("", value: $walkTime, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)

                        Text("min")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notifications", systemImage: "bell.fill")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                Toggle(isOn: $enable15Min) {
                    HStack {
                        Image(systemName: "15.circle.fill")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("15 minute warning")
                            Text("Get reminded before your leave time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $enableTimeToLeave) {
                    HStack {
                        Image(systemName: "figure.walk.departure")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Time to leave alert")
                            Text("Know exactly when to head out")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Button(action: {
                    notificationManager?.sendTestNotification()
                }) {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Send Test Notification")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var wizardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Setup", systemImage: "wand.and.stars")
                .font(.headline)
                .foregroundColor(.primary)

            Button(action: {
                onRunWizard?()
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Run Setup Wizard Again")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                onClose?()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button("Save") {
                saveSettings()
                onClose?()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Data

    private func loadCurrentSettings() {
        let settings = settingsManager.settings
        selectedOrigin = settings.route.origin
        selectedDestination = settings.route.destination
        leaveTime = settings.leaveTime
        walkTime = settings.walkTimeMinutes
        enable15Min = settings.enable15MinWarning
        enableTimeToLeave = settings.enableTimeToLeaveAlert
    }

    private func saveSettings() {
        var newSettings = AppSettings()
        newSettings.route = Route(origin: selectedOrigin, destination: selectedDestination)
        newSettings.leaveTime = leaveTime
        newSettings.walkTimeMinutes = walkTime
        newSettings.enable15MinWarning = enable15Min
        newSettings.enableTimeToLeaveAlert = enableTimeToLeave

        settingsManager.saveSettings(newSettings)
    }
}
