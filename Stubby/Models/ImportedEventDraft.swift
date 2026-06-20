import Foundation

struct ParsedEventDetails: Equatable {
    var title: String?
    var date: Date?
    var venue: String?
    var section: String?
    var row: String?
    var seat: String?
    var isGeneralAdmission: Bool
    var rawText: String
    var barcodePayloads: [String]
}

struct ImportedEventDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date?
    var venue: String
    var section: String
    var row: String
    var seat: String
    var isGeneralAdmission: Bool
    var notes: String
    var sourceText: String
    var category: String?
    var participants: [String]
    var imageURL: URL?
    var sportsGame: SportsGameMatch?
    var ticketDetails: TicketDetails?
    var barcodePayloads: [String]

    init(
        title: String = "",
        date: Date? = nil,
        venue: String = "",
        section: String = "",
        row: String = "",
        seat: String = "",
        isGeneralAdmission: Bool = false,
        notes: String = "",
        sourceText: String = "",
        category: String? = nil,
        participants: [String] = [],
        imageURL: URL? = nil,
        sportsGame: SportsGameMatch? = nil,
        ticketDetails: TicketDetails? = nil,
        barcodePayloads: [String] = []
    ) {
        self.title = title
        self.date = date
        self.venue = venue
        self.section = section
        self.row = row
        self.seat = seat
        self.isGeneralAdmission = isGeneralAdmission
        self.notes = notes
        self.sourceText = sourceText
        self.category = category
        self.participants = participants
        self.imageURL = imageURL
        self.sportsGame = sportsGame
        self.ticketDetails = ticketDetails
        self.barcodePayloads = barcodePayloads
    }

    init(details: ParsedEventDetails) {
        self.init(
            title: details.title ?? "",
            date: details.date,
            venue: details.venue ?? "",
            section: details.section ?? "",
            row: details.row ?? "",
            seat: details.seat ?? "",
            isGeneralAdmission: details.isGeneralAdmission,
            sourceText: details.rawText,
            ticketDetails: TicketDetails(
                originalTitle: details.title ?? "",
                originalDate: details.date,
                originalVenue: details.venue,
                section: details.section,
                row: details.row,
                seat: details.seat,
                generalAdmissionLabel: details.isGeneralAdmission ? "General Admission" : nil
            ),
            barcodePayloads: details.barcodePayloads
        )
    }

    func makeEvent() -> Event {
        Event(
            title: title,
            date: date,
            venue: venue,
            section: section,
            row: row,
            seat: seat,
            isGeneralAdmission: isGeneralAdmission,
            notes: notes,
            sourceText: sourceText,
            category: category,
            participants: participants,
            imageURL: imageURL,
            sportsGame: sportsGame,
            ticketDetails: ticketDetails,
            barcodePayloads: barcodePayloads
        )
    }

    mutating func apply(_ match: SportsGameMatch, logoURL: URL? = nil) {
        title = match.title
        date = match.gameDate
        venue = match.venue ?? venue
        category = "\(match.sport.capitalized) · \(match.league)"
        participants = [match.awayTeam.name, match.homeTeam.name]
        imageURL = logoURL ?? match.homeTeam.logoURL ?? match.awayTeam.logoURL
        sportsGame = match
    }
}

struct TicketImportResult: Identifiable {
    var id = UUID()
    var draft: ImportedEventDraft
    var previewImageData: Data?
}
