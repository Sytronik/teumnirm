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
        window.setContentSize(NSSize(width: 450, height: 650))
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
        .frame(minWidth: 400, minHeight: 500)
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
                        ForEach(TimerSettings.breakIntervalMinutesOptions, id: \.self) {
                            minutes in
                            Text(L.Settings.minutes(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text(L.Settings.autoRestoreTime)
                    Spacer()
                    Picker("", selection: $viewModel.autoRestoreMinutes) {
                        ForEach(TimerSettings.autoRestoreMinutesOptions, id: \.self) { minutes in
                            Text(L.Settings.minutes(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                Toggle(
                    L.Settings.deferBreakWhileMicrophoneInUse,
                    isOn: $viewModel.deferBreakWhileMicrophoneInUse
                )
            } header: {
                Text(L.Settings.timerSettings)
            }

            Section {
                Toggle(L.Settings.showTimerInMenuBar, isOn: $viewModel.showTimerInMenuBar)
            } header: {
                Text(L.Settings.menuBar)
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
    @State private var loadLightsErrorMessage: String?
    @State private var showLinkButtonAlert = false
    @State private var showLocalNetworkPermissionAlert = false
    @State private var isRequestingPermission = false
    @State private var pendingHueEnable = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    L.Hue.enableIntegration,
                    isOn: Binding(
                        get: { viewModel.hueEnabled },
                        set: { newValue in
                            if newValue && !viewModel.hueEnabled {
                                // Check if permission was already requested
                                let permissionAlreadyRequested = UserDefaults.standard.bool(
                                    forKey: SettingsKeys.localNetworkPermissionRequested)
                                if permissionAlreadyRequested {
                                    // Permission was already requested, just enable
                                    viewModel.hueEnabled = true
                                } else {
                                    // Show permission alert when enabling Hue for the first time
                                    pendingHueEnable = true
                                    showLocalNetworkPermissionAlert = true
                                }
                            } else {
                                viewModel.hueEnabled = newValue
                            }
                        }
                    ))

                if isRequestingPermission {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L.Hue.requestingPermission)
                            .foregroundColor(.secondary)
                    }
                }
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
                                loadLightsErrorMessage = nil
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

                        if let loadLightsErrorMessage {
                            Text(loadLightsErrorMessage)
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text(L.Hue.lightsToControl)
                    }
                }

                Section {
                    TabView(selection: $viewModel.breakMode) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(L.Hue.breakColor)
                                Spacer()
                                ColorWell(
                                    color: Binding(
                                        get: { viewModel.breakColor },
                                        set: { newColor in
                                            viewModel.setBreakColor(from: newColor)
                                        }
                                    )
                                )
                                .frame(width: 44, height: 24)
                            }
                        }
                        .padding(.horizontal, 8)
                        .tag(HueBreakMode.color)
                        .tabItem { Text(L.Hue.breakModeColor) }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(L.Hue.colorTemperature)
                                Spacer()
                                Text(L.Hue.kelvin(viewModel.breakColorTemperatureKelvin))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            GradientSlider(
                                value: Binding(
                                    get: {
                                        HueDefaults.colorTemperatureRange.upperBound
                                            + HueDefaults.colorTemperatureRange.lowerBound
                                            - viewModel.breakColorTemperature
                                    },
                                    set: { newValue in
                                        viewModel.breakColorTemperature =
                                            HueDefaults.colorTemperatureRange.upperBound
                                            + HueDefaults.colorTemperatureRange.lowerBound
                                            - newValue
                                    }
                                ),
                                range: HueDefaults.colorTemperatureRange,
                                step: 1,
                                gradient: LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.6, blue: 0.2),
                                        Color(red: 0.6, green: 0.8, blue: 1.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .padding(.horizontal, 8)
                        .tag(HueBreakMode.colorTemperature)
                        .tabItem { Text(L.Hue.breakModeTemperature) }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(L.Hue.brightness)
                                Spacer()
                                Text(L.Hue.brightnessPercent(viewModel.breakBrightnessPercent))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            GradientSlider(
                                value: $viewModel.breakBrightness,
                                range: HueDefaults.brightnessRange,
                                step: 0.01,
                                gradient: LinearGradient(
                                    colors: [.black, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .padding(.horizontal, 8)
                        .tag(HueBreakMode.brightness)
                        .tabItem { Text(L.Hue.breakModeBrightness) }
                    }
                    .frame(height: 100)
                } header: {
                    Text(L.Hue.breakLightSettings)
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
        .alert(L.Hue.localNetworkPermissionTitle, isPresented: $showLocalNetworkPermissionAlert) {
            Button(L.Hue.cancel, role: .cancel) {
                pendingHueEnable = false
            }
            Button(L.Hue.ok) {
                requestLocalNetworkPermission()
            }
        } message: {
            Text(L.Hue.localNetworkPermissionMessage)
        }
    }

    private func requestLocalNetworkPermission() {
        guard pendingHueEnable else { return }

        isRequestingPermission = true

        Task {
            await viewModel.appDelegate?.hueController.triggerLocalNetworkPermission()

            await MainActor.run {
                // Mark that permission has been requested
                UserDefaults.standard.set(
                    true, forKey: SettingsKeys.localNetworkPermissionRequested)

                isRequestingPermission = false
                viewModel.hueEnabled = true
                pendingHueEnable = false
            }
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

        loadLightsErrorMessage = nil
        appDelegate.hueController.bridgeIP = viewModel.hueBridgeIP
        appDelegate.hueController.username = viewModel.hueUsername

        Task {
            do {
                let lights = try await appDelegate.hueController.getLights()
                await MainActor.run {
                    viewModel.availableLights = lights
                    loadLightsErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    loadLightsErrorMessage = L.Hue.couldNotLoadLights(error.localizedDescription)
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

    @Published var deferBreakWhileMicrophoneInUse: Bool {
        didSet {
            appDelegate?.deferBreakWhileMicrophoneInUse = deferBreakWhileMicrophoneInUse
            saveSettings()
        }
    }

    @Published var useCompatibilityMode: Bool {
        didSet {
            appDelegate?.blurOverlayManager.setCompatibilityMode(useCompatibilityMode)
            saveSettings()
        }
    }

    @Published var showTimerInMenuBar: Bool {
        didSet {
            appDelegate?.showTimerInMenuBar = showTimerInMenuBar
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

    @Published var breakMode: HueBreakMode {
        didSet {
            applyBreakSettings()
        }
    }

    @Published var breakHue: Double {
        didSet {
            if !isUpdatingBreakColor {
                applyBreakSettings()
            }
        }
    }

    @Published var breakSaturation: Double {
        didSet {
            if !isUpdatingBreakColor {
                applyBreakSettings()
            }
        }
    }

    @Published var breakBrightness: Double {
        didSet {
            let normalized = Self.normalizedBreakBrightness(breakBrightness)
            if normalized != breakBrightness {
                breakBrightness = normalized
                return
            }
            if !isUpdatingBreakColor {
                applyBreakSettings()
            }
        }
    }

    @Published var breakColorTemperature: Double {
        didSet {
            applyBreakSettings()
        }
    }

    @Published var availableLights: [String: HueLight] = [:]

    // Properties used for status updates
    @Published var statusText: String = L.Settings.statusUnknown
    @Published var remainingTimeText: String?

    private var updateTimer: Timer?
    private var isUpdatingBreakColor = false

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let defaults = UserDefaults.standard
        self.breakIntervalMinutes = Int(appDelegate.breakInterval / 60)
        self.autoRestoreMinutes = Int(appDelegate.autoRestoreInterval / 60)
        self.deferBreakWhileMicrophoneInUse = appDelegate.deferBreakWhileMicrophoneInUse
        self.useCompatibilityMode = defaults.bool(forKey: SettingsKeys.useCompatibilityMode)
        self.showTimerInMenuBar = defaults.bool(forKey: SettingsKeys.showTimerInMenuBar)
        self.hueEnabled = defaults.bool(forKey: SettingsKeys.hueEnabled)
        self.hueBridgeIP = defaults.string(forKey: SettingsKeys.hueBridgeIP) ?? ""
        self.hueUsername = defaults.string(forKey: SettingsKeys.hueUsername) ?? ""
        self.selectedLightIDs = Set(defaults.stringArray(forKey: SettingsKeys.hueLightIDs) ?? [])
        if let storedMode = defaults.string(forKey: SettingsKeys.hueBreakMode),
            let mode = HueBreakMode(rawValue: storedMode)
        {
            self.breakMode = mode
        } else {
            self.breakMode = HueDefaults.breakMode
        }
        self.breakHue =
            defaults.object(forKey: SettingsKeys.hueBreakHue) == nil
            ? HueDefaults.breakHue
            : defaults.double(forKey: SettingsKeys.hueBreakHue)
        self.breakSaturation =
            defaults.object(forKey: SettingsKeys.hueBreakSaturation) == nil
            ? HueDefaults.breakSaturation
            : defaults.double(forKey: SettingsKeys.hueBreakSaturation)
        let storedBrightness =
            defaults.object(forKey: SettingsKeys.hueBreakBrightness) == nil
            ? HueDefaults.breakBrightness
            : defaults.double(forKey: SettingsKeys.hueBreakBrightness)
        self.breakBrightness = Self.normalizedBreakBrightness(storedBrightness)
        self.breakColorTemperature =
            defaults.object(forKey: SettingsKeys.hueBreakColorTemperature) == nil
            ? HueDefaults.breakColorTemperature
            : defaults.double(forKey: SettingsKeys.hueBreakColorTemperature)

        // Initial status update
        updateStatus()

        // Start timer (update status every second)
        startUpdateTimer()
    }

    deinit {
        updateTimer?.invalidate()
    }

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        // Add to .common mode so the timer runs during UI interaction
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

        // Update status text
        switch appDelegate.state {
        case .monitoring:
            statusText =
                appDelegate.isBreakDeferredForMicrophone
                ? L.Settings.statusPendingForMicrophone : L.Settings.statusMonitoring
        case .breakTime:
            statusText = L.Settings.statusBreakTime
        case .paused:
            statusText = L.Settings.statusPaused
        }

        // Update remaining time (reflect pause during idle)
        if appDelegate.state == .monitoring,
            !appDelegate.isBreakDeferredForMicrophone,
            let remaining = appDelegate.remainingBreakTime()
        {

            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            remainingTimeText = String(format: "%d:%02d", minutes, seconds)
        } else {
            remainingTimeText = nil
        }
    }

    var breakColor: NSColor {
        NSColor(
            calibratedHue: breakHue,
            saturation: breakSaturation,
            brightness: Self.normalizedBreakBrightness(breakBrightness),
            alpha: 1.0
        )
    }

    var breakColorTemperatureKelvin: Int {
        let clamped = max(breakColorTemperature, 1)
        return Int(1_000_000 / clamped)
    }

    var breakBrightnessPercent: Int {
        Int(round(Self.normalizedBreakBrightness(breakBrightness) * 100))
    }

    func setBreakColor(from color: NSColor) {
        guard let components = color.hueSaturationBrightness else { return }
        let clampedHue = min(max(components.hue, 0), 1)
        let clampedSaturation = min(max(components.saturation, 0), 1)
        let clampedBrightness = Self.normalizedBreakBrightness(components.brightness)
        isUpdatingBreakColor = true
        breakHue = clampedHue
        breakSaturation = clampedSaturation
        breakBrightness = clampedBrightness
        isUpdatingBreakColor = false
        applyBreakSettings()
    }

    private func applyBreakSettings() {
        appDelegate?.hueController.breakHue = breakHue
        appDelegate?.hueController.breakSaturation = breakSaturation
        appDelegate?.hueController.breakBrightness = Self.normalizedBreakBrightness(breakBrightness)
        appDelegate?.hueController.breakColorTemperature = breakColorTemperature
        appDelegate?.hueController.breakMode = breakMode
        saveSettings()
    }

    private static func normalizedBreakBrightness(_ value: Double) -> Double {
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

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(breakIntervalMinutes * 60, forKey: SettingsKeys.breakInterval)
        defaults.set(
            deferBreakWhileMicrophoneInUse,
            forKey: SettingsKeys.deferBreakWhileMicrophoneInUse
        )
        defaults.set(useCompatibilityMode, forKey: SettingsKeys.useCompatibilityMode)
        defaults.set(showTimerInMenuBar, forKey: SettingsKeys.showTimerInMenuBar)
        defaults.set(hueEnabled, forKey: SettingsKeys.hueEnabled)
        defaults.set(hueBridgeIP, forKey: SettingsKeys.hueBridgeIP)
        defaults.set(hueUsername, forKey: SettingsKeys.hueUsername)
        defaults.set(Array(selectedLightIDs), forKey: SettingsKeys.hueLightIDs)
        defaults.set(breakMode.rawValue, forKey: SettingsKeys.hueBreakMode)
        defaults.set(breakHue, forKey: SettingsKeys.hueBreakHue)
        defaults.set(breakSaturation, forKey: SettingsKeys.hueBreakSaturation)
        defaults.set(breakBrightness, forKey: SettingsKeys.hueBreakBrightness)
        defaults.set(breakColorTemperature, forKey: SettingsKeys.hueBreakColorTemperature)
    }
}

// MARK: - Color Well

struct ColorWell: NSViewRepresentable {
    @Binding var color: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.color = color
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorDidChange(_:))
        return colorWell
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if nsView.color != color {
            nsView.color = color
        }
    }

    class Coordinator: NSObject {
        private var color: Binding<NSColor>

        init(color: Binding<NSColor>) {
            self.color = color
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            color.wrappedValue = sender.color
        }
    }
}

// MARK: - Gradient Slider

struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: LinearGradient

    private let trackHeight: CGFloat = 8
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let availableWidth = max(1, width - thumbSize)
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let progress = (clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let xOffset = CGFloat(progress) * availableWidth

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(gradient)
                    .frame(height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: xOffset)
                    .shadow(radius: 1)
            }
            .frame(height: max(trackHeight, thumbSize))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let location = min(
                            max(0, gesture.location.x - thumbSize / 2), availableWidth)
                        let ratio = Double(location / availableWidth)
                        var newValue =
                            range.lowerBound
                            + ratio * (range.upperBound - range.lowerBound)
                        newValue = (newValue / step).rounded() * step
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - NSColor Helpers

extension NSColor {
    fileprivate struct HueSaturationBrightness {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    fileprivate var hueSaturationBrightness: HueSaturationBrightness? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return HueSaturationBrightness(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness)
        )
    }
}
