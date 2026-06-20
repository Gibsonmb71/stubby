import SwiftUI

struct SportsGameScoreboardView: View {
    var match: SportsGameMatch

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TeamScoreColumn(
                    team: match.awayTeam,
                    score: match.awayScore,
                    alignment: .leading
                )

                VStack(spacing: 6) {
                    Text("at")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image(systemName: "sportscourt")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 42)
                .padding(.top, 26)

                TeamScoreColumn(
                    team: match.homeTeam,
                    score: match.homeScore,
                    alignment: .trailing
                )
            }

            VStack(spacing: 4) {
                Text(match.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(match.gameDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct TeamScoreColumn: View {
    var team: SportsTeamInfo
    var score: Int?
    var alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            TeamLogoView(team: team)
                .frame(width: 78, height: 78)

            Text(scoreText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(height: 38)

            Text(team.abbreviation?.isEmpty == false ? team.abbreviation ?? team.name : team.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var scoreText: String {
        score.map(String.init) ?? "-"
    }
}

private struct TeamLogoView: View {
    var team: SportsTeamInfo

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))

            if let logoURL = team.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    case .failure:
                        fallback
                    case .empty:
                        fallback
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fallback: some View {
        Text(teamInitials)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.accentColor)
    }

    private var teamInitials: String {
        if let abbreviation = team.abbreviation, !abbreviation.isEmpty {
            return String(abbreviation.prefix(3)).uppercased()
        }

        let initials = team.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()

        return initials.isEmpty ? "T" : initials.uppercased()
    }
}
