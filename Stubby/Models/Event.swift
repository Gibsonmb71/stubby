import Foundation

struct Event: Identifiable, Codable, Equatable {
    var id: UUID
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
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
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
        barcodePayloads: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case venue
        case section
        case row
        case seat
        case isGeneralAdmission
        case notes
        case sourceText
        case category
        case participants
        case imageURL
        case artworkURL
        case sportsGame
        case ticketDetails
        case barcodePayloads
        case ticketmasterEventID
        case ticketmasterURL
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        venue = try container.decodeIfPresent(String.self, forKey: .venue) ?? ""
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? ""
        row = try container.decodeIfPresent(String.self, forKey: .row) ?? ""
        seat = try container.decodeIfPresent(String.self, forKey: .seat) ?? ""
        isGeneralAdmission = try container.decodeIfPresent(Bool.self, forKey: .isGeneralAdmission) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category)
        participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
            ?? container.decodeIfPresent(URL.self, forKey: .artworkURL)
        sportsGame = try container.decodeIfPresent(SportsGameMatch.self, forKey: .sportsGame)
        ticketDetails = try container.decodeIfPresent(TicketDetails.self, forKey: .ticketDetails)
        barcodePayloads = try container.decodeIfPresent([String].self, forKey: .barcodePayloads) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(venue, forKey: .venue)
        try container.encode(section, forKey: .section)
        try container.encode(row, forKey: .row)
        try container.encode(seat, forKey: .seat)
        try container.encode(isGeneralAdmission, forKey: .isGeneralAdmission)
        try container.encode(notes, forKey: .notes)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(participants, forKey: .participants)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(sportsGame, forKey: .sportsGame)
        try container.encodeIfPresent(ticketDetails, forKey: .ticketDetails)
        try container.encode(barcodePayloads, forKey: .barcodePayloads)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : title
    }

    var seatingSummary: String {
        if isGeneralAdmission {
            return "General Admission"
        }

        let parts = [
            section.isEmpty ? nil : "Sec \(section)",
            row.isEmpty ? nil : "Row \(row)",
            seat.isEmpty ? nil : "Seat \(seat)"
        ].compactMap { $0 }

        return parts.isEmpty ? "No seat details" : parts.joined(separator: " · ")
    }

    var venueSummary: String {
        venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Venue not set" : venue
    }
}
