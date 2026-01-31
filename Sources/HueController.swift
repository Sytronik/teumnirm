import Foundation

// MARK: - Hue Controller

/// Controls Philips Hue lights via REST API
class HueController {

    // MARK: - Properties

    var bridgeIP: String?
    var username: String?
    var targetLightIDs: [String] = []

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

    /// Save current light states and set lights to red for break time
    func setLightsToRed() async throws {
        guard isConfigured else {
            print("[HueController] Not configured, skipping")
            return
        }

        // Save current states
        originalLightStates.removeAll()

        for lightID in targetLightIDs {
            do {
                let state = try await getLightState(lightID: lightID)
                originalLightStates[lightID] = state
                print("[HueController] Saved state for light \(lightID)")
            } catch {
                print("[HueController] Failed to save state for light \(lightID): \(error)")
            }
        }

        // Set to red
        // Hue value 0 = red, sat 254 = full saturation, bri 254 = full brightness
        let redState: [String: Any] = [
            "on": true,
            "hue": 0,  // Red
            "sat": 254,  // Full saturation
            "bri": 254,  // Full brightness
            "transitiontime": 10,  // 1 second transition
        ]

        for lightID in targetLightIDs {
            do {
                try await setLightState(lightID: lightID, state: redState)
                print("[HueController] Set light \(lightID) to red")
            } catch {
                print("[HueController] Failed to set light \(lightID) to red: \(error)")
            }
        }
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
