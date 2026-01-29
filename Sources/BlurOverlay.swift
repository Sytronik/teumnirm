import AppKit
import CoreGraphics

// MARK: - Private API Loading (for enhanced blur effect)

private let cgsMainConnectionID: (@convention(c) () -> UInt32)? = {
    guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
    guard let sym = dlsym(handle, "CGSMainConnectionID") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> UInt32).self)
}()

private let cgsSetWindowBackgroundBlurRadius: (@convention(c) (UInt32, UInt32, Int32) -> Int32)? = {
    guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
    guard let sym = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UInt32, UInt32, Int32) -> Int32).self)
}()

private var privateAPIsAvailable: Bool {
    return cgsMainConnectionID != nil && cgsSetWindowBackgroundBlurRadius != nil
}

// MARK: - Blur Overlay Manager

class BlurOverlayManager {
    private var windows: [NSWindow] = []
    private var blurViews: [NSVisualEffectView] = []
    private var currentBlurRadius: Int32 = 0
    private var targetBlurRadius: Int32 = 0
    private var useCompatibilityMode = false

    private var animationTimer: Timer?

    /// Callback when blur animation completes (reaches target)
    var onBlurComplete: (() -> Void)?

    init() {}

    deinit {
        animationTimer?.invalidate()
        removeOverlayWindows()
    }

    // MARK: - Public Methods

    func setupOverlayWindows() {
        removeOverlayWindows()

        for screen in NSScreen.screens {
            // Use full frame to cover entire screen including menu bar
            let frame = screen.frame

            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.isOpaque = false
            window.backgroundColor = .clear
            // Level above everything except the confirm window
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = true  // Allow clicks to pass through
            window.hasShadow = false

            // Create blur view
            let blurView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            blurView.blendingMode = .behindWindow
            blurView.material = .fullScreenUI
            blurView.state = .active
            blurView.alphaValue = 0  // Start invisible

            window.contentView = blurView

            windows.append(window)
            blurViews.append(blurView)
        }
    }

    func showOverlay() {
        if windows.isEmpty {
            setupOverlayWindows()
        }

        for window in windows {
            window.orderFrontRegardless()
        }

        targetBlurRadius = AppConstants.maxBlurRadius
        startAnimationTimer()
    }

    func hideOverlay() {
        targetBlurRadius = 0
        startAnimationTimer()
    }

    func removeOverlayWindows() {
        animationTimer?.invalidate()
        animationTimer = nil

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        blurViews.removeAll()
        currentBlurRadius = 0
        targetBlurRadius = 0
    }

    func rebuildOverlayWindows() {
        let wasVisible = currentBlurRadius > 0
        removeOverlayWindows()
        setupOverlayWindows()

        if wasVisible {
            showOverlay()
        }
    }

    func setCompatibilityMode(_ enabled: Bool) {
        useCompatibilityMode = enabled
    }

    // MARK: - Animation

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) {
            [weak self] _ in
            self?.updateBlur()
        }
    }

    private func updateBlur() {
        // Smooth transition
        if currentBlurRadius < targetBlurRadius {
            // Ease in: +2 per frame for faster appearance
            currentBlurRadius = min(currentBlurRadius + 2, targetBlurRadius)
        } else if currentBlurRadius > targetBlurRadius {
            // Fast ease out
            currentBlurRadius = max(currentBlurRadius - 8, targetBlurRadius)
        }

        // Check if animation complete
        if currentBlurRadius == targetBlurRadius {
            animationTimer?.invalidate()
            animationTimer = nil

            // Hide windows when fully transparent
            if currentBlurRadius == 0 {
                for window in windows {
                    window.orderOut(nil)
                }
            }

            onBlurComplete?()
        }

        // Apply blur
        applyBlur()
    }

    private func applyBlur() {
        // Calculate alpha for NSVisualEffectView
        let normalizedBlur = CGFloat(currentBlurRadius) / CGFloat(AppConstants.maxBlurRadius)
        let visualEffectAlpha = min(1.0, sqrt(normalizedBlur) * 1.2)

        if useCompatibilityMode || !privateAPIsAvailable {
            // Use NSVisualEffectView alpha (public API)
            for blurView in blurViews {
                blurView.alphaValue = visualEffectAlpha
            }
        } else if let getConnectionID = cgsMainConnectionID,
            let setBlurRadius = cgsSetWindowBackgroundBlurRadius
        {
            // Use private CoreGraphics API for better blur
            let cid = getConnectionID()
            for window in windows {
                _ = setBlurRadius(cid, UInt32(window.windowNumber), currentBlurRadius)
            }
            // Also set alpha for visual feedback
            for blurView in blurViews {
                blurView.alphaValue = visualEffectAlpha * 0.3  // Lighter overlay with private API
            }
        } else {
            // Fallback
            for blurView in blurViews {
                blurView.alphaValue = visualEffectAlpha
            }
        }
    }

    // MARK: - Display Change Handling

    func registerDisplayChangeCallback() {
        let callback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<BlurOverlayManager>.fromOpaque(userInfo).takeUnretainedValue()

            if flags.contains(.beginConfigurationFlag) {
                return
            }

            DispatchQueue.main.async {
                manager.rebuildOverlayWindows()
            }
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(callback, userInfo)
    }
}
