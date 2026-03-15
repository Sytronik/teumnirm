import Foundation
import Testing
@testable import Teumnirm

struct UsageHistoryStoreTests {
    @Test
    func persistsSessionsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let store = UsageHistoryStore(defaults: defaults)

        let start = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 0)
        let end = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 50)

        store.addSession(startAt: start, endAt: end)

        let reloadedStore = UsageHistoryStore(defaults: defaults)
        #expect(reloadedStore.sessions.count == 1)
        #expect(reloadedStore.sessions[0].startAt == start)
        #expect(reloadedStore.sessions[0].endAt == end)
    }

    @Test
    func mergesAdjacentSessionsWithinThreeMinutesOnSameDay() {
        let store = UsageHistoryStore(defaults: makeDefaults())

        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 50)
        )
        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 52),
            endAt: makeDate(year: 2026, month: 3, day: 15, hour: 16, minute: 0)
        )

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].startAt == makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 0))
        #expect(store.sessions[0].endAt == makeDate(year: 2026, month: 3, day: 15, hour: 16, minute: 0))
    }

    @Test
    func doesNotMergeSessionsAcrossMidnightEvenWithinThreeMinutes() {
        let store = UsageHistoryStore(defaults: makeDefaults())

        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 14, hour: 23, minute: 50),
            endAt: makeDate(year: 2026, month: 3, day: 14, hour: 23, minute: 59)
        )
        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 15, hour: 0, minute: 1),
            endAt: makeDate(year: 2026, month: 3, day: 15, hour: 0, minute: 10)
        )

        #expect(store.sessions.count == 2)
    }

    @Test
    func recentSectionsSplitSessionsAcrossDays() {
        let store = UsageHistoryStore(defaults: makeDefaults())
        let start = makeDate(year: 2026, month: 3, day: 14, hour: 23, minute: 50)
        let end = makeDate(year: 2026, month: 3, day: 15, hour: 0, minute: 10)
        let now = makeDate(year: 2026, month: 3, day: 15, hour: 12, minute: 0)

        store.addSession(startAt: start, endAt: end)

        let sections = store.recentSections(days: 2, now: now)

        #expect(sections.count == 2)
        #expect(sections[0].day == Calendar.current.startOfDay(for: end))
        #expect(Int(sections[0].totalDuration) == 10 * 60)
        #expect(sections[0].segments.count == 1)
        #expect(sections[0].segments[0].startAt == makeDate(year: 2026, month: 3, day: 15, hour: 0, minute: 0))
        #expect(sections[0].segments[0].endAt == end)
        #expect(sections[1].day == Calendar.current.startOfDay(for: start))
        #expect(Int(sections[1].totalDuration) == 10 * 60)
        #expect(sections[1].segments[0].startAt == start)
    }

    @Test
    func recentSectionsIncludeActiveSession() {
        let store = UsageHistoryStore(defaults: makeDefaults())
        let sessionStart = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 0)
        let now = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 20)

        store.startActiveSession(at: sessionStart)

        let sections = store.recentSections(days: 1, now: now)

        #expect(sections.count == 1)
        #expect(Int(sections[0].totalDuration) == 20 * 60)
        #expect(sections[0].segments.count == 1)
        #expect(sections[0].segments[0].startAt == sessionStart)
        #expect(sections[0].segments[0].endAt == now)
    }

    @Test
    func recentSectionsMergeSavedAndActiveSessionsWithinThreeMinutes() {
        let store = UsageHistoryStore(defaults: makeDefaults())
        let firstStart = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 0)
        let firstEnd = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 50)
        let activeStart = makeDate(year: 2026, month: 3, day: 15, hour: 15, minute: 52)
        let now = makeDate(year: 2026, month: 3, day: 15, hour: 16, minute: 0)

        store.addSession(startAt: firstStart, endAt: firstEnd)
        store.startActiveSession(at: activeStart)

        let sections = store.recentSections(days: 1, now: now)

        #expect(sections.count == 1)
        #expect(sections[0].segments.count == 1)
        #expect(sections[0].segments[0].startAt == firstStart)
        #expect(sections[0].segments[0].endAt == now)
        #expect(Int(sections[0].totalDuration) == 60 * 60)
    }

    @Test
    func pruneExpiredSessionsRemovesHistoryOutsideRetention() {
        let defaults = makeDefaults()
        let store = UsageHistoryStore(defaults: defaults)
        let now = makeDate(year: 2026, month: 3, day: 15, hour: 12, minute: 0)

        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 5, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30)
        )
        store.addSession(
            startAt: makeDate(year: 2026, month: 3, day: 14, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 14, hour: 9, minute: 30)
        )

        store.pruneExpiredSessions(retentionDays: 7, now: now)

        #expect(store.sessions.count == 1)
        #expect(Calendar.current.isDate(store.sessions[0].startAt, inSameDayAs: makeDate(year: 2026, month: 3, day: 14, hour: 0, minute: 0)))
        #expect(defaults.object(forKey: SettingsKeys.usageHistoryLastPrunedAt) as? Date == now)
    }

    @Test
    func pruneIfNeededRunsAtMostOncePerDay() {
        let store = UsageHistoryStore(defaults: makeDefaults())
        let dayOneMorning = makeDate(year: 2026, month: 3, day: 15, hour: 9, minute: 0)
        let dayOneEvening = makeDate(year: 2026, month: 3, day: 15, hour: 18, minute: 0)
        let dayTwoMorning = makeDate(year: 2026, month: 3, day: 16, hour: 9, minute: 0)

        store.addSession(
            startAt: makeDate(year: 2026, month: 2, day: 1, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 2, day: 1, hour: 9, minute: 30)
        )

        store.pruneIfNeeded(now: dayOneMorning)
        #expect(store.sessions.isEmpty)

        store.addSession(
            startAt: makeDate(year: 2026, month: 2, day: 2, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 2, day: 2, hour: 9, minute: 30)
        )

        store.pruneIfNeeded(now: dayOneEvening)
        #expect(store.sessions.count == 1)

        store.pruneIfNeeded(now: dayTwoMorning)
        #expect(store.sessions.isEmpty)
    }

    @Test
    func recentDaysDefaultsAndClampsPersistedValues() {
        let defaults = makeDefaults()
        let store = UsageHistoryStore(defaults: defaults)

        #expect(store.recentDays == AppConstants.defaultUsageHistoryDays)

        store.recentDays = 100
        #expect(store.recentDays == AppConstants.usageHistoryDaysRange.upperBound)

        let reloadedStore = UsageHistoryStore(defaults: defaults)
        #expect(reloadedStore.recentDays == AppConstants.usageHistoryDaysRange.upperBound)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UsageHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
