import AppKit

// MARK: - Welcome Window Controller

/// Displays a welcome window on first launch to inform users about the menu bar app
class WelcomeWindowController: NSObject, NSWindowDelegate {

    // MARK: - Properties

    private var window: NSWindow?

    /// Callback when user dismisses the welcome window
    var onDismiss: (() -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    func showWindow() {
        guard window == nil else { return }

        // Get the main screen
        guard let screen = NSScreen.main else { return }

        // Create window
        let windowWidth: CGFloat = 420
        let windowHeight: CGFloat = 240
        let windowRect = NSRect(
            x: (screen.frame.width - windowWidth) / 2,
            y: (screen.frame.height - windowHeight) / 2 + 100,  // Slightly above center
            width: windowWidth,
            height: windowHeight
        )

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = L.Welcome.title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hasShadow = true
        window.delegate = self

        // Create content view
        let contentView = NSView(frame: NSRect(origin: .zero, size: windowRect.size))
        contentView.wantsLayer = true

        // App icon
        let iconSize: CGFloat = 64
        let iconView = NSImageView(
            frame: NSRect(
                x: (windowWidth - iconSize) / 2,
                y: windowHeight - iconSize - 30,
                width: iconSize,
                height: iconSize
            )
        )
        if let appIcon = NSImage(systemSymbolName: "timer", accessibilityDescription: "Teumnirm") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
            iconView.image = appIcon.withSymbolConfiguration(config)
            iconView.contentTintColor = .controlAccentColor
        }
        contentView.addSubview(iconView)

        // Description label
        let descLabel = NSTextField(wrappingLabelWithString: L.Welcome.description)
        descLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        descLabel.textColor = .labelColor
        descLabel.alignment = .center
        descLabel.frame = NSRect(x: 30, y: 70, width: windowWidth - 60, height: 70)
        contentView.addSubview(descLabel)

        // Menu bar hint
        let hintLabel = NSTextField(labelWithString: L.Welcome.menuBarHint)
        hintLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.frame = NSRect(x: 30, y: 45, width: windowWidth - 60, height: 18)
        contentView.addSubview(hintLabel)

        // Got it button
        let button = NSButton(
            title: L.Welcome.gotIt, target: self, action: #selector(dismissButtonClicked)
        )
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        button.frame = NSRect(x: (windowWidth - 100) / 2, y: 10, width: 100, height: 30)
        button.keyEquivalent = "\r"  // Enter key
        contentView.addSubview(button)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        self.window = window

        // Activate the app to bring window to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onDismiss?()
        window = nil
    }

    // MARK: - Private Methods

    @objc private func dismissButtonClicked() {
        onDismiss?()
        hideWindow()
    }
}
