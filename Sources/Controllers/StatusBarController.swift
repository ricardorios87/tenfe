import SwiftUI
import AppKit
import Observation

@Observable
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var wizardWindow: NSWindow?
    private var refreshTask: Task<Void, Never>?
    private var settingsObserverTask: Task<Void, Never>?

    var trainService = TrainService()
    var notificationManager = NotificationManager()
    var settingsManager = SettingsManager()

    init() {
        setupStatusBar()
        setupPopover()
        startMonitoring()

        // Check if first launch
        checkFirstLaunch()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Tenfe")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 200)
        popover.behavior = .transient
        self.popover = popover
    }

    private func updatePopoverContent() {
        popover?.contentViewController = NSHostingController(
            rootView: StatusBarPopupView(
                trainService: trainService,
                settingsManager: settingsManager,
                onTripSelected: { [weak self] tripId in
                    guard let self = self else { return }
                    self.settingsManager.setActiveTrip(id: tripId)
                    // Immediately reload trains for the new route
                    if let trip = self.settingsManager.settings.activeTrip {
                        Task { @MainActor in
                            await self.trainService.setRoute(trip.route)
                            self.notificationManager.startMonitoring(
                                trip: trip,
                                trainService: self.trainService
                            )
                        }
                    }
                },
                onSettingsClick: { [weak self] in
                    self?.openSettings()
                },
                onQuitClick: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    @objc private func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                closePopover()
            } else {
                showPopover(button)
            }
        }
    }

    private func showPopover(_ sender: NSView) {
        guard let popover = popover else { return }

        // Update popover content with latest data before showing
        updatePopoverContent()

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)

        // Start event monitor to close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.close()

        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - First Launch

    private func checkFirstLaunch() {
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        if !hasCompletedSetup {
            // Delay to ensure the app is fully loaded
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.openWizard()
            }
        }
    }

    // MARK: - Settings Window

    func openSettings() {
        closePopover()

        // Close wizard if open
        wizardWindow?.close()
        wizardWindow = nil

        // If settings window exists, just bring it to front
        if let existingWindow = settingsWindow {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        // Create new settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Tenfe Settings"
        window.isReleasedWhenClosed = false

        let settingsView = SettingsView(
            settingsManager: settingsManager,
            notificationManager: notificationManager,
            onRunWizard: { [weak self] in
                self?.closeSettingsAndOpenWizard()
            },
            onClose: { [weak self] in
                self?.closeSettings()
            }
        )

        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    private func closeSettings() {
        settingsWindow?.close()
    }

    private func closeSettingsAndOpenWizard() {
        settingsWindow?.close()
        settingsWindow = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.openWizard()
        }
    }

    // MARK: - Wizard Window

    func openWizard() {
        closePopover()

        // Close settings if open
        settingsWindow?.close()
        settingsWindow = nil

        // If wizard window exists, just bring it to front
        if let existingWindow = wizardWindow {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        // Create new wizard window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Tenfe Setup"
        window.isReleasedWhenClosed = false

        let wizardView = SetupWizardView(
            settingsManager: settingsManager,
            onComplete: { [weak self] in
                self?.closeWizard()
                // Update route and refresh trains after setup
                Task { @MainActor in
                    guard let self = self else { return }
                    await self.trainService.setRoute(self.settingsManager.settings.route)
                    if let activeTrip = self.settingsManager.settings.activeTrip {
                        self.notificationManager.startMonitoring(
                            trip: activeTrip,
                            trainService: self.trainService
                        )
                    }
                }
            }
        )

        window.contentView = NSHostingView(rootView: wizardView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        wizardWindow = window
    }

    private func closeWizard() {
        wizardWindow?.close()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Initialize train service with current route
        Task { @MainActor in
            await trainService.setRoute(settingsManager.settings.route)

            // Start notification monitoring based on active trip
            if let activeTrip = settingsManager.settings.activeTrip {
                notificationManager.startMonitoring(
                    trip: activeTrip,
                    trainService: trainService
                )
            }
        }

        // Refresh trains periodically (every 5 minutes)
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await trainService.refreshTrains()
            }
        }

        // Observe settings changes using AsyncStream
        settingsObserverTask = Task { @MainActor in
            for await newSettings in observeSettings() {
                await trainService.setRoute(newSettings.route)
                if let activeTrip = newSettings.activeTrip {
                    notificationManager.startMonitoring(
                        trip: activeTrip,
                        trainService: trainService
                    )
                }
            }
        }
    }

    private func observeSettings() -> AsyncStream<AppSettings> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var lastSettings = settingsManager.settings
                continuation.yield(lastSettings)

                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    let currentSettings = settingsManager.settings
                    if currentSettings.route.origin != lastSettings.route.origin ||
                       currentSettings.route.destination != lastSettings.route.destination ||
                       currentSettings.walkTimeMinutes != lastSettings.walkTimeMinutes ||
                       currentSettings.enable15MinWarning != lastSettings.enable15MinWarning ||
                       currentSettings.enableTimeToLeaveAlert != lastSettings.enableTimeToLeaveAlert ||
                       currentSettings.activeTripId != lastSettings.activeTripId ||
                       currentSettings.trips.count != lastSettings.trips.count {
                        continuation.yield(currentSettings)
                        lastSettings = currentSettings
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated deinit {
        // Tasks will be automatically cancelled when deallocated
    }
}
