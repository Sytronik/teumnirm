import AppKit
import Foundation

// MARK: - App Constants

enum AppConstants {
    static let appName = "Teumnirm"
    static let appNameKorean = "틈니름"
    static let defaultBreakInterval: TimeInterval = 55 * 60  // 55 minutes
    static let autoRestoreInterval: TimeInterval = 5 * 60  // 5 minutes
    static let idleThreshold: TimeInterval = 3 * 60  // 3 minutes - idle time to pause timer
    static let idleResetRatio: Double = 0.5  // Reset timer if idle for this ratio of breakInterval
    static let maxBlurRadius: Int32 = 64
}

// MARK: - Timer Settings

enum TimerSettings {
    static let breakIntervalMinutesRange: ClosedRange<Int> = 20...120
    static let breakIntervalMinutesStep = 5
    static let breakIntervalMinutesOptions: [Int] = Array(
        stride(
            from: breakIntervalMinutesRange.lowerBound,
            through: breakIntervalMinutesRange.upperBound,
            by: breakIntervalMinutesStep
        )
    )
    static let autoRestoreMinutesOptions: [Int] = [3, 5, 10, 15]
}

// MARK: - Hue Defaults

enum HueDefaults {
    static let breakHue: Double = 0.0
    static let breakSaturation: Double = 1.0
    static let breakBrightness: Double = 1.0
    static let breakColorTemperature: Double = 370.0  // mired (~2700K)
    static let colorTemperatureRange: ClosedRange<Double> = 153.0...500.0
    static let brightnessRange: ClosedRange<Double> = 0.01...1.0
    static let breakMode: HueBreakMode = .color
}

enum HueBreakMode: String, CaseIterable, Identifiable, Codable {
    case color
    case colorTemperature
    case brightness

    var id: String { rawValue }
}

// MARK: - Settings Keys

enum SettingsKeys {
    static let breakInterval = "breakInterval"
    static let hueEnabled = "hueEnabled"
    static let hueBridgeIP = "hueBridgeIP"
    static let hueUsername = "hueUsername"
    static let hueLightIDs = "hueLightIDs"
    static let hueBreakHue = "hueBreakHue"
    static let hueBreakSaturation = "hueBreakSaturation"
    static let hueBreakBrightness = "hueBreakBrightness"
    static let hueBreakColorTemperature = "hueBreakColorTemperature"
    static let hueBreakMode = "hueBreakMode"
    static let isEnabled = "isEnabled"
    static let useCompatibilityMode = "useCompatibilityMode"
    static let localNetworkPermissionRequested = "localNetworkPermissionRequested"
    static let hasShownWelcome = "hasShownWelcome"
    static let showTimerInMenuBar = "showTimerInMenuBar"
    static let deferBreakWhileMicrophoneInUse = "deferBreakWhileMicrophoneInUse"
}

// MARK: - App State

enum AppState: Equatable {
    case monitoring
    case breakTime
    case paused

    var isActive: Bool {
        switch self {
        case .monitoring, .breakTime: return true
        case .paused: return false
        }
    }
}

// MARK: - Hue Light State

struct HueLightState: Codable {
    var on: Bool
    var bri: Int?
    var hue: Int?
    var sat: Int?
    var xy: [Double]?
    var ct: Int?
    var colormode: String?
}

// MARK: - Hue Light

struct HueLight: Codable {
    let name: String
    let state: HueLightState
    let type: String?
    let capabilities: HueLightCapabilities?
}

struct HueLightCapabilities: Codable {
    let control: HueLightControlCapabilities?
}

struct HueLightControlCapabilities: Codable {
    let ct: HueLightColorTemperatureRange?
    let colorgamuttype: String?
}

struct HueLightColorTemperatureRange: Codable {
    let min: Int?
    let max: Int?
}

// MARK: - Hue Bridge Discovery Response

struct HueBridgeDiscovery: Codable {
    let id: String
    let internalipaddress: String
}

// MARK: - Hue API Response

struct HueAPIResponse: Codable {
    let success: [String: String]?
    let error: HueAPIError?
}

struct HueAPIError: Codable {
    let type: Int
    let address: String
    let description: String
}

// MARK: - Notification Names

extension Notification.Name {
    static let breakTimeStarted = Notification.Name("breakTimeStarted")
    static let breakTimeEnded = Notification.Name("breakTimeEnded")
    static let activityDetected = Notification.Name("activityDetected")
    static let settingsChanged = Notification.Name("settingsChanged")
}
