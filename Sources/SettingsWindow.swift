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
        window.title = "Teumnirm 설정"
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
                    Label("일반", systemImage: "gearshape")
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
                    Text("휴식 알림 간격")
                    Spacer()
                    Picker("", selection: $viewModel.breakIntervalMinutes) {
                        Text("30분").tag(30)
                        Text("45분").tag(45)
                        Text("60분").tag(60)
                        Text("90분").tag(90)
                        Text("120분").tag(120)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text("자동 해제 시간")
                    Spacer()
                    Picker("", selection: $viewModel.autoRestoreMinutes) {
                        Text("3분").tag(3)
                        Text("5분").tag(5)
                        Text("10분").tag(10)
                        Text("15분").tag(15)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            } header: {
                Text("타이머 설정")
            }

            Section {
                Toggle("호환 모드 사용 (블러가 안 보이면 활성화)", isOn: $viewModel.useCompatibilityMode)
            } header: {
                Text("화면 블러")
            }

            Section {
                HStack {
                    Text("현재 상태")
                    Spacer()
                    Text(viewModel.statusText)
                        .foregroundColor(.secondary)
                }

                if viewModel.remainingTimeText != nil {
                    HStack {
                        Text("다음 휴식까지")
                        Spacer()
                        Text(viewModel.remainingTimeText ?? "")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("상태")
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
                Toggle("Philips Hue 연동 사용", isOn: $viewModel.hueEnabled)
            }

            if viewModel.hueEnabled {
                Section {
                    HStack {
                        TextField("브릿지 IP 주소", text: $viewModel.hueBridgeIP)
                            .textFieldStyle(.roundedBorder)

                        Button("자동 검색") {
                            discoverBridge()
                        }
                        .disabled(isDiscovering)
                    }

                    if isDiscovering {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("브릿지 검색 중...")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("브릿지 연결")
                }

                Section {
                    if viewModel.hueUsername.isEmpty {
                        Button("브릿지 연결하기") {
                            showLinkButtonAlert = true
                        }
                        .disabled(viewModel.hueBridgeIP.isEmpty || isRegistering)

                        if isRegistering {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("연결 중...")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("연결됨")
                            Spacer()
                            Button("연결 해제") {
                                viewModel.hueUsername = ""
                                viewModel.selectedLightIDs.removeAll()
                            }
                            .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("인증")
                }

                if !viewModel.hueUsername.isEmpty {
                    Section {
                        if viewModel.availableLights.isEmpty {
                            Button("조명 목록 불러오기") {
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
                        Text("제어할 조명")
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
        .alert("브릿지 버튼을 눌러주세요", isPresented: $showLinkButtonAlert) {
            Button("취소", role: .cancel) {}
            Button("연결") {
                registerUser()
            }
        } message: {
            Text("Philips Hue 브릿지의 큰 버튼을 누른 후 '연결'을 클릭하세요.")
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
                    errorMessage = "브릿지를 찾을 수 없습니다: \(error.localizedDescription)"
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
                    errorMessage = "브릿지 버튼을 먼저 눌러주세요"
                    isRegistering = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "연결 실패: \(error.localizedDescription)"
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
                    errorMessage = "조명 목록을 불러올 수 없습니다: \(error.localizedDescription)"
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

    var statusText: String {
        guard let appDelegate = appDelegate else { return "알 수 없음" }
        switch appDelegate.state {
        case .monitoring:
            return "모니터링 중"
        case .breakTime:
            return "휴식 시간"
        case .paused:
            return "일시정지"
        }
    }

    var remainingTimeText: String? {
        guard let appDelegate = appDelegate,
            appDelegate.state == .monitoring,
            let lastActivity = appDelegate.lastActivityTime
        else { return nil }

        let elapsed = Date().timeIntervalSince(lastActivity)
        let remaining = max(0, appDelegate.breakInterval - elapsed)

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

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
