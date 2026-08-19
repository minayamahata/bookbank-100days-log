import Foundation
import Testing
@testable import BookBank

struct RereadDatePolicyTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_787_126_400) // 2026-08-19 00:00 UTC

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func sameDayAsRegisteredAtIsAllowed() {
        let registered = day(2026, 8, 10)
        #expect(RereadDatePolicy.isValid(registered, registeredAt: registered, now: now, calendar: calendar))
        #expect(RereadDatePolicy.areReadingDatesConsistent(
            registeredAt: registered,
            rereadDates: [registered],
            now: now,
            calendar: calendar
        ))
    }

    @Test func rereadBeforeRegisteredAtIsRejected() {
        let registered = day(2026, 8, 10)
        let earlier = day(2026, 8, 9)
        #expect(!RereadDatePolicy.isValid(earlier, registeredAt: registered, now: now, calendar: calendar))
        #expect(!RereadDatePolicy.areReadingDatesConsistent(
            registeredAt: registered,
            rereadDates: [earlier],
            now: now,
            calendar: calendar
        ))
    }

    @Test func rereadAfterRegisteredAtIsAllowed() {
        let registered = day(2026, 8, 10)
        let later = day(2026, 8, 18)
        #expect(RereadDatePolicy.isValid(later, registeredAt: registered, now: now, calendar: calendar))
    }

    @Test func futureRereadAndRegisteredAtAreRejected() {
        let future = day(2026, 8, 20)
        let registered = day(2026, 8, 10)
        #expect(!RereadDatePolicy.isValid(future, registeredAt: registered, now: now, calendar: calendar))
        #expect(!RereadDatePolicy.isValidRegisteredAt(future, now: now, calendar: calendar))
        #expect(!RereadDatePolicy.areReadingDatesConsistent(
            registeredAt: future,
            rereadDates: [],
            now: now,
            calendar: calendar
        ))
    }

    @Test func registeredAtTodayIsAllowed() {
        #expect(RereadDatePolicy.isValidRegisteredAt(now, now: now, calendar: calendar))
    }

    @Test func upperBoundIsMinOfFirstRereadAndToday() {
        let firstReread = day(2026, 8, 12)
        #expect(RereadDatePolicy.registeredAtUpperBound(firstRereadDate: firstReread, now: now) == firstReread)
        #expect(RereadDatePolicy.registeredAtUpperBound(firstRereadDate: day(2026, 8, 25), now: now) == now)
        #expect(RereadDatePolicy.registeredAtUpperBound(firstRereadDate: nil, now: now) == now)
    }
}
