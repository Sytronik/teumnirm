import Foundation

// MARK: - Hue Controller

/// Controls Philips Hue lights via REST API
class HueController {

    // MARK: - Properties

    var bridgeIP: String?
    var username: String?
    var targetLightIDs: [String] = []
    var breakHue: Double = HueDefaults.breakHue
    var breakSaturation: Double = HueDefaults.breakSaturation
    var breakBrightness: Double = HueDefaults.breakBrightness
    var breakColorTemperature: Double = HueDefaults.breakColorTemperature
    var breakMode: HueBreakMode = HueDefaults.breakMode

    /// Stores original light states for restoration
    private var originalLightStates: [String: HueLightState] = [:]

    private let session: URLSession

    /// Whether the controller is configured and ready to use
    var isConfigured: Bool {
        return bridgeIP != nil && username != nil && !targetLightIDs.isEmpty
    }

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Bridge Discovery

    /// Discover Hue bridges on the local network using meethue.com discovery service
    func discoverBridges() async throws -> [HueBridgeDiscovery] {
        guard let url = URL(string: "https://discovery.meethue.com") else {
            throw HueError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw HueError.discoveryFailed
        }

        let bridges = try JSONDecoder().decode([HueBridgeDiscovery].self, from: data)
        return bridges
    }

    /// Discover bridge using mDNS/Bonjour (alternative method)
    func discoverBridgeLocal() async throws -> String {
        // Try the meethue.com discovery first
        let bridges = try await discoverBridges()

        guard let firstBridge = bridges.first else {
            throw HueError.noBridgeFound
        }

        return firstBridge.internalipaddress
    }

    // MARK: - User Registration

    /// Register a new user with the bridge (requires pressing the bridge button first)
    func registerUser(bridgeIP: String) async throws -> String {
        guard let url = URL(string: "http://\(bridgeIP)/api") else {
            throw HueError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "devicetype": "teumnirm#\(ProcessInfo.processInfo.hostName)"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        // Parse response
        if let responses = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let firstResponse = responses.first
        {
            if let success = firstResponse["success"] as? [String: Any],
                let username = success["username"] as? String
            {
                return username
            }

            if let error = firstResponse["error"] as? [String: Any],
                let description = error["description"] as? String
            {
                if description.contains("link button") {
                    throw HueError.linkButtonNotPressed
                }
                throw HueError.registrationFailed(description)
            }
        }

        throw HueError.registrationFailed("Unknown error")
    }

    // MARK: - Light Control

    /// Get all available lights from the bridge
    func getLights() async throws -> [String: HueLight] {
        guard let bridgeIP = bridgeIP, let username = username else {
            throw HueError.notConfigured
        }

        guard let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights") else {
            throw HueError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw HueError.requestFailed
        }

        let lights = try JSONDecoder().decode([String: HueLight].self, from: data)
        return lights
    }

    /// Get the current state of a specific light
    func getLightState(lightID: String) async throws -> HueLightState {
        guard let bridgeIP = bridgeIP, let username = username else {
            throw HueError.notConfigured
        }

        guard let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights/\(lightID)") else {
            throw HueError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let light = try JSONDecoder().decode(HueLight.self, from: data)
        return light.state
    }

    /// Set the state of a light
    func setLightState(lightID: String, state: [String: Any]) async throws {
        guard let bridgeIP = bridgeIP, let username = username else {
            throw HueError.notConfigured
        }

        guard let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights/\(lightID)/state")
        else {
            throw HueError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: state)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw HueError.requestFailed
        }
    }

    // MARK: - Break Time Actions

    /// Save current light states and set lights for break time
    func setLightsToBreakColor() async throws {
        guard isConfigured else {
            print("[HueController] Not configured, skipping")
            return
        }

        // Save current states
        originalLightStates.removeAll()

        let lights = try await getLights()

        for lightID in targetLightIDs {
            guard let light = lights[lightID] else {
                print("[HueController] Light \(lightID) not found")
                continue
            }

            originalLightStates[lightID] = light.state
            print("[HueController] Saved state for light \(lightID)")

            let breakState = makeBreakState(for: light)
            do {
                try await setLightState(lightID: lightID, state: breakState)
                print("[HueController] Set light \(lightID) for break time")
            } catch {
                print("[HueController] Failed to set light \(lightID) for break time: \(error)")
            }
        }
    }

    private func makeBreakState(for light: HueLight) -> [String: Any] {
        var state: [String: Any] = [
            "on": true,
            "transitiontime": 10,
        ]

        switch breakMode {
        case .color:
            if supportsColor(light) {
                state["hue"] = breakHueValue()
                state["sat"] = breakSaturationValue()
            } else if supportsColorTemperature(light) {
                state["ct"] = breakColorTemperatureValue(for: light)
            } else if supportsBrightness(light) {
                state["bri"] = breakBrightnessValue()
            }
        case .colorTemperature:
            if supportsColorTemperature(light) {
                state["ct"] = breakColorTemperatureValue(for: light)
            } else if supportsColor(light) {
                state["hue"] = breakHueValue()
                state["sat"] = breakSaturationValue()
            } else if supportsBrightness(light) {
                state["bri"] = breakBrightnessValue()
            }
        case .brightness:
            if supportsBrightness(light) {
                state["bri"] = breakBrightnessValue()
            }
        }

        return state
    }

    private func supportsColor(_ light: HueLight) -> Bool {
        if light.capabilities?.control?.colorgamuttype != nil {
            return true
        }

        guard let type = light.type?.lowercased() else { return false }
        if type.contains("color temperature") {
            return false
        }
        return type.contains("extended color") || type.contains("color light")
    }

    private func supportsColorTemperature(_ light: HueLight) -> Bool {
        if light.capabilities?.control?.ct != nil {
            return true
        }

        guard let type = light.type?.lowercased() else { return false }
        return type.contains("color temperature")
    }

    private func supportsBrightness(_ light: HueLight) -> Bool {
        light.state.bri != nil
    }

    private func breakHueValue() -> Int {
        let value = Int(round(breakHue * 65_535))
        return clamp(value, min: 0, max: 65_535)
    }

    private func breakSaturationValue() -> Int {
        let value = Int(round(breakSaturation * 254))
        return clamp(value, min: 0, max: 254)
    }

    private func breakBrightnessValue() -> Int {
        let value = Int(round(normalizedBreakBrightness(breakBrightness) * 254))
        return clamp(value, min: 1, max: 254)
    }

    private func breakColorTemperatureValue(for light: HueLight) -> Int {
        let defaultRange = HueDefaults.colorTemperatureRange
        let minCt = light.capabilities?.control?.ct?.min ?? Int(defaultRange.lowerBound)
        let maxCt = light.capabilities?.control?.ct?.max ?? Int(defaultRange.upperBound)
        let value = Int(round(breakColorTemperature))
        return clamp(value, min: minCt, max: maxCt)
    }

    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    /// Restore lights to their original state
    func restoreLights() async throws {
        guard isConfigured else {
            print("[HueController] Not configured, skipping")
            return
        }

        for lightID in targetLightIDs {
            guard let originalState = originalLightStates[lightID] else {
                print("[HueController] No saved state for light \(lightID)")
                continue
            }

            var state: [String: Any] = [
                "on": originalState.on,
                "transitiontime": 10,
            ]

            if let bri = originalState.bri {
                state["bri"] = bri
            }

            // Restore color based on color mode
            if let colormode = originalState.colormode {
                switch colormode {
                case "hs":
                    if let hue = originalState.hue { state["hue"] = hue }
                    if let sat = originalState.sat { state["sat"] = sat }
                case "xy":
                    if let xy = originalState.xy { state["xy"] = xy }
                case "ct":
                    if let ct = originalState.ct { state["ct"] = ct }
                default:
                    break
                }
            }

            do {
                try await setLightState(lightID: lightID, state: state)
                print("[HueController] Restored light \(lightID)")
            } catch {
                print("[HueController] Failed to restore light \(lightID): \(error)")
            }
        }

        originalLightStates.removeAll()
    }

    // MARK: - Configuration

    func configure(bridgeIP: String, username: String, lightIDs: [String]) {
        self.bridgeIP = bridgeIP
        self.username = username
        self.targetLightIDs = lightIDs
    }

    func loadFromDefaults() {
        let defaults = UserDefaults.standard
        bridgeIP = defaults.string(forKey: SettingsKeys.hueBridgeIP)
        username = defaults.string(forKey: SettingsKeys.hueUsername)
        targetLightIDs = defaults.stringArray(forKey: SettingsKeys.hueLightIDs) ?? []
        breakHue = defaults.object(forKey: SettingsKeys.hueBreakHue) == nil
            ? HueDefaults.breakHue
            : defaults.double(forKey: SettingsKeys.hueBreakHue)
        breakSaturation = defaults.object(forKey: SettingsKeys.hueBreakSaturation) == nil
            ? HueDefaults.breakSaturation
            : defaults.double(forKey: SettingsKeys.hueBreakSaturation)
        let storedBrightness = defaults.object(forKey: SettingsKeys.hueBreakBrightness) == nil
            ? HueDefaults.breakBrightness
            : defaults.double(forKey: SettingsKeys.hueBreakBrightness)
        breakBrightness = normalizedBreakBrightness(storedBrightness)
        breakColorTemperature = defaults.object(forKey: SettingsKeys.hueBreakColorTemperature) == nil
            ? HueDefaults.breakColorTemperature
            : defaults.double(forKey: SettingsKeys.hueBreakColorTemperature)
        if let storedMode = defaults.string(forKey: SettingsKeys.hueBreakMode),
           let mode = HueBreakMode(rawValue: storedMode) {
            breakMode = mode
        } else {
            breakMode = HueDefaults.breakMode
        }
    }

    /// Trigger local network permission dialog by attempting to access a local IP
    /// This is necessary because macOS requires explicit permission for local network access
    func triggerLocalNetworkPermission() async {
        // Try to access a common local network gateway to trigger the permission dialog
        // This will prompt the user to allow local network access if not already granted
        let testIPs = ["192.168.0.1", "192.168.1.1", "10.0.0.1"]

        for ip in testIPs {
            guard let url = URL(string: "http://\(ip)/") else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 2  // Short timeout since we just need to trigger the dialog

            do {
                _ = try await session.data(for: request)
            } catch {
                // Error is expected - we just need to trigger the permission dialog
            }

            // Only need one attempt to trigger the dialog
            break
        }
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(bridgeIP, forKey: SettingsKeys.hueBridgeIP)
        defaults.set(username, forKey: SettingsKeys.hueUsername)
        defaults.set(targetLightIDs, forKey: SettingsKeys.hueLightIDs)
        defaults.set(breakHue, forKey: SettingsKeys.hueBreakHue)
        defaults.set(breakSaturation, forKey: SettingsKeys.hueBreakSaturation)
        defaults.set(normalizedBreakBrightness(breakBrightness), forKey: SettingsKeys.hueBreakBrightness)
        defaults.set(breakColorTemperature, forKey: SettingsKeys.hueBreakColorTemperature)
        defaults.set(breakMode.rawValue, forKey: SettingsKeys.hueBreakMode)
    }

    private func normalizedBreakBrightness(_ value: Double) -> Double {
        let normalized: Double
        if value > HueDefaults.brightnessRange.upperBound {
            normalized = value / 254.0
        } else {
            normalized = value
        }

        return min(
            max(normalized, HueDefaults.brightnessRange.lowerBound),
            HueDefaults.brightnessRange.upperBound
        )
    }

    /// Test connection to the bridge
    func testConnection() async -> Bool {
        do {
            let lights = try await getLights()
            return !lights.isEmpty
        } catch {
            print("[HueController] Connection test failed: \(error)")
            return false
        }
    }
}

// MARK: - Hue Error

enum HueError: Error, LocalizedError {
    case invalidURL
    case discoveryFailed
    case noBridgeFound
    case linkButtonNotPressed
    case registrationFailed(String)
    case notConfigured
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .discoveryFailed:
            return "Failed to discover Hue bridges"
        case .noBridgeFound:
            return "No Hue bridge found on the network"
        case .linkButtonNotPressed:
            return "Press the link button on your Hue bridge and try again"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .notConfigured:
            return "Hue controller is not configured"
        case .requestFailed:
            return "Request to Hue bridge failed"
        }
    }
}
