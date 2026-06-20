import SwiftUI

struct EventCardView: View {
    var event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 8) {
                Text(event.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(dateText, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(event.venueSummary, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(event.seatingSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .lineLimit(1)
            }
        }
        .stubbyPanel(padding: 12)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageURL = event.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderArtwork
                case .empty:
                    ZStack {
                        placeholderArtwork
                        ProgressView()
                    }
                @unknown default:
                    placeholderArtwork
                }
            }
            .frame(height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderArtwork
                .frame(height: 142)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var placeholderArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.82),
                    Color.cyan.opacity(0.55),
                    Color(.systemGray5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "ticket.fill")
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.84))
                .padding(14)
        }
    }

    private var dateText: String {
        guard let date = event.date else {
            return "Date not set"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
