import AppKit
import UserNotifications

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - UI Components

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var confirmMenuItem: NSMenuItem!
    private var timerMenuItem: NSMenuItem!
    private var statusPopover: NSPopover?

    // MARK: - Managers

    let blurOverlayManager = BlurOverlayManager()
    let hueController = HueController()
    private var activityMonitor: CGEventActivityMonitor?
    private var confirmWindowController = ConfirmWindowController()
    private var settingsWindowController = SettingsWindowController()
    private var welcomeWindowController = WelcomeWindowController()

    // MARK: - State

    private var _state: AppState = .paused
    var state: AppState {
        get { _state }
        set {
            guard newValue != _state else { return }
            let oldState = _state
            _state = newValue
            handleStateTransition(from: oldState, to: newValue)
        }
    }

    // MARK: - Timers

    private var usageTimer: Timer?
    private var timerUpdateTimer: Timer?
    private var accumulatedUsageTime: TimeInterval = 0
    private var usageResumeTime: Date?
    private var isUsagePaused = false
    var lastActivityTime: Date?  // Last activity time (used for idle detection)

    // MARK: - Settings

    var breakInterval: TimeInterval = AppConstants.defaultBreakInterval {
        didSet {
            UserDefaults.standard.set(breakInterval, forKey: SettingsKeys.breakInterval)
        }
    }

    var autoRestoreInterval: TimeInterval = AppConstants.autoRestoreInterval {
        didSet {
            confirmWindowController.autoRestoreInterval = autoRestoreInterval
        }
    }

    var hueEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(hueEnabled, forKey: SettingsKeys.hueEnabled)
        }
    }

    var showTimerInMenuBar: Bool = false {
        didSet {
            UserDefaults.standard.set(showTimerInMenuBar, forKey: SettingsKeys.showTimerInMenuBar)
            updateMenuBarTimerDisplay()
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupMenuBar()
        setupActivityMonitor()
        setupConfirmWindow()
        blurOverlayManager.setupOverlayWindows()
        blurOverlayManager.registerDisplayChangeCallback()

        // Show welcome window on first launch
        showWelcomeWindowIfNeeded()

        // Start monitoring
        state = .monitoring

        print("[AppDelegate] App launched - Teumnirm (틈니름)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityMonitor?.stopMonitoring()
        usageTimer?.invalidate()
        timerUpdateTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Teumnirm")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        // Status
        statusMenuItem = NSMenuItem(title: L.Menu.statusStarting, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Timer display
        timerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timerMenuItem.isEnabled = false
        menu.addItem(timerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Enabled toggle
        enabledMenuItem = NSMenuItem(
            title: L.Menu.monitoring, action: #selector(toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)

        // Reset timer
        let resetItem = NSMenuItem(
            title: L.Menu.resetTimer, action: #selector(resetTimer), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // Confirm break (only visible during break time)
        confirmMenuItem = NSMenuItem(
            title: L.Menu.endBreak, action: #selector(confirmBreak), keyEquivalent: "\r")
        confirmMenuItem.target = self
        confirmMenuItem.isHidden = true
        menu.addItem(confirmMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: L.Menu.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: L.Menu.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupActivityMonitor() {
        activityMonitor = CGEventActivityMonitor()
        activityMonitor?.onActivity = { [weak self] in
            self?.handleActivity()
        }
    }

    private func setupConfirmWindow() {
        confirmWindowController.autoRestoreInterval = autoRestoreInterval
        confirmWindowController.onConfirm = { [weak self] in
            self?.endBreakTime()
        }
    }

    private func showWelcomeWindowIfNeeded() {
        let defaults = UserDefaults.standard
        let hasShownWelcome = defaults.bool(forKey: SettingsKeys.hasShownWelcome)

        if hasShownWelcome {
            // Show brief status popover for returning users
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showStatusPopover()
            }
            return
        }

        welcomeWindowController.onDismiss = { [weak self] in
            defaults.set(true, forKey: SettingsKeys.hasShownWelcome)
            // Show popover to point to menu bar icon after welcome window closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.showStatusPopover()
            }
        }
        welcomeWindowController.showWindow()
    }

    private func showStatusPopover() {
        guard let button = statusItem.button else { return }

        // Create popover content
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))

        // Title label
        let titleLabel = NSTextField(labelWithString: L.Popover.monitoringStarted)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 12, y: 24, width: 176, height: 18)
        contentView.addSubview(titleLabel)

        // Subtitle label
        let subtitleLabel = NSTextField(labelWithString: L.Popover.clickForOptions)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 12, y: 8, width: 176, height: 14)
        contentView.addSubview(subtitleLabel)

        // Create view controller
        let viewController = NSViewController()
        viewController.view = contentView

        // Create and show popover
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.animates = true

        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Auto-close after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.statusPopover?.performClose(nil)
            self?.statusPopover = nil
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: SettingsKeys.breakInterval) != nil {
            breakInterval = defaults.double(forKey: SettingsKeys.breakInterval)
        }

        hueEnabled = defaults.bool(forKey: SettingsKeys.hueEnabled)
        showTimerInMenuBar = defaults.bool(forKey: SettingsKeys.showTimerInMenuBar)

        hueController.loadFromDefaults()

        let useCompatibilityMode = defaults.bool(forKey: SettingsKeys.useCompatibilityMode)
        blurOverlayManager.setCompatibilityMode(useCompatibilityMode)
    }

    // MARK: - State Machine

    private func handleStateTransition(from oldState: AppState, to newState: AppState) {
        print("[AppDelegate] State: \(oldState) -> \(newState)")

        switch newState {
        case .monitoring:
            startMonitoring()
        case .breakTime:
            startBreakTime()
        case .paused:
            stopMonitoring()
        }

        updateUI()
    }

    private func startMonitoring() {
        let now = Date()
        accumulatedUsageTime = 0
        usageResumeTime = now
        isUsagePaused = false
        lastActivityTime = now

        // Start activity monitor
        if !activityMonitor!.startMonitoring() {
            print("[AppDelegate] Failed to start activity monitor")
            // Request permission only when it's not granted
            if !CGEventActivityMonitor.checkInputMonitoringPermission() {
                print("[AppDelegate] Requesting input monitoring permission")
                CGEventActivityMonitor.requestInputMonitoringPermission()
            }
        }

        // Start usage timer
        startUsageTimer()
        startTimerUpdateTimer()
    }

    private func stopMonitoring() {
        activityMonitor?.stopMonitoring()
        usageTimer?.invalidate()
        usageTimer = nil
        timerUpdateTimer?.invalidate()
        timerUpdateTimer = nil
    }

    private func startBreakTime() {
        stopMonitoring()

        // Show blur overlay
        blurOverlayManager.showOverlay()

        // Show confirm window
        confirmWindowController.showWindow()

        // Set Hue lights to red
        if hueEnabled && hueController.isConfigured {
            Task {
                try? await hueController.setLightsToRed()
            }
        }

        print("[AppDelegate] Break time started")
    }

    private func endBreakTime() {
        // Hide blur overlay
        blurOverlayManager.hideOverlay()

        // Hide confirm window
        confirmWindowController.hideWindow()

        // Restore Hue lights
        if hueEnabled && hueController.isConfigured {
            Task {
                try? await hueController.restoreLights()
            }
        }

        // Resume monitoring
        state = .monitoring

        print("[AppDelegate] Break time ended")
    }

    // MARK: - Timer Management

    private func startUsageTimer() {
        usageTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkUsageTime()
        }
        // Add to .common mode so the timer runs while the menu is open
        RunLoop.main.add(timer, forMode: .common)
        usageTimer = timer
    }

    private func startTimerUpdateTimer() {
        timerUpdateTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimerDisplay()
        }
        // Add to .common mode so the timer runs while the menu is open
        RunLoop.main.add(timer, forMode: .common)
        timerUpdateTimer = timer
    }

    private func checkUsageTime() {
        guard state == .monitoring else { return }

        let now = Date()
        pauseUsageTimerIfNeeded(at: now)

        guard let elapsed = currentUsageElapsedTime(at: now) else { return }

        if elapsed >= breakInterval {
            state = .breakTime
        }
    }

    private func updateTimerDisplay() {
        guard state == .monitoring,
              let remaining = remainingBreakTime()
        else {
            timerMenuItem.title = ""
            updateMenuBarTimerDisplay()
            return
        }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60

        timerMenuItem.title = L.Menu.nextBreakIn(minutes: minutes, seconds: seconds)
        updateMenuBarTimerDisplay(minutes: minutes, seconds: seconds)
    }

    private func updateMenuBarTimerDisplay(minutes: Int? = nil, seconds: Int? = nil) {
        guard let statusItem = statusItem, let button = statusItem.button else { return }

        if showTimerInMenuBar, let minutes = minutes, let seconds = seconds {
            button.title = String(format: "%d:%02d", minutes, seconds)
            button.image = nil
        } else {
            button.title = ""
            // Restore icon based on current state
            switch state {
            case .monitoring:
                button.image = NSImage(
                    systemSymbolName: "timer", accessibilityDescription: "Monitoring")
            case .breakTime:
                button.image = NSImage(
                    systemSymbolName: "pause.circle.fill", accessibilityDescription: "Break Time")
            case .paused:
                button.image = NSImage(
                    systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            }
            button.image?.isTemplate = true
        }
    }

    // MARK: - Activity Handling

    private func handleActivity() {
        guard state == .monitoring else { return }

        let now = Date()

        if isUsagePaused {
            isUsagePaused = false
            usageResumeTime = now
            print("[AppDelegate] Activity detected, resuming usage timer")
        }

        lastActivityTime = now
    }

    private func pauseUsageTimerIfNeeded(at now: Date) {
        guard let lastActivity = lastActivityTime else { return }

        let idleTime = now.timeIntervalSince(lastActivity)
        let resetThreshold = breakInterval * AppConstants.idleResetRatio

        // If idle for half of break interval, reset the timer completely
        if idleTime >= resetThreshold {
            if !isUsagePaused || accumulatedUsageTime > 0 {
                accumulatedUsageTime = 0
                isUsagePaused = true
                usageResumeTime = now
                print("[AppDelegate] Idle for \(Int(idleTime))s (>= \(Int(resetThreshold))s), resetting usage timer")
            }
            return
        }

        // If idle for idleThreshold, pause the timer
        if !isUsagePaused && idleTime >= AppConstants.idleThreshold {
            if let resumeTime = usageResumeTime {
                accumulatedUsageTime += now.timeIntervalSince(resumeTime)
            }
            isUsagePaused = true
            usageResumeTime = now
            print("[AppDelegate] Idle detected, pausing usage timer")
        }
    }

    func currentUsageElapsedTime(at now: Date = Date()) -> TimeInterval? {
        guard state == .monitoring, let resumeTime = usageResumeTime else { return nil }

        let activeElapsed = isUsagePaused ? 0 : now.timeIntervalSince(resumeTime)
        return accumulatedUsageTime + activeElapsed
    }

    func remainingBreakTime(at now: Date = Date()) -> TimeInterval? {
        guard let elapsed = currentUsageElapsedTime(at: now) else { return nil }
        return max(0, breakInterval - elapsed)
    }

    // MARK: - UI Updates

    private func updateUI() {
        switch state {
        case .monitoring:
            statusMenuItem.title = L.Menu.statusMonitoring
            enabledMenuItem.state = .on
            confirmMenuItem.isHidden = true

        case .breakTime:
            statusMenuItem.title = L.Menu.statusBreakTime
            enabledMenuItem.state = .on
            confirmMenuItem.isHidden = false
            timerMenuItem.title = ""

        case .paused:
            statusMenuItem.title = L.Menu.statusPaused
            enabledMenuItem.state = .off
            confirmMenuItem.isHidden = true
            timerMenuItem.title = ""
        }

        // Update menu bar icon/timer display
        updateMenuBarTimerDisplay()
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled() {
        if state == .paused {
            state = .monitoring
        } else {
            if state == .breakTime {
                endBreakTime()
            }
            state = .paused
        }
    }

    @objc private func resetTimer() {
        if state == .breakTime {
            endBreakTime()
        } else if state == .monitoring {
            let now = Date()
            accumulatedUsageTime = 0
            usageResumeTime = now
            isUsagePaused = false
            lastActivityTime = now
            print("[AppDelegate] Timer reset")
        }
    }

    @objc private func confirmBreak() {
        if state == .breakTime {
            confirmWindowController.confirmFromMenuBar()
        }
    }

    @objc private func openSettings() {
        settingsWindowController.showSettings(appDelegate: self)
    }

    @objc private func quit() {
        // Clean up
        if state == .breakTime {
            blurOverlayManager.hideOverlay()
            confirmWindowController.hideWindow()

            if hueEnabled && hueController.isConfigured {
                Task {
                    try? await hueController.restoreLights()
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
                return
            }
        }

        NSApplication.shared.terminate(nil)
    }
}
