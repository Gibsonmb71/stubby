import Foundation
import os

protocol SportsDataProvider {
    func events(sportPath: String, date: Date) async throws -> [SportsGameMatch]
}

private let sportsLookupLogger = Logger(subsystem: "com.gibsonbell.stubby", category: "ESPNLookup")

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
            sportsLookupLogger.error("Failed to build ESPN URL for path=\(sportPath, privacy: .public)")
            throw URLError(.badURL)
        }

        sportsLookupLogger.info("Requesting ESPN scoreboard path=\(sportPath, privacy: .public) date=\(Self.dateString(for: date), privacy: .public)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            sportsLookupLogger.error("ESPN response was not HTTP for path=\(sportPath, privacy: .public)")
            throw ESPNLookupError.invalidResponse(url)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            sportsLookupLogger.error("ESPN HTTP \(httpResponse.statusCode, privacy: .public) path=\(sportPath, privacy: .public) body=\(body, privacy: .public)")
            throw ESPNLookupError.httpStatus(httpResponse.statusCode, url)
        }

        let scoreboard: ESPNScoreboard
        do {
            scoreboard = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
        } catch {
            sportsLookupLogger.error("Failed to decode ESPN scoreboard path=\(sportPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
        let pathParts = sportPath.split(separator: "/").map(String.init)
        let sport = pathParts.first ?? ""
        let league = pathParts.dropFirst().joined(separator: "/")
        var skippedEvents = 0

        let games = scoreboard.events.compactMap { event -> SportsGameMatch? in
            guard let competition = event.competitions.first else {
                skippedEvents += 1
                sportsLookupLogger.debug("Skipping ESPN event \(event.id, privacy: .public): missing competition")
                return nil
            }
            let competitors = competition.competitors
            guard competitors.count >= 2 else {
                skippedEvents += 1
                sportsLookupLogger.debug("Skipping ESPN event \(event.id, privacy: .public): not enough competitors")
                return nil
            }
            let fallbackHome = competitors.last
            let fallbackAway = competitors.first
            guard
                let home = competitors.first(where: { $0.homeAway == "home" }) ?? fallbackHome,
                let away = competitors.first(where: { $0.homeAway == "away" }) ?? fallbackAway,
                let gameDate = ESPNDateParser.date(from: competition.date ?? event.date)
            else {
                skippedEvents += 1
                sportsLookupLogger.debug("Skipping ESPN event \(event.id, privacy: .public): missing teams or date")
                return nil
            }
            guard home.id != away.id else {
                skippedEvents += 1
                sportsLookupLogger.debug("Skipping ESPN event \(event.id, privacy: .public): duplicate competitors")
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

        sportsLookupLogger.info("Decoded \(games.count, privacy: .public) ESPN games path=\(sportPath, privacy: .public), skipped=\(skippedEvents, privacy: .public)")
        return games
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

}

enum ESPNLookupError: LocalizedError {
    case invalidResponse(URL)
    case httpStatus(Int, URL)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let url):
            return "ESPN returned a non-HTTP response for \(url.absoluteString)."
        case .httpStatus(let statusCode, let url):
            return "ESPN returned HTTP \(statusCode) for \(url.absoluteString)."
        }
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

        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss.SSSX", "yyyy-MM-dd HH:mm:ss"] {
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
        let dates = lookupDates(for: date)
        var candidatesByID: [String: SportsGameMatch] = [:]
        var lookupErrors: [Error] = []
        sportsLookupLogger.info("Starting ESPN match title=\(draft.title, privacy: .public) venue=\(draft.venue, privacy: .public) paths=\(sportPaths.joined(separator: ","), privacy: .public)")
        for path in sportPaths {
            for lookupDate in dates {
                do {
                    let games = try await provider.events(sportPath: path, date: lookupDate)
                    sportsLookupLogger.debug("Scoring \(games.count, privacy: .public) ESPN games path=\(path, privacy: .public) lookupDate=\(ESPNSportsDataProvider.dateString(for: lookupDate), privacy: .public)")
                    for game in games {
                        var scored = game
                        scored.confidence = score(game, against: draft)
                        if let existing = candidatesByID[scored.espnEventID] {
                            candidatesByID[scored.espnEventID] = betterCandidate(existing, scored, targetDate: date)
                        } else {
                            candidatesByID[scored.espnEventID] = scored
                        }
                    }
                } catch {
                    lookupErrors.append(error)
                    sportsLookupLogger.error("ESPN lookup failed path=\(path, privacy: .public) lookupDate=\(ESPNSportsDataProvider.dateString(for: lookupDate), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let scoredCandidates = Array(candidatesByID.values)
            .filter { $0.confidence >= 35 }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return abs(lhs.gameDate.timeIntervalSince(date)) < abs(rhs.gameDate.timeIntervalSince(date))
                }
                return lhs.confidence > rhs.confidence
            }
        if let best = scoredCandidates.first {
            sportsLookupLogger.info("Best ESPN match id=\(best.espnEventID, privacy: .public) title=\(best.title, privacy: .public) confidence=\(best.confidence, privacy: .public)")
        } else {
            let bestRejected = candidatesByID.values.max { lhs, rhs in lhs.confidence < rhs.confidence }
            sportsLookupLogger.warning("No ESPN candidates above threshold. total=\(candidatesByID.count, privacy: .public) bestRejected=\(bestRejected?.title ?? "none", privacy: .public) confidence=\(bestRejected?.confidence ?? 0, privacy: .public)")
        }
        if scoredCandidates.isEmpty, let firstError = lookupErrors.first, lookupErrors.count == sportPaths.count * dates.count {
            throw firstError
        }

        return scoredCandidates
    }

    private func lookupDates(for date: Date) -> [Date] {
        let calendar = Calendar.current
        return [
            date,
            calendar.date(byAdding: .day, value: -1, to: date),
            calendar.date(byAdding: .day, value: 1, to: date)
        ].compactMap { $0 }
    }

    private func betterCandidate(_ lhs: SportsGameMatch, _ rhs: SportsGameMatch, targetDate: Date) -> SportsGameMatch {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence ? lhs : rhs
        }

        return abs(lhs.gameDate.timeIntervalSince(targetDate)) <= abs(rhs.gameDate.timeIntervalSince(targetDate)) ? lhs : rhs
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
            return text.contains("women") || text.contains("womens") ? ["basketball/womens-college-basketball", "basketball/wnba", "basketball/mens-college-basketball", "basketball/nba"] : ["basketball/mens-college-basketball", "basketball/nba", "basketball/womens-college-basketball", "basketball/wnba"]
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
            "basketball/womens-college-basketball",
            "baseball/mlb",
            "football/nfl",
            "basketball/nba",
            "basketball/wnba",
            "hockey/nhl",
            "hockey/mens-college-hockey",
            "soccer/usa.1",
            "soccer/eng.1"
        ]
    }

    private func score(_ game: SportsGameMatch, against draft: ImportedEventDraft) -> Int {
        var score = 0
        let searchText = [
            draft.title,
            draft.sourceText,
            draft.participants.joined(separator: " "),
            draft.ticketDetails?.originalTitle ?? "",
            draft.ticketDetails?.originalVenue ?? ""
        ].joined(separator: " ")
        let title = normalized(draft.title)
        let source = normalized(searchText)
        let venue = normalized(draft.venue)
        let haystack = [title, source].joined(separator: " ")

        if draft.date.map({ Calendar.current.isDate($0, inSameDayAs: game.gameDate) }) == true {
            score += 30
        }

        let homeTokens = teamTokens(game.homeTeam)
        let awayTokens = teamTokens(game.awayTeam)
        let homeHits = tokenHits(homeTokens, in: haystack)
        let awayHits = tokenHits(awayTokens, in: haystack)
        if homeHits > 0 { score += 25 + min(homeHits * 4, 12) }
        if awayHits > 0 { score += 25 + min(awayHits * 4, 12) }

        if let abbreviation = game.homeTeam.abbreviation, tokenHits([normalized(abbreviation)], in: haystack) > 0 {
            score += 18
        }
        if let abbreviation = game.awayTeam.abbreviation, tokenHits([normalized(abbreviation)], in: haystack) > 0 {
            score += 18
        }

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
            } else if delta < 60 * 60 * 14 {
                score += 6
            } else if delta < 60 * 60 * 30 {
                score += 3
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
        let ignored: Set<String> = ["the", "at", "vs", "and", "of", "for", "university", "college", "mens", "womens"]
        return normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !ignored.contains($0) }
    }

    private func teamTokens(_ team: SportsTeamInfo) -> [String] {
        var tokens = significantTokens(team.name)
        if let abbreviation = team.abbreviation {
            let normalizedAbbreviation = normalized(abbreviation)
            if !normalizedAbbreviation.isEmpty {
                tokens.append(normalizedAbbreviation)
            }
        }
        tokens.append(contentsOf: mascotAliases(for: tokens))
        return Array(Set(tokens))
    }

    private func mascotAliases(for tokens: [String]) -> [String] {
        tokens.flatMap { token -> [String] in
            guard token.count > 3 else { return [] }
            if token.hasSuffix("ies") {
                return [String(token.dropLast(3)) + "y"]
            }
            if token.hasSuffix("s") {
                return [String(token.dropLast())]
            }
            return [token + "s"]
        }
    }

    private func tokenHits(_ tokens: [String], in text: String) -> Int {
        tokens.filter { text.contains($0) }.count
    }
}

private struct ESPNScoreboard: Decodable {
    var events: [ESPNEvent]

    enum CodingKeys: String, CodingKey {
        case events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([ESPNEvent].self, forKey: .events) ?? []
    }
}

private struct ESPNEvent: Decodable {
    var id: String
    var date: String?
    var name: String?
    var competitions: [ESPNCompetition]
    var links: [ESPNLink]?
    var status: ESPNStatus?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case name
        case competitions
        case links
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        competitions = try container.decodeIfPresent([ESPNCompetition].self, forKey: .competitions) ?? []
        links = try container.decodeIfPresent([ESPNLink].self, forKey: .links)
        status = try container.decodeIfPresent(ESPNStatus.self, forKey: .status)
    }
}

private struct ESPNCompetition: Decodable {
    var date: String?
    var venue: ESPNVenue?
    var competitors: [ESPNCompetitor]
    var status: ESPNStatus?

    enum CodingKeys: String, CodingKey {
        case date
        case venue
        case competitors
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        venue = try container.decodeIfPresent(ESPNVenue.self, forKey: .venue)
        competitors = try container.decodeIfPresent([ESPNCompetitor].self, forKey: .competitors) ?? []
        status = try container.decodeIfPresent(ESPNStatus.self, forKey: .status)
    }
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
    var team: ESPNTeam?

    var sportsTeam: SportsTeamInfo {
        SportsTeamInfo(
            id: id ?? team?.id ?? UUID().uuidString,
            name: team?.displayName ?? team?.name ?? team?.location ?? "Team",
            abbreviation: team?.abbreviation,
            logoURL: team?.logoURL
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
    var logos: [ESPNLogo]?

    var logoURL: URL? {
        logo.flatMap(URL.init(string:))
            ?? logos?.first(where: { $0.href != nil })?.href
    }
}

private struct ESPNLogo: Decodable {
    var href: URL?
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
