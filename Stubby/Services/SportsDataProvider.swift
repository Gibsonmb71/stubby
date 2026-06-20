import Foundation

protocol SportsDataProvider {
    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch]
}

struct ESPNSportsDataProvider: SportsDataProvider {
    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch] {
        var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/\(sportPath)/scoreboard")
        var queryItems = [
            URLQueryItem(name: "dates", value: Self.dateString(for: date)),
            URLQueryItem(name: "limit", value: "500")
        ]
        if sportPath == "football/college-football" {
            queryItems.append(URLQueryItem(name: "groups", value: "80"))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let scoreboard = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
        let pathParts = sportPath.split(separator: "/").map(String.init)
        let sport = pathParts.first ?? ""
        let league = pathParts.dropFirst().joined(separator: "/")

        return scoreboard.events.compactMap { event in
            guard let competition = event.competitions.first else { return nil }
            let competitors = competition.competitors
            guard
                let home = competitors.first(where: { $0.homeAway == "home" }),
                let away = competitors.first(where: { $0.homeAway == "away" }),
                let gameDate = ESPNDateParser.date(from: competition.date ?? event.date)
            else {
                return nil
            }

            return SportsGameMatch(
                espnEventID: event.id,
                sport: sport,
                league: league,
                gameDate: gameDate,
                venue: competition.venue?.fullName,
                city: competition.venue?.address?.city,
                state: competition.venue?.address?.state,
                homeTeam: home.sportsTeam,
                awayTeam: away.sportsTeam,
                homeScore: Int(home.score ?? ""),
                awayScore: Int(away.score ?? ""),
                status: competition.status?.type?.description ?? event.status?.type?.description,
                espnURL: event.links?.first(where: { $0.rel?.contains("summary") == true })?.href
                    ?? event.links?.first?.href
            )
        }
    }

    private static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

}

enum ESPNDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

struct SportsGameMatcher {
    var provider: SportsDataProvider = ESPNSportsDataProvider()

    func matchCandidates(for draft: ImportedEventDraft) async throws -> [SportsGameMatch] {
        guard let date = draft.date else { return [] }

        let sportPaths = sportPaths(for: draft)
        var candidates: [SportsGameMatch] = []
        var lookupErrors: [Error] = []
        for path in sportPaths {
            do {
                let games = try await provider.events(sportPath: path, date: date)
                candidates.append(contentsOf: games.map { game in
                    var scored = game
                    scored.confidence = score(game, against: draft)
                    return scored
                })
            } catch {
                lookupErrors.append(error)
            }
        }

        let scoredCandidates = candidates
            .filter { $0.confidence >= 35 }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return abs(lhs.gameDate.timeIntervalSince(date)) < abs(rhs.gameDate.timeIntervalSince(date))
                }
                return lhs.confidence > rhs.confidence
            }
        if scoredCandidates.isEmpty, let firstError = lookupErrors.first, lookupErrors.count == sportPaths.count {
            throw firstError
        }

        return scoredCandidates
    }

    private func sportPaths(for draft: ImportedEventDraft) -> [String] {
        let text = normalized([draft.title, draft.venue, draft.sourceText].joined(separator: " "))

        if text.contains("baseball") {
            return text.contains("college") || text.contains("univ") || text.contains("university") || text.contains("gamecocks")
                ? ["baseball/college-baseball", "baseball/mlb"]
                : ["baseball/mlb", "baseball/college-baseball"]
        }
        if text.contains("football") {
            return text.contains("college") || text.contains("univ") || text.contains("university")
                ? ["football/college-football", "football/nfl"]
                : ["football/nfl", "football/college-football"]
        }
        if text.contains("basketball") {
            return text.contains("women") ? ["basketball/womens-college-basketball", "basketball/wnba"] : ["basketball/mens-college-basketball", "basketball/nba"]
        }
        if text.contains("hockey") {
            return ["hockey/nhl", "hockey/mens-college-hockey", "hockey/womens-college-hockey"]
        }
        if text.contains("soccer") {
            return ["soccer/usa.1", "soccer/eng.1", "soccer/uefa.champions", "soccer/fifa.world"]
        }

        return [
            "baseball/college-baseball",
            "football/college-football",
            "basketball/mens-college-basketball",
            "baseball/mlb",
            "football/nfl",
            "basketball/nba",
            "hockey/nhl",
            "soccer/usa.1"
        ]
    }

    private func score(_ game: SportsGameMatch, against draft: ImportedEventDraft) -> Int {
        var score = 0
        let title = normalized(draft.title)
        let source = normalized(draft.sourceText)
        let venue = normalized(draft.venue)
        let haystack = [title, source].joined(separator: " ")

        if draft.date.map({ Calendar.current.isDate($0, inSameDayAs: game.gameDate) }) == true {
            score += 30
        }

        let homeTokens = significantTokens(game.homeTeam.name)
        let awayTokens = significantTokens(game.awayTeam.name)
        let homeHits = tokenHits(homeTokens, in: haystack)
        let awayHits = tokenHits(awayTokens, in: haystack)
        if homeHits > 0 { score += 25 + min(homeHits * 4, 12) }
        if awayHits > 0 { score += 25 + min(awayHits * 4, 12) }

        if homeHits > 0 && awayHits > 0 {
            score += 25
        }

        let gameVenue = normalized([game.venue, game.city, game.state].compactMap { $0 }.joined(separator: " "))
        if !venue.isEmpty, !gameVenue.isEmpty {
            if gameVenue.contains(venue) || venue.contains(gameVenue) {
                score += 18
            } else if tokenHits(significantTokens(gameVenue), in: venue) >= 2 {
                score += 12
            }
        }

        if let draftDate = draft.date {
            let delta = abs(game.gameDate.timeIntervalSince(draftDate))
            if delta < 60 * 60 * 2 {
                score += 8
            }
        }

        return score
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func significantTokens(_ value: String) -> [String] {
        let ignored: Set<String> = ["the", "at", "vs", "and", "of", "university", "college"]
        return normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !ignored.contains($0) }
    }

    private func tokenHits(_ tokens: [String], in text: String) -> Int {
        tokens.filter { text.contains($0) }.count
    }
}

private struct ESPNScoreboard: Decodable {
    var events: [ESPNEvent]
}

private struct ESPNEvent: Decodable {
    var id: String
    var date: String?
    var name: String?
    var competitions: [ESPNCompetition]
    var links: [ESPNLink]?
    var status: ESPNStatus?
}

private struct ESPNCompetition: Decodable {
    var date: String?
    var venue: ESPNVenue?
    var competitors: [ESPNCompetitor]
    var status: ESPNStatus?
}

private struct ESPNVenue: Decodable {
    var fullName: String?
    var address: ESPNAddress?
}

private struct ESPNAddress: Decodable {
    var city: String?
    var state: String?
}

private struct ESPNCompetitor: Decodable {
    var id: String?
    var homeAway: String?
    var score: String?
    var team: ESPNTeam

    var sportsTeam: SportsTeamInfo {
        SportsTeamInfo(
            id: id ?? team.id ?? UUID().uuidString,
            name: team.displayName ?? team.name ?? team.location ?? "Team",
            abbreviation: team.abbreviation,
            logoURL: team.logo.flatMap(URL.init(string:))
        )
    }
}

private struct ESPNTeam: Decodable {
    var id: String?
    var location: String?
    var name: String?
    var displayName: String?
    var abbreviation: String?
    var logo: String?
}

private struct ESPNStatus: Decodable {
    var type: ESPNStatusType?
}

private struct ESPNStatusType: Decodable {
    var description: String?
}

private struct ESPNLink: Decodable {
    var rel: [String]?
    var href: URL?
}
