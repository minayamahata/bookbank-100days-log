import Foundation
import Testing
@testable import BookBank

struct MonthlyLogShareEnglishLabelsTests {
    @Test func fullEnglishMonthNames() {
        #expect(MonthlyLogShareEnglishLabels.fullMonthNames == [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ])
        for month in 1...12 {
            #expect(MonthlyLogShareEnglishLabels.fullMonthName(month) == MonthlyLogShareEnglishLabels.fullMonthNames[month - 1])
        }
    }

    @Test func abbreviatedEnglishMonthNames() {
        #expect(MonthlyLogShareEnglishLabels.abbreviatedMonthNames == [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ])
        for month in 1...12 {
            #expect(
                MonthlyLogShareEnglishLabels.abbreviatedMonthName(month)
                    == MonthlyLogShareEnglishLabels.abbreviatedMonthNames[month - 1]
            )
        }
    }

    @Test func englishWeekdayAbbreviations() {
        #expect(MonthlyLogShareEnglishLabels.weekdayAbbreviations == [
            "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
        ])
    }

    @Test func labelsIgnoreAppLocale() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        #expect(MonthlyLogShareEnglishLabels.fullMonthName(8) == "August")
        #expect(MonthlyLogShareEnglishLabels.fullMonthName(8) != formatter.monthSymbols[7])
        #expect(MonthlyLogShareEnglishLabels.abbreviatedMonthName(8) == "Aug")
        #expect(MonthlyLogShareEnglishLabels.weekdayAbbreviations[0] == "Sun")
        #expect(MonthlyLogShareEnglishLabels.weekdayAbbreviations[0] != formatter.shortWeekdaySymbols[0])
    }

    @Test func firstWeekday1StartsOnSunday() {
        #expect(
            MonthlyLogShareEnglishLabels.weekdayAbbreviations(firstWeekday: 1)
                == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        )
    }

    @Test func firstWeekday2StartsOnMonday() {
        #expect(
            MonthlyLogShareEnglishLabels.weekdayAbbreviations(firstWeekday: 2)
                == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        )
    }

    @Test func weekdayLettersStayEnglishWhileDatesFollowCalendar() {
        var sunday = Calendar(identifier: .gregorian)
        sunday.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        sunday.firstWeekday = 1
        var monday = sunday
        monday.firstWeekday = 2

        let sundayLayout = MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: sunday)
        let mondayLayout = MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: monday)
        let sundayLabels = MonthlyLogShareEnglishLabels.weekdayAbbreviations(firstWeekday: 1)
        let mondayLabels = MonthlyLogShareEnglishLabels.weekdayAbbreviations(firstWeekday: 2)

        #expect(sundayLabels[sundayLayout.leadingBlankCount % 7] == "Sat")
        #expect(mondayLabels[mondayLayout.leadingBlankCount % 7] == "Sat")
        #expect(sundayLabels.allSatisfy { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].contains($0) })
        #expect(mondayLabels.allSatisfy { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].contains($0) })
    }
}
