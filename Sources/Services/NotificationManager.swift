import Foundation
import UserNotifications
import AppKit
import Observation

@Observable
@MainActor
final class NotificationManager: NSObject {
    private var monitoringTask: Task<Void, Never>?
    private var hasShown15MinWarning = false
    private var hasShownTimeToLeave = false
    private var lastNotificationDate: Date?
    private var notificationsAvailable = false

    // Current trip ID for namespaced keys
    private var currentTripId: UUID?

    private var lastWarningDateKey: String {
        guard let id = currentTripId else { return "TenfeLastWarningDate" }
        return "TenfeLastWarningDate_\(id)"
    }

    private var lastTimeToLeaveDateKey: String {
        guard let id = currentTripId else { return "TenfeLastTimeToLeaveDate" }
        return "TenfeLastTimeToLeaveDate_\(id)"
    }

    override init() {
        super.init()
        // Check if we're running in a proper app bundle (required for notifications)
        notificationsAvailable = Bundle.main.bundleIdentifier != nil
        if notificationsAvailable {
            requestNotificationPermissions()
        } else {
            print("Running without app bundle - notifications disabled")
        }
    }

    private func loadPersistedState() {
        let calendar = Calendar.current

        // Check if we already sent notifications today (survives app restart)
        if let lastWarningDate = UserDefaults.standard.object(forKey: lastWarningDateKey) as? Date,
           calendar.isDateInToday(lastWarningDate) {
            hasShown15MinWarning = true
        }

        if let lastTimeToLeaveDate = UserDefaults.standard.object(forKey: lastTimeToLeaveDateKey) as? Date,
           calendar.isDateInToday(lastTimeToLeaveDate) {
            hasShownTimeToLeave = true
        }
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permissions granted")
            } else if let error = error {
                print("Error requesting notifications: \(error)")
            }
        }
    }

    nonisolated func sendTestNotification() {
        Task { @MainActor in
            guard notificationsAvailable else {
                print("Notifications not available - app not running in proper bundle")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "🚂 Tenfe"
            content.subtitle = "Test notification"
            content.body = "Notifications are working correctly!"
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error sending test notification: \(error)")
                } else {
                    print("Test notification sent successfully")
                }
            }
        }
    }

    func startMonitoring(trip: Trip, trainService: TrainService) {
        // Update current trip ID and reload persisted state
        currentTripId = trip.id
        resetDailyFlags()
        loadPersistedState()

        // Cancel existing task
        monitoringTask?.cancel()

        // Check every minute for notification triggers using structured concurrency
        monitoringTask = Task { @MainActor in
            // Check immediately
            await checkAndSendNotifications(trip: trip, trainService: trainService)

            // Then check every minute
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await checkAndSendNotifications(trip: trip, trainService: trainService)
            }
        }
    }

    private func checkAndSendNotifications(trip: Trip, trainService: TrainService) async {
        let now = Date()

        // Get today's leave time
        guard let todayLeaveTime = combineDateWithTime(date: now, time: trip.leaveTime) else { return }

        // Skip if leave time has passed by more than 1 hour
        if now > todayLeaveTime.addingTimeInterval(3600) {
            resetDailyFlags()
            return
        }

        let timeUntilLeave = todayLeaveTime.timeIntervalSince(now)
        let minutesUntilLeave = Int(timeUntilLeave / 60)

        // 15-minute warning
        if trip.enable15MinWarning && !hasShown15MinWarning && minutesUntilLeave <= 15 && minutesUntilLeave > 10 {
            sendWarningNotification(trip: trip, trainService: trainService)
            hasShown15MinWarning = true
            UserDefaults.standard.set(Date(), forKey: lastWarningDateKey)
        }

        // Time to leave notification (accounting for walk time)
        let walkTime = TimeInterval(trip.walkTimeMinutes * 60)
        let optimalLeaveTime = getOptimalDepartureTime(trip: trip, trainService: trainService)

        if let optimalLeaveTime = optimalLeaveTime {
            let timeToLeaveNow = optimalLeaveTime.addingTimeInterval(-walkTime - 180) // 3 min buffer
            let minutesUntilOptimalLeave = Int(timeToLeaveNow.timeIntervalSince(now) / 60)

            if trip.enableTimeToLeaveAlert && !hasShownTimeToLeave && minutesUntilOptimalLeave <= 0 && minutesUntilOptimalLeave > -5 {
                sendTimeToLeaveNotification(trip: trip, trainService: trainService, targetTrain: optimalLeaveTime)
                hasShownTimeToLeave = true
                UserDefaults.standard.set(Date(), forKey: lastTimeToLeaveDateKey)
            }
        }
    }

    private func sendWarningNotification(trip: Trip, trainService: TrainService) {
        guard notificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "🚂 Tenfe"
        content.subtitle = "Leaving for \(trip.route.destination) soon!"

        let nextTrains = trainService.nextTrains.prefix(3)
        let trainTimes = nextTrains.map { $0.departureTimeString }.joined(separator: ", ")
        content.body = "Next trains: \(trainTimes)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendTimeToLeaveNotification(trip: Trip, trainService: TrainService, targetTrain: Date) {
        guard notificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "🚂 Tenfe"
        content.subtitle = "Time to leave now!"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let trainTime = formatter.string(from: targetTrain)

        let minutesUntilTrain = Int(targetTrain.timeIntervalSince(Date()) / 60)
        content.body = "Train to \(trip.route.destination) departs at \(trainTime) (in \(minutesUntilTrain) minutes)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func getOptimalDepartureTime(trip: Trip, trainService: TrainService) -> Date? {
        // Find the best train based on leave time and walk time
        guard let todayLeaveTime = combineDateWithTime(date: Date(), time: trip.leaveTime) else {
            return nil
        }

        let arrivalAtStation = todayLeaveTime.addingTimeInterval(TimeInterval(trip.walkTimeMinutes * 60))
        return trainService.getNextTrainAfter(date: arrivalAtStation)?.departureTime
    }

    private func combineDateWithTime(date: Date, time: Date) -> Date? {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return calendar.date(from: combined)
    }

    private func resetDailyFlags() {
        let calendar = Calendar.current
        if let lastDate = lastNotificationDate {
            if !calendar.isDateInToday(lastDate) {
                hasShown15MinWarning = false
                hasShownTimeToLeave = false
                // Clear persisted state for new day
                UserDefaults.standard.removeObject(forKey: lastWarningDateKey)
                UserDefaults.standard.removeObject(forKey: lastTimeToLeaveDateKey)
            }
        }
        lastNotificationDate = Date()
    }

    nonisolated deinit {
        // Task will be automatically cancelled when deallocated
    }
}
