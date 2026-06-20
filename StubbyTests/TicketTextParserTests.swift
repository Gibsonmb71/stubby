import XCTest
@testable import Stubby

final class TicketTextParserTests: XCTestCase {
    func testParsesReservedSeatTicket() {
        let parser = TicketTextParser()
        let details = parser.parse(textLines: [
            "Ticketmaster",
            "The National",
            "Fri, Aug 9, 2026 7:30 PM",
            "Madison Square Garden",
            "Sec 102 Row B Seat 14"
        ])

        XCTAssertEqual(details.title, "The National")
        XCTAssertEqual(details.venue, "Madison Square Garden")
        XCTAssertEqual(details.section, "102")
        XCTAssertEqual(details.row, "B")
        XCTAssertEqual(details.seat, "14")
        XCTAssertFalse(details.isGeneralAdmission)
        XCTAssertNotNil(details.date)
    }

    func testParsesGeneralAdmissionTicket() {
        let parser = TicketTextParser()
        let details = parser.parse(textLines: [
            "Lunar Festival",
            "General Admission",
            "Jun 21, 2026 6:00 PM",
            "Civic Center Plaza"
        ])

        XCTAssertEqual(details.title, "Lunar Festival")
        XCTAssertEqual(details.venue, "Civic Center Plaza")
        XCTAssertTrue(details.isGeneralAdmission)
    }

    func testParsesLabelsSplitAcrossLines() {
        let parser = TicketTextParser()
        let details = parser.parse(textLines: [
            "City FC vs United",
            "Section",
            "215",
            "Row",
            "12",
            "Seat",
            "8"
        ])

        XCTAssertEqual(details.section, "215")
        XCTAssertEqual(details.row, "12")
        XCTAssertEqual(details.seat, "8")
    }

    func testParsesTicketmasterColumnLayoutWithPhoneChromeNoise() throws {
        let parser = TicketTextParser()
        let details = parser.parse(textLines: [
            "15:11",
            "1",
            "4:00 PM",
            "ticketmaster",
            "Mar 29, 2025",
            "t",
            "FOUNDERS PARK",
            "Univ of South Carolina Gamecocks Baseball vs. Tennessee...",
            "SECTION",
            "ROW",
            "SEAT",
            "12",
            "17",
            "4",
            "ENTRY INFO",
            "TICKET TYPE",
            "BEHIND HOME PLATE Resale Ticket",
            "EXPIRED"
        ])

        XCTAssertEqual(details.title, "Univ of South Carolina Gamecocks Baseball vs. Tennessee...")
        XCTAssertEqual(details.venue, "FOUNDERS PARK")
        XCTAssertEqual(details.section, "12")
        XCTAssertEqual(details.row, "17")
        XCTAssertEqual(details.seat, "4")

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(details.date))
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 0)
    }

    func testParsesTicketmasterGamecockBasketballLayoutWithUpperLevelNoise() throws {
        let parser = TicketTextParser()
        let details = parser.parse(textLines: [
            "15:124",
            "1",
            "vs. Georgia",
            "JAN 10",
            "14:00",
            "GAMECOCK",
            "MEN'S BASKETBALL",
            "Colonial Life Arena",
            "Sec",
            "Row",
            "Seat",
            "UPPER",
            "LEVEL",
            "219",
            "1",
            "17",
            "Verified Resale Ticket",
            "Colonial Life Arena",
            "ticketmaster"
        ])

        XCTAssertEqual(details.title, "South Carolina Gamecocks MEN'S BASKETBALL vs. Georgia")
        XCTAssertEqual(details.venue, "Colonial Life Arena")
        XCTAssertEqual(details.section, "219")
        XCTAssertEqual(details.row, "1")
        XCTAssertEqual(details.seat, "17")

        XCTAssertNil(details.date)
        let dateMissingYear = try XCTUnwrap(details.dateMissingYear)
        XCTAssertEqual(dateMissingYear.month, 1)
        XCTAssertEqual(dateMissingYear.day, 10)
        XCTAssertEqual(dateMissingYear.hour, 14)
        XCTAssertEqual(dateMissingYear.minute, 0)

        let resolvedDate = try XCTUnwrap(dateMissingYear.date(in: 2026))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: resolvedDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)
    }
}
