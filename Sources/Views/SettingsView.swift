import SwiftUI

@MainActor
struct SettingsView: View {
    let settingsManager: SettingsManager
    var notificationManager: NotificationManager?
    var onRunWizard: (@MainActor () -> Void)?
    var onClose: (@MainActor () -> Void)?

    @State private var editingTrip: Trip?
    @State private var isNewTrip = false

    // Edit mode fields
    @State private var tripName: String = ""
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

            if editingTrip != nil {
                // Edit mode
                ScrollView {
                    VStack(spacing: 20) {
                        nameSection
                        routeSection
                        scheduleSection
                        editNotificationsSection
                    }
                    .padding(24)
                }

                Divider()

                editFooterButtons
            } else {
                // List mode
                ScrollView {
                    VStack(spacing: 20) {
                        tripsSection
                        testNotificationSection
                        wizardSection
                    }
                    .padding(24)
                }

                Divider()

                listFooterButtons
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            if editingTrip != nil {
                Button(action: { cancelEdit() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: editingTrip != nil ? "pencil.circle.fill" : "gearshape.fill")
                .font(.title2)
                .foregroundColor(.secondary)

            Text(editingTrip != nil ? (isNewTrip ? "New Trip" : "Edit Trip") : "Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - List Mode Sections

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trips", systemImage: "tram.fill")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ForEach(settingsManager.settings.trips) { trip in
                    TripRowView(
                        trip: trip,
                        isActive: trip.id == settingsManager.settings.activeTrip?.id,
                        canDelete: settingsManager.settings.trips.count > 1,
                        onActivate: {
                            settingsManager.setActiveTrip(id: trip.id)
                        },
                        onEdit: {
                            startEditing(trip: trip, isNew: false)
                        },
                        onDelete: {
                            settingsManager.deleteTrip(id: trip.id)
                        }
                    )
                }

                Button(action: {
                    let newTrip = Trip()
                    startEditing(trip: newTrip, isNew: true)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Trip")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var testNotificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notifications", systemImage: "bell.fill")
                .font(.headline)
                .foregroundColor(.primary)

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

    // MARK: - Edit Mode Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Name", systemImage: "tag.fill")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                TextField("e.g. Morning commute", text: $tripName)
                    .textFieldStyle(.roundedBorder)

                Text("Leave empty to auto-generate from route")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

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
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                        Text("Departure")
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

    private var editNotificationsSection: some View {
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
                            Text("Get reminded before departure")
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
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Footers

    private var listFooterButtons: some View {
        HStack {
            Button("Close") {
                onClose?()
            }
            .keyboardShortcut(.escape)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var editFooterButtons: some View {
        HStack {
            Button("Cancel") {
                cancelEdit()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button("Save") {
                saveTrip()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Edit Actions

    private func startEditing(trip: Trip, isNew: Bool) {
        editingTrip = trip
        isNewTrip = isNew
        tripName = trip.name
        selectedOrigin = trip.route.origin
        selectedDestination = trip.route.destination
        leaveTime = trip.leaveTime
        walkTime = trip.walkTimeMinutes
        enable15Min = trip.enable15MinWarning
        enableTimeToLeave = trip.enableTimeToLeaveAlert
    }

    private func cancelEdit() {
        editingTrip = nil
        isNewTrip = false
    }

    private func saveTrip() {
        guard var trip = editingTrip else { return }
        trip.name = tripName
        trip.route = Route(origin: selectedOrigin, destination: selectedDestination)
        trip.leaveTime = leaveTime
        trip.walkTimeMinutes = walkTime
        trip.enable15MinWarning = enable15Min
        trip.enableTimeToLeaveAlert = enableTimeToLeave

        if isNewTrip {
            settingsManager.addTrip(trip)
        } else {
            settingsManager.updateTrip(trip)
        }

        editingTrip = nil
        isNewTrip = false
    }
}

// MARK: - Trip Row View

@MainActor
struct TripRowView: View {
    let trip: Trip
    let isActive: Bool
    let canDelete: Bool
    let onActivate: @MainActor () -> Void
    let onEdit: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Active indicator
            Button(action: onActivate) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isActive ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            // Trip info
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("Leave \(formattedTime(trip.leaveTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(trip.walkTimeMinutes) min walk")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(canDelete ? .red.opacity(0.7) : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formattedTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
