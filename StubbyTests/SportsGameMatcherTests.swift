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
}

private struct MockSportsDataProvider: SportsDataProvider {
    var games: [SportsGameMatch]

    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch] {
        games.filter { "\($0.sport)/\($0.league)" == sportPath }
    }
}
