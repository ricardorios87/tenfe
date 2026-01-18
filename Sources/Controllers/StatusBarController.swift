import SwiftUI
import AppKit
import Combine

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var wizardWindow: NSWindow?

    @Published var trainService = TrainService()
    @Published var notificationManager = NotificationManager()
    @Published var settingsManager = SettingsManager()

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
        popover.contentViewController = NSHostingController(
            rootView: StatusBarPopupView(
                trainService: trainService,
                settingsManager: settingsManager,
                onSettingsClick: { [weak self] in
                    self?.openSettings()
                },
                onQuitClick: {
                    NSApp.terminate(nil)
                }
            )
        )
        self.popover = popover
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

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)

        // Start event monitor to close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openWizard()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.openWizard()
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
                // Refresh trains after setup
                self?.trainService.refreshTrains()
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
        trainService.setRoute(settingsManager.settings.route)

        // Start notification monitoring based on settings
        notificationManager.startMonitoring(
            trainService: trainService,
            settings: settingsManager.settings
        )

        // Refresh trains periodically (every 5 minutes)
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.trainService.refreshTrains()
        }

        // Update train service when settings change
        settingsManager.$settings
            .sink { [weak self] newSettings in
                self?.trainService.setRoute(newSettings.route)
                self?.notificationManager.startMonitoring(
                    trainService: self?.trainService ?? TrainService(),
                    settings: newSettings
                )
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
