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
}
