import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, ObservableObject {
    private var notificationTimer: Timer?
    private var hasShown15MinWarning = false
    private var hasShownTimeToLeave = false
    private var lastNotificationDate: Date?
    private var notificationsAvailable = false

    // UserDefaults keys for persisting notification state across app restarts
    private let lastWarningDateKey = "TenfeLastWarningDate"
    private let lastTimeToLeaveDateKey = "TenfeLastTimeToLeaveDate"

    override init() {
        super.init()
        // Check if we're running in a proper app bundle (required for notifications)
        notificationsAvailable = Bundle.main.bundleIdentifier != nil
        if notificationsAvailable {
            requestNotificationPermissions()
        } else {
            print("Running without app bundle - notifications disabled")
        }
        loadPersistedState()
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

    func sendTestNotification() {
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

    func startMonitoring(trainService: TrainService, settings: AppSettings) {
        // Reset flags at start of new monitoring session
        resetDailyFlags()

        // Cancel existing timer
        notificationTimer?.invalidate()

        // Check every minute for notification triggers
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndSendNotifications(trainService: trainService, settings: settings)
        }

        // Also check immediately
        checkAndSendNotifications(trainService: trainService, settings: settings)
    }

    private func checkAndSendNotifications(trainService: TrainService, settings: AppSettings) {
        let now = Date()

        // Get today's leave time
        guard let todayLeaveTime = combineDateWithTime(date: now, time: settings.leaveTime) else { return }

        // Skip if leave time has passed by more than 1 hour
        if now > todayLeaveTime.addingTimeInterval(3600) {
            resetDailyFlags()
            return
        }

        let timeUntilLeave = todayLeaveTime.timeIntervalSince(now)
        let minutesUntilLeave = Int(timeUntilLeave / 60)

        // 15-minute warning
        if settings.enable15MinWarning && !hasShown15MinWarning && minutesUntilLeave <= 15 && minutesUntilLeave > 10 {
            sendWarningNotification(trainService: trainService, settings: settings)
            hasShown15MinWarning = true
            UserDefaults.standard.set(Date(), forKey: lastWarningDateKey)
        }

        // Time to leave notification (accounting for walk time)
        let walkTime = TimeInterval(settings.walkTimeMinutes * 60)
        let optimalLeaveTime = getOptimalDepartureTime(trainService: trainService, settings: settings)

        if let optimalLeaveTime = optimalLeaveTime {
            let timeToLeaveNow = optimalLeaveTime.addingTimeInterval(-walkTime - 180) // 3 min buffer
            let minutesUntilOptimalLeave = Int(timeToLeaveNow.timeIntervalSince(now) / 60)

            if settings.enableTimeToLeaveAlert && !hasShownTimeToLeave && minutesUntilOptimalLeave <= 0 && minutesUntilOptimalLeave > -5 {
                sendTimeToLeaveNotification(trainService: trainService, settings: settings, targetTrain: optimalLeaveTime)
                hasShownTimeToLeave = true
                UserDefaults.standard.set(Date(), forKey: lastTimeToLeaveDateKey)
            }
        }
    }

    private func sendWarningNotification(trainService: TrainService, settings: AppSettings) {
        guard notificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "🚂 Tenfe"
        content.subtitle = "Leaving for \(settings.route.destination) soon!"

        let nextTrains = trainService.nextTrains.prefix(3)
        let trainTimes = nextTrains.map { $0.departureTimeString }.joined(separator: ", ")
        content.body = "Next trains: \(trainTimes)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendTimeToLeaveNotification(trainService: TrainService, settings: AppSettings, targetTrain: Date) {
        guard notificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = "🚂 Tenfe"
        content.subtitle = "Time to leave now!"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let trainTime = formatter.string(from: targetTrain)

        let minutesUntilTrain = Int(targetTrain.timeIntervalSince(Date()) / 60)
        content.body = "Train to \(settings.route.destination) departs at \(trainTime) (in \(minutesUntilTrain) minutes)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func getOptimalDepartureTime(trainService: TrainService, settings: AppSettings) -> Date? {
        // Find the best train based on leave time and walk time
        guard let todayLeaveTime = combineDateWithTime(date: Date(), time: settings.leaveTime) else {
            return nil
        }

        let arrivalAtStation = todayLeaveTime.addingTimeInterval(TimeInterval(settings.walkTimeMinutes * 60))
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

    deinit {
        notificationTimer?.invalidate()
    }
}