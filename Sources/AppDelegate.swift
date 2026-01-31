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

    // MARK: - Managers

    let blurOverlayManager = BlurOverlayManager()
    let hueController = HueController()
    private var activityMonitor: CGEventActivityMonitor?
    private var confirmWindowController = ConfirmWindowController()
    private var settingsWindowController = SettingsWindowController()

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
    var usageStartTime: Date?  // 연속 사용 시작 시간
    var lastActivityTime: Date?  // 마지막 활동 시간 (비활동 감지용)

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

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupMenuBar()
        setupActivityMonitor()
        setupConfirmWindow()
        blurOverlayManager.setupOverlayWindows()
        blurOverlayManager.registerDisplayChangeCallback()

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

    private func loadSettings() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: SettingsKeys.breakInterval) != nil {
            breakInterval = defaults.double(forKey: SettingsKeys.breakInterval)
        }

        hueEnabled = defaults.bool(forKey: SettingsKeys.hueEnabled)

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
        usageStartTime = now
        lastActivityTime = now

        // Start activity monitor
        if !activityMonitor!.startMonitoring() {
            print("[AppDelegate] Failed to start activity monitor")
            // 권한이 없는 경우에만 권한 요청
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
        // .common 모드에 추가하여 메뉴가 열려 있을 때도 타이머가 동작하도록 함
        RunLoop.main.add(timer, forMode: .common)
        usageTimer = timer
    }

    private func startTimerUpdateTimer() {
        timerUpdateTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimerDisplay()
        }
        // .common 모드에 추가하여 메뉴가 열려 있을 때도 타이머가 동작하도록 함
        RunLoop.main.add(timer, forMode: .common)
        timerUpdateTimer = timer
    }

    private func checkUsageTime() {
        guard state == .monitoring, let usageStart = usageStartTime else { return }

        let elapsed = Date().timeIntervalSince(usageStart)

        if elapsed >= breakInterval {
            state = .breakTime
        }
    }

    private func updateTimerDisplay() {
        guard state == .monitoring, let usageStart = usageStartTime else {
            timerMenuItem.title = ""
            return
        }

        let elapsed = Date().timeIntervalSince(usageStart)
        let remaining = max(0, breakInterval - elapsed)

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60

        timerMenuItem.title = L.Menu.nextBreakIn(minutes: minutes, seconds: seconds)
    }

    // MARK: - Activity Handling

    private func handleActivity() {
        guard state == .monitoring else { return }

        let now = Date()

        // 마지막 활동 이후 idleThreshold(3분) 이상 지났으면 휴식한 것으로 간주
        // → 연속 사용 시간 리셋
        if let lastActivity = lastActivityTime,
            now.timeIntervalSince(lastActivity) >= AppConstants.idleThreshold
        {
            usageStartTime = now
            print("[AppDelegate] Idle detected, resetting usage timer")
        }

        lastActivityTime = now
    }

    // MARK: - UI Updates

    private func updateUI() {
        switch state {
        case .monitoring:
            statusMenuItem.title = L.Menu.statusMonitoring
            statusItem.button?.image = NSImage(
                systemSymbolName: "timer", accessibilityDescription: "Monitoring")
            enabledMenuItem.state = .on
            confirmMenuItem.isHidden = true

        case .breakTime:
            statusMenuItem.title = L.Menu.statusBreakTime
            statusItem.button?.image = NSImage(
                systemSymbolName: "pause.circle.fill", accessibilityDescription: "Break Time")
            enabledMenuItem.state = .on
            confirmMenuItem.isHidden = false
            timerMenuItem.title = ""

        case .paused:
            statusMenuItem.title = L.Menu.statusPaused
            statusItem.button?.image = NSImage(
                systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            enabledMenuItem.state = .off
            confirmMenuItem.isHidden = true
            timerMenuItem.title = ""
        }
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
            usageStartTime = now
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
