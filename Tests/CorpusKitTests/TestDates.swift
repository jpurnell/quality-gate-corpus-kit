import Foundation

/// Deterministic UTC date construction for tests.
///
/// Every date these suites build comes from a literal, so the parses here
/// cannot fail in practice. They still avoid force unwraps: a malformed
/// literal yields ``sentinel`` and fails whichever assertion consumed it,
/// rather than trapping and taking the entire run down with it.
///
/// This also gives the suites one date-formatting configuration instead of a
/// copy per file, so UTC and the POSIX locale cannot drift apart between them.
enum TestDates {

    /// Returned when a literal fails to parse.
    ///
    /// The Unix epoch is deliberate: it is far outside every window these
    /// tests assert on, so a parsing mistake surfaces as an obviously wrong
    /// date in the failure message instead of a plausible one.
    static let sentinel = Date(timeIntervalSince1970: 0)

    /// A Gregorian calendar pinned to UTC.
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// A formatter for `format`, pinned to UTC and a fixed locale.
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = .gmt
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    /// Parses a `yyyy-MM-dd` date.
    static func day(_ string: String) -> Date {
        formatter("yyyy-MM-dd").date(from: string) ?? sentinel
    }

    /// Parses a `yyyy-MM-dd'T'HH:mm:ss` timestamp.
    static func timestamp(_ string: String) -> Date {
        formatter("yyyy-MM-dd'T'HH:mm:ss").date(from: string) ?? sentinel
    }

    /// Builds a date from explicit UTC components.
    static func utc(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return utcCalendar.date(from: components) ?? sentinel
    }
}
