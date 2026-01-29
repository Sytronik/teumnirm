import ApplicationServices
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

// MARK: - Activity Monitor

/// Monitors keyboard and mouse activity using IOKit HID events
class ActivityMonitor {
    private var hidManager: IOHIDManager?
    private var isMonitoring = false

    /// Callback when any keyboard/mouse activity is detected
    var onActivity: (() -> Void)?

    // Throttle activity callbacks to avoid excessive calls
    private var lastActivityTime: Date = .distantPast
    private let activityThrottleInterval: TimeInterval = 0.5

    init() {}

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else { return }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("[ActivityMonitor] Failed to create HID Manager")
            return
        }

        // Match keyboards, mice, and pointing devices
        let deviceMatching: [[String: Any]] = [
            // Keyboard
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
            ],
            // Mouse
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
            ],
            // Pointer (trackpad, etc.)
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer,
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, deviceMatching as CFArray)

        // Set up input value callback
        let inputCallback: IOHIDValueCallback = { context, _, _, _ in
            guard let context = context else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleHIDInput()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, inputCallback, context)

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Open the HID Manager
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[ActivityMonitor] Failed to open HID Manager: \(result)")
            return
        }

        isMonitoring = true
        print("[ActivityMonitor] Started monitoring keyboard/mouse activity")
    }

    func stopMonitoring() {
        guard isMonitoring, let manager = hidManager else { return }

        IOHIDManagerUnscheduleFromRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        hidManager = nil
        isMonitoring = false
        print("[ActivityMonitor] Stopped monitoring")
    }

    // MARK: - Private Methods

    private func handleHIDInput() {
        let now = Date()

        // Throttle callbacks
        guard now.timeIntervalSince(lastActivityTime) >= activityThrottleInterval else {
            return
        }

        lastActivityTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onActivity?()
        }
    }
}

// MARK: - Alternative: CGEvent-based Monitor

/// Alternative activity monitor using CGEvent tap (requires Accessibility permission)
/// This is more reliable but requires explicit accessibility permission
class CGEventActivityMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false

    var onActivity: (() -> Void)?

    private var lastActivityTime: Date = .distantPast
    private let activityThrottleInterval: TimeInterval = 0.5

    init() {}

    deinit {
        stopMonitoring()
    }

    func startMonitoring() -> Bool {
        guard !isMonitoring else { return true }

        // Events to monitor
        let eventMask: CGEventMask =
            ((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.rightMouseUp.rawValue) | (1 << CGEventType.scrollWheel.rawValue))

        // Create event tap
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CGEventActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleEvent()
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: refcon
            )
        else {
            print(
                "[CGEventActivityMonitor] Failed to create event tap. Check Accessibility permissions."
            )
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            print("[CGEventActivityMonitor] Failed to create run loop source")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isMonitoring = true
        print("[CGEventActivityMonitor] Started monitoring")
        return true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        print("[CGEventActivityMonitor] Stopped monitoring")
    }

    private func handleEvent() {
        let now = Date()

        guard now.timeIntervalSince(lastActivityTime) >= activityThrottleInterval else {
            return
        }

        lastActivityTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onActivity?()
        }
    }

    // MARK: - Permission Check

    static func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("[CGEventActivityMonitor] Accessibility permission not granted")
        }
        return trusted
    }

    static func requestAccessibilityPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
