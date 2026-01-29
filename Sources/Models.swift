import AppKit
import Foundation

// MARK: - App Constants

enum AppConstants {
    static let appName = "Teumnirm"
    static let appNameKorean = "틈니름"
    static let defaultBreakInterval: TimeInterval = 60 * 60  // 1시간
    static let autoRestoreInterval: TimeInterval = 5 * 60  // 5분
    static let idleThreshold: TimeInterval = 3 * 60  // 3분 - 이 시간 이상 비활동 시 휴식으로 간주
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
