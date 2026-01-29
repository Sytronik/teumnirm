import AppKit
import SwiftUI

// MARK: - Settings Window Controller

class SettingsWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?

    weak var appDelegate: AppDelegate?

    func showSettings(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appDelegate: appDelegate)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = L.Settings.windowTitle
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 500))
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        self.hostingController = hostingController

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettings() {
        window?.close()
        window = nil
        hostingController = nil
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    init(appDelegate: AppDelegate) {
        self.viewModel = SettingsViewModel(appDelegate: appDelegate)
    }

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(L.Settings.tabGeneral, systemImage: "gearshape")
                }

            HueSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Philips Hue", systemImage: "lightbulb")
                }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L.Settings.breakInterval)
                    Spacer()
                    Picker("", selection: $viewModel.breakIntervalMinutes) {
                        Text(L.Settings.minutes(30)).tag(30)
                        Text(L.Settings.minutes(45)).tag(45)
                        Text(L.Settings.minutes(60)).tag(60)
                        Text(L.Settings.minutes(90)).tag(90)
                        Text(L.Settings.minutes(120)).tag(120)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text(L.Settings.autoRestoreTime)
                    Spacer()
                    Picker("", selection: $viewModel.autoRestoreMinutes) {
                        Text(L.Settings.minutes(3)).tag(3)
                        Text(L.Settings.minutes(5)).tag(5)
                        Text(L.Settings.minutes(10)).tag(10)
                        Text(L.Settings.minutes(15)).tag(15)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            } header: {
                Text(L.Settings.timerSettings)
            }

            Section {
                Toggle(L.Settings.useCompatibilityMode, isOn: $viewModel.useCompatibilityMode)
            } header: {
                Text(L.Settings.screenBlur)
            }

            Section {
                HStack {
                    Text(L.Settings.currentStatus)
                    Spacer()
                    Text(viewModel.statusText)
                        .foregroundColor(.secondary)
                }

                if viewModel.remainingTimeText != nil {
                    HStack {
                        Text(L.Settings.nextBreakIn)
                        Spacer()
                        Text(viewModel.remainingTimeText ?? "")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text(L.Settings.status)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hue Settings View

struct HueSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isDiscovering = false
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @State private var showLinkButtonAlert = false

    var body: some View {
        Form {
            Section {
                Toggle(L.Hue.enableIntegration, isOn: $viewModel.hueEnabled)
            }

            if viewModel.hueEnabled {
                Section {
                    HStack {
                        TextField(L.Hue.bridgeIP, text: $viewModel.hueBridgeIP)
                            .textFieldStyle(.roundedBorder)

                        Button(L.Hue.autoDiscover) {
                            discoverBridge()
                        }
                        .disabled(isDiscovering)
                    }

                    if isDiscovering {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(L.Hue.searchingBridge)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L.Hue.bridgeConnection)
                }

                Section {
                    if viewModel.hueUsername.isEmpty {
                        Button(L.Hue.connectToBridge) {
                            showLinkButtonAlert = true
                        }
                        .disabled(viewModel.hueBridgeIP.isEmpty || isRegistering)

                        if isRegistering {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(L.Hue.connecting)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(L.Hue.connected)
                            Spacer()
                            Button(L.Hue.disconnect) {
                                viewModel.hueUsername = ""
                                viewModel.selectedLightIDs.removeAll()
                            }
                            .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text(L.Hue.authentication)
                }

                if !viewModel.hueUsername.isEmpty {
                    Section {
                        if viewModel.availableLights.isEmpty {
                            Button(L.Hue.loadLights) {
                                loadLights()
                            }
                        } else {
                            ForEach(
                                viewModel.availableLights.sorted(by: { $0.key < $1.key }), id: \.key
                            ) { lightID, light in
                                Toggle(
                                    light.name,
                                    isOn: Binding(
                                        get: { viewModel.selectedLightIDs.contains(lightID) },
                                        set: { isSelected in
                                            if isSelected {
                                                viewModel.selectedLightIDs.insert(lightID)
                                            } else {
                                                viewModel.selectedLightIDs.remove(lightID)
                                            }
                                        }
                                    ))
                            }
                        }
                    } header: {
                        Text(L.Hue.lightsToControl)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert(L.Hue.pressBridgeButton, isPresented: $showLinkButtonAlert) {
            Button(L.Hue.cancel, role: .cancel) {}
            Button(L.Hue.connect) {
                registerUser()
            }
        } message: {
            Text(L.Hue.pressBridgeButtonMessage)
        }
    }

    private func discoverBridge() {
        isDiscovering = true
        errorMessage = nil

        Task {
            do {
                let ip = try await viewModel.appDelegate?.hueController.discoverBridgeLocal()
                await MainActor.run {
                    viewModel.hueBridgeIP = ip ?? ""
                    isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = L.Hue.couldNotFindBridge(error.localizedDescription)
                    isDiscovering = false
                }
            }
        }
    }

    private func registerUser() {
        guard !viewModel.hueBridgeIP.isEmpty else { return }

        isRegistering = true
        errorMessage = nil

        Task {
            do {
                let username = try await viewModel.appDelegate?.hueController.registerUser(
                    bridgeIP: viewModel.hueBridgeIP)
                await MainActor.run {
                    viewModel.hueUsername = username ?? ""
                    isRegistering = false
                    loadLights()
                }
            } catch HueError.linkButtonNotPressed {
                await MainActor.run {
                    errorMessage = L.Hue.pressButtonFirst
                    isRegistering = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = L.Hue.connectionFailed(error.localizedDescription)
                    isRegistering = false
                }
            }
        }
    }

    private func loadLights() {
        guard let appDelegate = viewModel.appDelegate else { return }

        appDelegate.hueController.bridgeIP = viewModel.hueBridgeIP
        appDelegate.hueController.username = viewModel.hueUsername

        Task {
            do {
                let lights = try await appDelegate.hueController.getLights()
                await MainActor.run {
                    viewModel.availableLights = lights
                }
            } catch {
                await MainActor.run {
                    errorMessage = L.Hue.couldNotLoadLights(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Settings View Model

class SettingsViewModel: ObservableObject {
    weak var appDelegate: AppDelegate?

    @Published var breakIntervalMinutes: Int {
        didSet {
            appDelegate?.breakInterval = TimeInterval(breakIntervalMinutes * 60)
            saveSettings()
        }
    }

    @Published var autoRestoreMinutes: Int {
        didSet {
            appDelegate?.autoRestoreInterval = TimeInterval(autoRestoreMinutes * 60)
            saveSettings()
        }
    }

    @Published var useCompatibilityMode: Bool {
        didSet {
            appDelegate?.blurOverlayManager.setCompatibilityMode(useCompatibilityMode)
            saveSettings()
        }
    }

    @Published var hueEnabled: Bool {
        didSet {
            appDelegate?.hueEnabled = hueEnabled
            saveSettings()
        }
    }

    @Published var hueBridgeIP: String {
        didSet {
            appDelegate?.hueController.bridgeIP = hueBridgeIP
            saveSettings()
        }
    }

    @Published var hueUsername: String {
        didSet {
            appDelegate?.hueController.username = hueUsername
            saveSettings()
        }
    }

    @Published var selectedLightIDs: Set<String> {
        didSet {
            appDelegate?.hueController.targetLightIDs = Array(selectedLightIDs)
            saveSettings()
        }
    }

    @Published var availableLights: [String: HueLight] = [:]

    // 상태 업데이트용 프로퍼티
    @Published var statusText: String = L.Settings.statusUnknown
    @Published var remainingTimeText: String?

    private var updateTimer: Timer?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let defaults = UserDefaults.standard
        self.breakIntervalMinutes = Int(appDelegate.breakInterval / 60)
        self.autoRestoreMinutes = Int(appDelegate.autoRestoreInterval / 60)
        self.useCompatibilityMode = defaults.bool(forKey: SettingsKeys.useCompatibilityMode)
        self.hueEnabled = defaults.bool(forKey: SettingsKeys.hueEnabled)
        self.hueBridgeIP = defaults.string(forKey: SettingsKeys.hueBridgeIP) ?? ""
        self.hueUsername = defaults.string(forKey: SettingsKeys.hueUsername) ?? ""
        self.selectedLightIDs = Set(defaults.stringArray(forKey: SettingsKeys.hueLightIDs) ?? [])

        // 초기 상태 업데이트
        updateStatus()

        // 타이머 시작 (1초마다 상태 업데이트)
        startUpdateTimer()
    }

    deinit {
        updateTimer?.invalidate()
    }

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        // .common 모드에 추가하여 UI 상호작용 중에도 타이머가 동작하도록 함
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateStatus() {
        guard let appDelegate = appDelegate else {
            statusText = L.Settings.statusUnknown
            remainingTimeText = nil
            return
        }

        // 상태 텍스트 업데이트
        switch appDelegate.state {
        case .monitoring:
            statusText = L.Settings.statusMonitoring
        case .breakTime:
            statusText = L.Settings.statusBreakTime
        case .paused:
            statusText = L.Settings.statusPaused
        }

        // 남은 시간 업데이트 (usageStartTime 기준)
        if appDelegate.state == .monitoring,
            let usageStart = appDelegate.usageStartTime
        {
            let elapsed = Date().timeIntervalSince(usageStart)
            let remaining = max(0, appDelegate.breakInterval - elapsed)

            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            remainingTimeText = String(format: "%d:%02d", minutes, seconds)
        } else {
            remainingTimeText = nil
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(breakIntervalMinutes * 60, forKey: SettingsKeys.breakInterval)
        defaults.set(useCompatibilityMode, forKey: SettingsKeys.useCompatibilityMode)
        defaults.set(hueEnabled, forKey: SettingsKeys.hueEnabled)
        defaults.set(hueBridgeIP, forKey: SettingsKeys.hueBridgeIP)
        defaults.set(hueUsername, forKey: SettingsKeys.hueUsername)
        defaults.set(Array(selectedLightIDs), forKey: SettingsKeys.hueLightIDs)
    }
}
