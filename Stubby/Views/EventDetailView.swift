import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject private var eventStore: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleteFeedbackTrigger = false

    var event: Event

    var body: some View {
        List {
            if let sportsGame = event.sportsGame {
                SportsGameScoreboardView(match: sportsGame)
                    .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 10, trailing: 18))
                    .listRowBackground(Color.clear)
            } else if let imageURL = event.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 10, trailing: 18))
                .listRowBackground(Color.clear)
            }

            Section("Event") {
                DetailRow(title: "Title", value: event.displayTitle)
                DetailRow(title: "Date", value: event.date?.formatted(date: .long, time: .shortened) ?? "Not set")
                DetailRow(title: "Location", value: event.venueSummary)
                if let category = event.category, !category.isEmpty {
                    DetailRow(title: "Category", value: category)
                }
                if !event.participants.isEmpty {
                    DetailRow(title: "Participants", value: event.participants.joined(separator: ", "))
                }
            }

            if let sportsGame = event.sportsGame {
                Section("Game") {
                    DetailRow(title: "ESPN ID", value: sportsGame.espnEventID)
                    DetailRow(title: "Away", value: sportsGame.awayTeam.name)
                    DetailRow(title: "Home", value: sportsGame.homeTeam.name)
                    if let status = sportsGame.status {
                        DetailRow(title: "Status", value: status)
                    }
                    if let espnURL = sportsGame.espnURL {
                        Link(destination: espnURL) {
                            Label("Open ESPN Event", systemImage: "safari")
                        }
                    }
                }
            }

            Section("Seat") {
                DetailRow(title: "Admission", value: event.isGeneralAdmission ? "General Admission" : "Reserved")
                DetailRow(title: "Section", value: event.section.isEmpty ? "Not set" : event.section)
                DetailRow(title: "Row", value: event.row.isEmpty ? "Not set" : event.row)
                DetailRow(title: "Seat", value: event.seat.isEmpty ? "Not set" : event.seat)
            }

            if !event.notes.isEmpty {
                Section("Notes") {
                    Text(event.notes)
                }
            }

            if !event.barcodePayloads.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(event.barcodePayloads, id: \.self) { payload in
                            Text(payload)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    } label: {
                        Label("Show Barcode", systemImage: "barcode.viewfinder")
                    }
                }
            }

            if !event.sourceText.isEmpty {
                Section("OCR Text") {
                    Text(event.sourceText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(event.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    deleteFeedbackTrigger.toggle()
                    eventStore.delete(event)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sensoryFeedback(.warning, trigger: deleteFeedbackTrigger)
    }
}

private struct DetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
