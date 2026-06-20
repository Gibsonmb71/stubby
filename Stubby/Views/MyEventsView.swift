import SwiftUI

struct MyEventsView: View {
    @EnvironmentObject private var eventStore: EventStore
    @State private var deleteFeedbackTrigger = false

    var isImporting: Bool

    var body: some View {
        Group {
            if eventStore.events.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(isImporting ? "Reading Ticket" : "No Events Yet", systemImage: "ticket")
        } description: {
            Text(isImporting ? "Extracting event details locally" : "Import a ticket to start your collection.")
        } actions: {
            if isImporting {
                ProgressView()
            }
        }
    }

    private var eventList: some View {
        List {
            if isImporting {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading ticket")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(eventSections) { section in
                Section(section.title) {
                    ForEach(section.events) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventListRow(event: event)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteFeedbackTrigger.toggle()
                                eventStore.delete(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteFeedbackTrigger.toggle()
                                eventStore.delete(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        delete(offsets, in: section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sensoryFeedback(.warning, trigger: deleteFeedbackTrigger)
    }

    private var eventSections: [EventYearSection] {
        let groupedEvents = Dictionary(grouping: eventStore.events) { event in
            sectionYear(for: event)
        }

        return groupedEvents
            .map { year, events in
                EventYearSection(
                    year: year,
                    title: year.map(String.init) ?? "No Date",
                    events: events.sorted { eventSortDate($0) > eventSortDate($1) }
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.year, rhs.year) {
                case let (lhsYear?, rhsYear?):
                    return lhsYear > rhsYear
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return lhs.title < rhs.title
                }
            }
    }

    private func delete(_ offsets: IndexSet, in section: EventYearSection) {
        deleteFeedbackTrigger.toggle()
        let eventsToDelete = offsets.map { section.events[$0] }
        eventsToDelete.forEach(eventStore.delete)
    }

    private func sectionYear(for event: Event) -> Int? {
        guard let date = event.date else { return nil }
        return Calendar.current.component(.year, from: date)
    }

    private func eventSortDate(_ event: Event) -> Date {
        event.date ?? event.createdAt
    }
}

private struct EventYearSection: Identifiable {
    var year: Int?
    var title: String
    var events: [Event]

    var id: String {
        year.map(String.init) ?? "no-date"
    }
}

private struct EventListRow: View {
    var event: Event

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Label(dateText, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(event.venueSummary, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(event.seatingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageURL = event.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderThumbnail
                case .empty:
                    placeholderThumbnail
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    placeholderThumbnail
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(0.16))
            .overlay {
                Image(systemName: "ticket.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var dateText: String {
        guard let date = event.date else {
            return "Date not set"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
