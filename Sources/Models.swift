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

// MARK: - Settings Keys

enum SettingsKeys {
    static let breakInterval = "breakInterval"
    static let hueEnabled = "hueEnabled"
    static let hueBridgeIP = "hueBridgeIP"
    static let hueUsername = "hueUsername"
    static let hueLightIDs = "hueLightIDs"
    static let isEnabled = "isEnabled"
    static let useCompatibilityMode = "useCompatibilityMode"
    static let localNetworkPermissionRequested = "localNetworkPermissionRequested"
    static let hasShownWelcome = "hasShownWelcome"
    static let showTimerInMenuBar = "showTimerInMenuBar"
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
