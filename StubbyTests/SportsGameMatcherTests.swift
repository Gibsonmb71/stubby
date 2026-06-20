import XCTest
@testable import Stubby

final class SportsGameMatcherTests: XCTestCase {
    func testParsesESPNDateWithoutSeconds() throws {
        let date = try XCTUnwrap(ESPNDateParser.date(from: "2025-03-29T20:00Z"))
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 0)
    }

    func testMatchesCollegeBaseballTicketByTeamsDateAndVenue() async throws {
        let gameDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-29T20:00:00Z"))
        let draft = ImportedEventDraft(
            title: "Univ of South Carolina Gamecocks Baseball vs Tennessee",
            date: gameDate,
            venue: "Founders Park",
            sourceText: "FOUNDERS PARK\nUniv of South Carolina Gamecocks Baseball vs. Tennessee"
        )
        let expectedMatch = SportsGameMatch(
            espnEventID: "401748982",
            sport: "baseball",
            league: "college-baseball",
            gameDate: gameDate,
            venue: "Founders Park",
            city: "Columbia",
            state: "South Carolina",
            homeTeam: SportsTeamInfo(id: "2579", name: "South Carolina Gamecocks", abbreviation: "SC", logoURL: nil),
            awayTeam: SportsTeamInfo(id: "2633", name: "Tennessee Volunteers", abbreviation: "TENN", logoURL: nil),
            homeScore: 5,
            awayScore: 7,
            status: "Final",
            espnURL: nil
        )
        let unrelatedMatch = SportsGameMatch(
            espnEventID: "other",
            sport: "baseball",
            league: "college-baseball",
            gameDate: gameDate,
            venue: "Other Park",
            city: nil,
            state: nil,
            homeTeam: SportsTeamInfo(id: "1", name: "Duke Blue Devils", abbreviation: nil, logoURL: nil),
            awayTeam: SportsTeamInfo(id: "2", name: "Virginia Cavaliers", abbreviation: nil, logoURL: nil),
            homeScore: nil,
            awayScore: nil,
            status: nil,
            espnURL: nil
        )
        let matcher = SportsGameMatcher(provider: MockSportsDataProvider(games: [unrelatedMatch, expectedMatch]))

        let candidates = try await matcher.matchCandidates(for: draft)

        XCTAssertEqual(candidates.first?.espnEventID, "401748982")
        XCTAssertGreaterThan(candidates.first?.confidence ?? 0, unrelatedMatch.confidence)
    }

    func testSearchesNeighboringDatesForTimezoneMismatch() async throws {
        let ticketDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-30T03:30:00Z"))
        let espnDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-30T04:30:00Z"))
        let draft = ImportedEventDraft(
            title: "South Carolina vs Tennessee Baseball",
            date: ticketDate,
            venue: "Founders Park",
            sourceText: "South Carolina vs Tennessee"
        )
        let expectedMatch = SportsGameMatch(
            espnEventID: "timezone",
            sport: "baseball",
            league: "college-baseball",
            gameDate: espnDate,
            venue: "Founders Park",
            city: "Columbia",
            state: "South Carolina",
            homeTeam: SportsTeamInfo(id: "2579", name: "South Carolina Gamecocks", abbreviation: "SC", logoURL: nil),
            awayTeam: SportsTeamInfo(id: "2633", name: "Tennessee Volunteers", abbreviation: "TENN", logoURL: nil),
            homeScore: nil,
            awayScore: nil,
            status: nil,
            espnURL: nil
        )
        let provider = RecordingSportsDataProvider(games: [expectedMatch])
        let matcher = SportsGameMatcher(provider: provider)

        let candidates = try await matcher.matchCandidates(for: draft)

        XCTAssertEqual(candidates.first?.espnEventID, "timezone")
        let requestedDays = await provider.requestedDateStrings
        XCTAssertTrue(requestedDays.contains("20250328"))
        XCTAssertTrue(requestedDays.contains("20250329"))
        XCTAssertTrue(requestedDays.contains("20250330"))
    }

    func testScoresTeamAbbreviationsFromTicketText() async throws {
        let gameDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-29T20:00:00Z"))
        let draft = ImportedEventDraft(
            title: "SC vs TENN",
            date: gameDate,
            venue: "Founders Park",
            sourceText: "SC vs TENN"
        )
        let expectedMatch = SportsGameMatch(
            espnEventID: "abbreviations",
            sport: "baseball",
            league: "college-baseball",
            gameDate: gameDate,
            venue: "Founders Park",
            city: "Columbia",
            state: "South Carolina",
            homeTeam: SportsTeamInfo(id: "2579", name: "South Carolina Gamecocks", abbreviation: "SC", logoURL: nil),
            awayTeam: SportsTeamInfo(id: "2633", name: "Tennessee Volunteers", abbreviation: "TENN", logoURL: nil),
            homeScore: nil,
            awayScore: nil,
            status: nil,
            espnURL: nil
        )
        let matcher = SportsGameMatcher(provider: MockSportsDataProvider(games: [expectedMatch]))

        let candidates = try await matcher.matchCandidates(for: draft)

        XCTAssertEqual(candidates.first?.espnEventID, "abbreviations")
    }

    func testMatchesGamecockBasketballTicketWithSplitOpponentAndMascot() async throws {
        let gameDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-10T19:00:00Z"))
        let draft = ImportedEventDraft(
            title: "South Carolina Gamecocks MEN'S BASKETBALL vs. Georgia",
            date: gameDate,
            venue: "Colonial Life Arena",
            sourceText: [
                "vs. Georgia",
                "JAN 10",
                "14:00",
                "GAMECOCK",
                "MEN'S BASKETBALL",
                "Colonial Life Arena"
            ].joined(separator: "\n")
        )
        let expectedMatch = SportsGameMatch(
            espnEventID: "gamecock-basketball",
            sport: "basketball",
            league: "mens-college-basketball",
            gameDate: gameDate,
            venue: "Colonial Life Arena",
            city: "Columbia",
            state: "South Carolina",
            homeTeam: SportsTeamInfo(id: "2579", name: "South Carolina Gamecocks", abbreviation: "SC", logoURL: nil),
            awayTeam: SportsTeamInfo(id: "61", name: "Georgia Bulldogs", abbreviation: "UGA", logoURL: nil),
            homeScore: nil,
            awayScore: nil,
            status: nil,
            espnURL: nil
        )
        let matcher = SportsGameMatcher(provider: MockSportsDataProvider(games: [expectedMatch]))

        let candidates = try await matcher.matchCandidates(for: draft)

        XCTAssertEqual(candidates.first?.espnEventID, "gamecock-basketball")
    }
}

private struct MockSportsDataProvider: SportsDataProvider {
    var games: [SportsGameMatch]

    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch] {
        games.filter { "\($0.sport)/\($0.league)" == sportPath }
    }
}

private actor RecordingSportsDataProvider: SportsDataProvider {
    var games: [SportsGameMatch]
    private(set) var requestedDateStrings: [String] = []

    init(games: [SportsGameMatch]) {
        self.games = games
    }

    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch] {
        requestedDateStrings.append(ESPNSportsDataProvider.dateString(for: date))
        return games.filter { "\($0.sport)/\($0.league)" == sportPath && Calendar.current.isDate($0.gameDate, inSameDayAs: date) }
    }
}
