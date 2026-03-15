import AppKit
import SwiftUI

final class UsageHistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hostingController: NSHostingController<UsageHistoryView>?

    func showWindow(store: UsageHistoryStore) {
        if let window {
            if let hostingController {
                hostingController.rootView = UsageHistoryView(store: store)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: UsageHistoryView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = L.UsageHistory.windowTitle
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 440, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        self.hostingController = hostingController

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hostingController = nil
    }
}

struct UsageHistoryView: View {
    @ObservedObject var store: UsageHistoryStore
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let sections = store.recentSections(now: now)
            let daySection = sections.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }

            HStack {
                Button {
                    selectedDay = previousDay(from: selectedDay)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveToPreviousDay)

                Spacer()

                VStack(spacing: 4) {
                    Text(dayHeaderTitle(for: selectedDay, section: daySection))
                        .font(.headline)
                    Text(L.UsageHistory.days(store.recentDays))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    selectedDay = nextDay(from: selectedDay)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveToNextDay)
            }

            if sections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L.UsageHistory.windowTitle)
                        .font(.headline)
                    Text(L.UsageHistory.emptyState)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let daySection {
                List(daySection.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(segmentTimeRange(segment))
                        Text(durationText(segment.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L.UsageHistory.noUsageOnDay)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 460)
        .onChange(of: store.recentDays) { _ in
            clampSelectedDay()
        }
        .onAppear {
            clampSelectedDay()
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { value in
            now = value
        }
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var earliestDay: Date {
        Calendar.current.date(byAdding: .day, value: -(store.recentDays - 1), to: today) ?? today
    }

    private var canMoveToPreviousDay: Bool {
        selectedDay > earliestDay
    }

    private var canMoveToNextDay: Bool {
        selectedDay < today
    }

    private func dayHeaderTitle(for day: Date, section: UsageHistoryDaySection?) -> String {
        let totalDuration = section?.totalDuration ?? 0
        return "\(dayText(day)) (\(durationText(totalDuration)))"
    }

    private func previousDay(from day: Date) -> Date {
        let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        return max(previous, earliestDay)
    }

    private func nextDay(from day: Date) -> Date {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        return min(next, today)
    }

    private func clampSelectedDay() {
        if selectedDay < earliestDay {
            selectedDay = earliestDay
        } else if selectedDay > today {
            selectedDay = today
        }
    }

    private func segmentTimeRange(_ segment: UsageHistorySegment) -> String {
        "\(timeText(segment.startAt)) - \(timeText(segment.endAt))"
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.preferredLanguages.first.flatMap(Locale.init(identifier:))
        formatter.dateFormat = isKorean ? "M월 d일" : "MMM d"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.preferredLanguages.first.flatMap(Locale.init(identifier:))
        formatter.dateFormat = isKorean ? "a h시 mm분" : "h:mm a"
        return formatter.string(from: date)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if isKorean {
            if totalMinutes >= 60 {
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
            }
            return "\(totalMinutes)분"
        }

        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
        }
        return "\(totalMinutes) min"
    }
}
