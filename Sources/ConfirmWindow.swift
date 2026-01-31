import AppKit

// MARK: - Confirm Window Controller

/// Displays a confirmation window on top of the blur overlay
class ConfirmWindowController {

    // MARK: - Properties

    private var window: NSWindow?
    private var countdownLabel: NSTextField?
    private var autoRestoreTimer: Timer?
    private var countdownUpdateTimer: Timer?
    private var breakStartTime: Date?

    /// Callback when user confirms break is complete
    var onConfirm: (() -> Void)?

    /// Auto restore interval (default 5 minutes)
    var autoRestoreInterval: TimeInterval = AppConstants.autoRestoreInterval

    // MARK: - Initialization

    init() {}

    deinit {
        hideWindow()
    }

    // MARK: - Public Methods

    func showWindow() {
        guard window == nil else { return }

        breakStartTime = Date()

        // Get the main screen
        guard let screen = NSScreen.main else { return }

        // Create window
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 200
        let windowRect = NSRect(
            x: (screen.frame.width - windowWidth) / 2,
            y: (screen.frame.height - windowHeight) / 2,
            width: windowWidth,
            height: windowHeight
        )

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        // Above the blur overlay
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true

        // Create transparent container view
        let containerView = NSView(frame: NSRect(origin: .zero, size: windowRect.size))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        // Create visual effect view as subview
        let contentView = NSVisualEffectView(frame: containerView.bounds)
        contentView.blendingMode = .behindWindow
        contentView.material = .hudWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        containerView.addSubview(contentView)

        // Title label
        let titleLabel = NSTextField(labelWithString: L.ConfirmWindow.title)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 0, y: 130, width: windowWidth, height: 40)
        contentView.addSubview(titleLabel)

        // Subtitle label
        let subtitleLabel = NSTextField(labelWithString: L.ConfirmWindow.subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .white.withAlphaComponent(0.8)
        subtitleLabel.alignment = .center
        subtitleLabel.frame = NSRect(x: 0, y: 105, width: windowWidth, height: 20)
        contentView.addSubview(subtitleLabel)

        // Countdown label
        let countdown = NSTextField(
            labelWithString: L.ConfirmWindow.autoDismissIn(minutes: 5, seconds: 0)
        )
        countdown.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countdown.textColor = .white.withAlphaComponent(0.6)
        countdown.alignment = .center
        countdown.frame = NSRect(x: 0, y: 75, width: windowWidth, height: 20)
        contentView.addSubview(countdown)
        self.countdownLabel = countdown

        // Confirm button
        let button = NSButton(
            title: L.ConfirmWindow.endBreak, target: self, action: #selector(confirmButtonClicked)
        )
        button.bezelStyle = .regularSquare
        button.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        button.frame = NSRect(x: (windowWidth - 100) / 2, y: 25, width: 100, height: 40)
        button.keyEquivalent = "\r"  // Enter key

        // Style the button
        button.wantsLayer = true
        button.layer?.cornerRadius = 10

        contentView.addSubview(button)

        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)

        self.window = window

        // Start timers
        startAutoRestoreTimer()
        startCountdownUpdateTimer()

        // Make sure the window can receive key events
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        autoRestoreTimer?.invalidate()
        autoRestoreTimer = nil
        countdownUpdateTimer?.invalidate()
        countdownUpdateTimer = nil

        window?.orderOut(nil)
        window = nil
        countdownLabel = nil
        breakStartTime = nil
    }

    // MARK: - Private Methods

    private func startAutoRestoreTimer() {
        autoRestoreTimer?.invalidate()
        autoRestoreTimer = Timer.scheduledTimer(
            withTimeInterval: autoRestoreInterval,
            repeats: false
        ) { [weak self] _ in
            self?.autoRestore()
        }
    }

    private func startCountdownUpdateTimer() {
        countdownUpdateTimer?.invalidate()
        countdownUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            self?.updateCountdown()
        }
    }

    private func updateCountdown() {
        guard let startTime = breakStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, autoRestoreInterval - elapsed)

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60

        countdownLabel?.stringValue = L.ConfirmWindow.autoDismissIn(
            minutes: minutes, seconds: seconds)
    }

    private func autoRestore() {
        print("[ConfirmWindow] Auto-restoring after timeout")
        confirmBreak()
    }

    @objc private func confirmButtonClicked() {
        print("[ConfirmWindow] User confirmed break complete")
        confirmBreak()
    }

    private func confirmBreak() {
        hideWindow()
        onConfirm?()
    }
}

// MARK: - Menu Bar Confirm Action

extension ConfirmWindowController {
    /// Call this from menu bar to confirm break
    func confirmFromMenuBar() {
        if window != nil {
            confirmBreak()
        }
    }

    var isShowingWindow: Bool {
        return window != nil
    }
}
