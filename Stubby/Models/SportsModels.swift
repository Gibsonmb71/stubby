import Foundation

struct SportsTeamInfo: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var abbreviation: String?
    var logoURL: URL?
}

struct SportsGameMatch: Codable, Equatable, Identifiable {
    var espnEventID: String
    var sport: String
    var league: String
    var gameDate: Date
    var venue: String?
    var city: String?
    var state: String?
    var homeTeam: SportsTeamInfo
    var awayTeam: SportsTeamInfo
    var homeScore: Int?
    var awayScore: Int?
    var status: String?
    var espnURL: URL?
    var confidence: Int = 0

    var id: String { espnEventID }

    var title: String {
        "\(awayTeam.name) at \(homeTeam.name)"
    }

    var scoreSummary: String? {
        guard let homeScore, let awayScore else { return nil }
        return "\(awayTeam.name) \(awayScore), \(homeTeam.name) \(homeScore)"
    }
}

struct TicketDetails: Codable, Equatable {
    var originalTitle: String
    var originalDate: Date?
    var originalVenue: String?
    var section: String?
    var row: String?
    var seat: String?
    var generalAdmissionLabel: String?
}

enum SportsLookupStatus: Equatable {
    case idle
    case searching
    case matched(SportsGameMatch)
    case candidates([SportsGameMatch])
    case noMatch
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "ESPN Lookup Ready"
        case .searching:
            return "Searching ESPN"
        case .matched:
            return "ESPN Match Applied"
        case .candidates:
            return "Choose ESPN Match"
        case .noMatch:
            return "No ESPN Match Found"
        case .failed:
            return "ESPN Lookup Failed"
        }
    }
}
