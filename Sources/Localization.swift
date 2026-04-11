import Foundation

// MARK: - Localization

/// Determines if the system language is Korean
let isKorean: Bool = {
    guard let language = Locale.preferredLanguages.first else { return false }
    return language.hasPrefix("ko")
}()

/// Localized strings for the app
enum L {
    // MARK: - Menu Bar

    enum Menu {
        static var statusStarting: String {
            isKorean ? "상태: 시작 중..." : "Status: Starting..."
        }

        static var monitoring: String {
            isKorean ? "모니터링" : "Monitoring"
        }

        static var resetTimer: String {
            isKorean ? "타이머 초기화" : "Reset Timer"
        }

        static var endBreak: String {
            isKorean ? "휴식 완료" : "End Break"
        }

        static var settings: String {
            isKorean ? "설정..." : "Settings..."
        }

        static var usageHistory: String {
            isKorean ? "사용 기록..." : "Usage History..."
        }

        static var quit: String {
            isKorean ? "종료" : "Quit"
        }

        static var statusMonitoring: String {
            isKorean ? "상태: 모니터링 중" : "Status: Monitoring"
        }

        static var statusPendingForMicrophone: String {
            isKorean ? "상태: 마이크 사용 종료 대기 중" : "Status: Waiting for microphone to be released"
        }

        static var statusBreakTime: String {
            isKorean ? "상태: 휴식 시간" : "Status: Break Time"
        }

        static var statusPaused: String {
            isKorean ? "상태: 일시정지" : "Status: Paused"
        }

        static func nextBreakIn(minutes: Int, seconds: Int) -> String {
            if isKorean {
                return String(format: "다음 휴식까지: %d:%02d", minutes, seconds)
            } else {
                return String(format: "Next break in: %d:%02d", minutes, seconds)
            }
        }

        static var breakPendingForMicrophone: String {
            isKorean ? "마이크 사용 중이라 휴식 알림 대기 중" : "Break is waiting while microphone is in use"
        }
    }

    // MARK: - Confirm Window

    enum ConfirmWindow {
        static var title: String {
            isKorean ? "휴식 시간입니다! 🧘" : "Break Time! 🧘"
        }

        static var subtitle: String {
            isKorean ? "잠시 쉬거나 자세를 바꿔보세요" : "Take a rest or stretch"
        }

        static func autoDismissIn(minutes: Int, seconds: Int) -> String {
            if isKorean {
                return String(format: "%d:%02d 후 자동 해제", minutes, seconds)
            } else {
                return String(format: "Auto-dismiss in %d:%02d", minutes, seconds)
            }
        }

        static var endBreak: String {
            isKorean ? "휴식 완료" : "End Break"
        }
    }

    // MARK: - Settings Window

    enum Settings {
        static var windowTitle: String {
            isKorean ? "Teumnirm 설정" : "Teumnirm Settings"
        }

        static var tabGeneral: String {
            isKorean ? "일반" : "General"
        }

        static var breakInterval: String {
            isKorean ? "휴식 알림 간격" : "Break Interval"
        }

        static func minutes(_ n: Int) -> String {
            isKorean ? "\(n)분" : "\(n) min"
        }

        static var autoRestoreTime: String {
            isKorean ? "자동 해제 시간" : "Auto-dismiss Time"
        }

        static var usageHistoryRetentionDays: String {
            isKorean ? "사용 기록 조회 기간" : "Usage History Range"
        }

        static var deferBreakWhileMicrophoneInUse: String {
            isKorean ? "마이크 사용 중에는 휴식 알림 미루기" : "Delay break alert while microphone is in use"
        }

        static var timerSettings: String {
            isKorean ? "타이머 설정" : "Timer Settings"
        }

        static var useCompatibilityMode: String {
            isKorean
                ? "호환 모드 사용 (블러가 안 보이면 활성화)"
                : "Use Compatibility Mode (enable if blur doesn't show)"
        }

        static var screenBlur: String {
            isKorean ? "화면 블러" : "Screen Blur"
        }

        static var menuBar: String {
            isKorean ? "메뉴바" : "Menu Bar"
        }

        static var showTimerInMenuBar: String {
            isKorean ? "메뉴바에 남은 시간 표시" : "Show remaining time in menu bar"
        }

        static var currentStatus: String {
            isKorean ? "현재 상태" : "Current Status"
        }

        static var nextBreakIn: String {
            isKorean ? "다음 휴식까지" : "Next Break In"
        }

        static var status: String {
            isKorean ? "상태" : "Status"
        }

        // Status texts
        static var statusUnknown: String {
            isKorean ? "알 수 없음" : "Unknown"
        }

        static var statusMonitoring: String {
            isKorean ? "모니터링 중" : "Monitoring"
        }

        static var statusPendingForMicrophone: String {
            isKorean ? "마이크 사용 종료 대기 중" : "Waiting for microphone to be released"
        }

        static var statusBreakTime: String {
            isKorean ? "휴식 시간" : "Break Time"
        }

        static var statusPaused: String {
            isKorean ? "일시정지" : "Paused"
        }
    }

    // MARK: - Usage History Window

    enum UsageHistory {
        static var windowTitle: String {
            isKorean ? "사용 기록" : "Usage History"
        }

        static var previousDay: String {
            isKorean ? "이전 날" : "Previous Day"
        }

        static var nextDay: String {
            isKorean ? "다음 날" : "Next Day"
        }

        static func days(_ value: Int) -> String {
            isKorean ? "최근 \(value)일" : "Last \(value) days"
        }

        static var emptyState: String {
            isKorean ? "표시할 사용 기록이 없습니다." : "No usage history to show."
        }

        static var noUsageOnDay: String {
            isKorean ? "이 날에는 기록된 사용 시간이 없습니다." : "No recorded usage for this day."
        }
    }

    // MARK: - Hue Settings

    enum Hue {
        static var enableIntegration: String {
            isKorean ? "Philips Hue 연동 사용" : "Enable Philips Hue Integration"
        }

        static var bridgeIP: String {
            isKorean ? "브릿지 IP 주소" : "Bridge IP Address"
        }

        static var autoDiscover: String {
            isKorean ? "자동 검색" : "Auto Discover"
        }

        static var searchingBridge: String {
            isKorean ? "브릿지 검색 중..." : "Searching for bridge..."
        }

        static var bridgeConnection: String {
            isKorean ? "브릿지 연결" : "Bridge Connection"
        }

        static var connectToBridge: String {
            isKorean ? "브릿지 연결하기" : "Connect to Bridge"
        }

        static var connecting: String {
            isKorean ? "연결 중..." : "Connecting..."
        }

        static var connected: String {
            isKorean ? "연결됨" : "Connected"
        }

        static var disconnect: String {
            isKorean ? "연결 해제" : "Disconnect"
        }

        static var authentication: String {
            isKorean ? "인증" : "Authentication"
        }

        static var loadLights: String {
            isKorean ? "조명 목록 불러오기" : "Load Lights"
        }

        static var lightsToControl: String {
            isKorean ? "제어할 조명" : "Lights to Control"
        }

        static var pressBridgeButton: String {
            isKorean ? "브릿지 버튼을 눌러주세요" : "Press Bridge Button"
        }

        static var cancel: String {
            isKorean ? "취소" : "Cancel"
        }

        static var connect: String {
            isKorean ? "연결" : "Connect"
        }

        static var pressBridgeButtonMessage: String {
            if isKorean {
                return "Philips Hue 브릿지의 큰 버튼을 누른 후 '연결'을 클릭하세요."
            } else {
                return "Press the button on your Philips Hue bridge, then click 'Connect'."
            }
        }

        static func couldNotFindBridge(_ error: String) -> String {
            if isKorean {
                return "브릿지를 찾을 수 없습니다: \(error)"
            } else {
                return "Could not find bridge: \(error)"
            }
        }

        static var pressButtonFirst: String {
            isKorean ? "브릿지 버튼을 먼저 눌러주세요" : "Please press the bridge button first"
        }

        static func connectionFailed(_ error: String) -> String {
            if isKorean {
                return "연결 실패: \(error)"
            } else {
                return "Connection failed: \(error)"
            }
        }

        static func couldNotLoadLights(_ error: String) -> String {
            if isKorean {
                return "조명 목록을 불러올 수 없습니다: \(error)"
            } else {
                return "Could not load lights: \(error)"
            }
        }

        static var localNetworkPermissionTitle: String {
            isKorean ? "로컬 네트워크 권한 필요" : "Local Network Permission Required"
        }

        static var localNetworkPermissionMessage: String {
            if isKorean {
                return
                    "Philips Hue 브릿지에 연결하려면 로컬 네트워크 접근 권한이 필요합니다.\n\n"
                    + "'확인'을 누르면 시스템 권한 요청이 표시됩니다. '허용'을 선택해 주세요."
            } else {
                return
                    "Local network access permission is required to connect to your Philips Hue bridge.\n\n"
                    + "Click 'OK' and select 'Allow' when the system permission prompt appears."
            }
        }

        static var ok: String {
            isKorean ? "확인" : "OK"
        }

        static var requestingPermission: String {
            isKorean ? "권한 요청 중..." : "Requesting permission..."
        }

        static var breakLightSettings: String {
            isKorean ? "휴식시간 조명 설정" : "Break Time Lighting"
        }

        static var breakMode: String {
            isKorean ? "모드" : "Mode"
        }

        static var breakModeColor: String {
            isKorean ? "색상" : "Color"
        }

        static var breakModeTemperature: String {
            isKorean ? "색온도" : "Color Temp"
        }

        static var breakModeBrightness: String {
            isKorean ? "밝기" : "Brightness"
        }

        static var breakColor: String {
            isKorean ? "휴식 색상" : "Break Color"
        }

        static var colorTemperature: String {
            isKorean ? "색온도" : "Color Temperature"
        }

        static func kelvin(_ value: Int) -> String {
            "\(value)K"
        }

        static var brightness: String {
            isKorean ? "밝기" : "Brightness"
        }

        static func brightnessPercent(_ value: Int) -> String {
            "\(value)%"
        }
    }

    // MARK: - Welcome Window

    enum Welcome {
        static var title: String {
            isKorean ? "Teumnirm이 실행되었습니다" : "Teumnirm is Running"
        }

        static var description: String {
            if isKorean {
                return "틈니름은 메뉴바 앱입니다.\n화면 상단의 타이머 아이콘을 클릭하여\n설정을 변경하거나 상태를 확인하세요."
            } else {
                return
                    "Teumnirm runs in the menu bar.\nClick the timer icon at the top of your screen\nto change settings or check status."
            }
        }

        static var gotIt: String {
            isKorean ? "확인" : "Got it"
        }

        static var menuBarHint: String {
            isKorean ? "메뉴바에서 찾아보세요 →" : "Find it in the menu bar →"
        }
    }

    // MARK: - Status Popover

    enum Popover {
        static var monitoringStarted: String {
            isKorean ? "모니터링 시작됨" : "Monitoring Started"
        }

        static var clickForOptions: String {
            isKorean ? "클릭하여 설정 및 상태 확인" : "Click for settings and status"
        }
    }
}
