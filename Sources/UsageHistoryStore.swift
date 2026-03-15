import Combine
import Foundation

final class UsageHistoryStore: ObservableObject {
    @Published private(set) var sessions: [UsageSession] = []
    @Published private(set) var activeSessionStart: Date?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSessions()
    }

    var recentDays: Int {
        get {
            let storedValue = defaults.integer(forKey: SettingsKeys.usageHistoryRecentDays)
            if AppConstants.usageHistoryDaysRange.contains(storedValue) {
                return storedValue
            }
            return AppConstants.defaultUsageHistoryDays
        }
        set {
            let normalized = min(
                max(newValue, AppConstants.usageHistoryDaysRange.lowerBound),
                AppConstants.usageHistoryDaysRange.upperBound
            )
            objectWillChange.send()
            defaults.set(normalized, forKey: SettingsKeys.usageHistoryRecentDays)
        }
    }

    var lastPrunedAt: Date? {
        defaults.object(forKey: SettingsKeys.usageHistoryLastPrunedAt) as? Date
    }

    func addSession(startAt: Date, endAt: Date) {
        guard endAt >= startAt else { return }
        let session = UsageSession(startAt: startAt, endAt: endAt)
        if let lastSession = sessions.last, shouldMerge(lastSession: lastSession, newSession: session) {
            let mergedSession = UsageSession(
                id: lastSession.id,
                startAt: lastSession.startAt,
                endAt: max(lastSession.endAt, session.endAt)
            )
            sessions[sessions.count - 1] = mergedSession
        } else {
            sessions.append(session)
            sessions.sort { $0.startAt < $1.startAt }
        }
        persist()
    }

    func startActiveSession(at startAt: Date) {
        activeSessionStart = startAt
    }

    func clearActiveSession() {
        activeSessionStart = nil
    }

    func recentSections(days: Int? = nil, now: Date = Date()) -> [UsageHistoryDaySection] {
        let recentDays = min(
            max(days ?? self.recentDays, AppConstants.usageHistoryDaysRange.lowerBound),
            AppConstants.usageHistoryDaysRange.upperBound
        )
        let calendar = Calendar.current
        guard
            let cutoff = calendar.date(
                byAdding: .day,
                value: -(recentDays - 1),
                to: calendar.startOfDay(for: now)
            )
        else {
            return []
        }

        var segmentsByDay: [Date: [UsageHistorySegment]] = [:]
        let effectiveSessions = projectedSessions(now: now)

        for session in effectiveSessions where session.endAt >= cutoff {
            let clampedStart = max(session.startAt, cutoff)
            split(sessionStart: clampedStart, sessionEnd: session.endAt, calendar: calendar).forEach {
                segment in
                segmentsByDay[segment.day, default: []].append(segment)
            }
        }

        return segmentsByDay
            .map { day, segments in
                let sortedSegments = segments.sorted { $0.startAt < $1.startAt }
                return UsageHistoryDaySection(day: day, segments: sortedSegments)
            }
            .sorted { $0.day > $1.day }
    }

    func pruneExpiredSessions(retentionDays: Int? = nil, now: Date = Date()) {
        let retentionDays = min(
            max(retentionDays ?? recentDays, AppConstants.usageHistoryDaysRange.lowerBound),
            AppConstants.usageHistoryDaysRange.upperBound
        )
        let calendar = Calendar.current
        guard
            let cutoff = calendar.date(
                byAdding: .day,
                value: -(retentionDays - 1),
                to: calendar.startOfDay(for: now)
            )
        else {
            return
        }

        let filtered = sessions.filter { $0.endAt >= cutoff }
        if filtered != sessions {
            sessions = filtered.sorted { $0.startAt < $1.startAt }
            persist()
        }
        defaults.set(now, forKey: SettingsKeys.usageHistoryLastPrunedAt)
    }

    func pruneIfNeeded(now: Date = Date()) {
        let calendar = Calendar.current
        if let lastPrunedAt, calendar.isDate(lastPrunedAt, inSameDayAs: now) {
            return
        }
        pruneExpiredSessions(retentionDays: recentDays, now: now)
    }

    private func loadSessions() {
        guard let data = defaults.data(forKey: SettingsKeys.usageHistorySessions) else { return }
        guard let decoded = try? decoder.decode([UsageSession].self, from: data) else { return }
        sessions = decoded.sorted { $0.startAt < $1.startAt }
    }

    private func persist() {
        guard let data = try? encoder.encode(sessions) else { return }
        defaults.set(data, forKey: SettingsKeys.usageHistorySessions)
    }

    private func projectedSessions(now: Date) -> [UsageSession] {
        guard let activeSessionStart else { return sessions }

        let activeSession = UsageSession(startAt: activeSessionStart, endAt: now)
        guard let lastSession = sessions.last else {
            return [activeSession]
        }

        guard shouldMerge(lastSession: lastSession, newSession: activeSession) else {
            return sessions + [activeSession]
        }

        var projected = sessions
        projected[projected.count - 1] = UsageSession(
            id: lastSession.id,
            startAt: lastSession.startAt,
            endAt: max(lastSession.endAt, activeSession.endAt)
        )
        return projected
    }

    private func shouldMerge(lastSession: UsageSession, newSession: UsageSession) -> Bool {
        let calendar = Calendar.current
        guard calendar.isDate(lastSession.endAt, inSameDayAs: newSession.startAt) else { return false }
        let gap = newSession.startAt.timeIntervalSince(lastSession.endAt)
        return gap <= AppConstants.usageHistoryMergeGap
    }

    private func split(
        sessionStart: Date,
        sessionEnd: Date,
        calendar: Calendar
    ) -> [UsageHistorySegment] {
        guard sessionEnd >= sessionStart else { return [] }

        var segments: [UsageHistorySegment] = []
        var currentStart = sessionStart

        while currentStart < sessionEnd {
            let dayStart = calendar.startOfDay(for: currentStart)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                break
            }
            let currentEnd = min(sessionEnd, nextDayStart)
            segments.append(
                UsageHistorySegment(day: dayStart, startAt: currentStart, endAt: currentEnd)
            )
            currentStart = currentEnd
        }

        if segments.isEmpty {
            let dayStart = calendar.startOfDay(for: sessionStart)
            segments.append(UsageHistorySegment(day: dayStart, startAt: sessionStart, endAt: sessionEnd))
        }

        return segments
    }
}

struct UsageHistoryDaySection: Identifiable, Equatable {
    let day: Date
    let segments: [UsageHistorySegment]

    var id: Date { day }

    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}

struct UsageHistorySegment: Identifiable, Equatable {
    let day: Date
    let startAt: Date
    let endAt: Date

    var id: String {
        "\(day.timeIntervalSinceReferenceDate)-\(startAt.timeIntervalSinceReferenceDate)"
    }

    var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
}
