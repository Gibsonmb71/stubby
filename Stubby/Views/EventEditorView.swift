import MapKit
import SwiftUI

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var draft: ImportedEventDraft
    @Binding private var sportsLookupStatus: SportsLookupStatus
    @State private var hasDate: Bool
    @State private var eventDate: Date
    @State private var isMatchingLocation = false
    @State private var locationMatch: AppleMapsLocationMatch?
    @State private var locationMatchMessage: String?
    @State private var locationMatchError: String?
    @State private var lastLocationMatchQuery = ""
    @State private var isShowingBarcodes = false

    private let originalDraft: ImportedEventDraft
    private let onApplySportsMatch: (SportsGameMatch, URL?) -> Void
    private let onRevertSportsMatch: () -> Void
    private let onSave: (ImportedEventDraft) -> Void
    private let locationMatcher = AppleMapsLocationMatcher()

    init(
        draft: Binding<ImportedEventDraft>,
        originalDraft: ImportedEventDraft,
        sportsLookupStatus: Binding<SportsLookupStatus>,
        onApplySportsMatch: @escaping (SportsGameMatch, URL?) -> Void,
        onRevertSportsMatch: @escaping () -> Void,
        onSave: @escaping (ImportedEventDraft) -> Void
    ) {
        _draft = draft
        self.originalDraft = originalDraft
        _sportsLookupStatus = sportsLookupStatus
        _hasDate = State(initialValue: draft.wrappedValue.date != nil)
        _eventDate = State(initialValue: draft.wrappedValue.date ?? Date())
        self.onApplySportsMatch = onApplySportsMatch
        self.onRevertSportsMatch = onRevertSportsMatch
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ESPN Lookup") {
                    sportsLookupControls
                }

                Section("Event Details") {
                    TextField("Title", text: $draft.title)
                        .textInputAutocapitalization(.words)
                    Toggle("Date & Time", isOn: $hasDate)
                    if hasDate {
                        DatePicker("When", selection: $eventDate)
                    }
                    TextField("Location", text: $draft.venue)
                        .textInputAutocapitalization(.words)
                        .onSubmit {
                            Task {
                                await matchLocation(applyExactMatch: false)
                            }
                        }
                    locationMatchControls
                }

                if draft.sportsGame != nil || draft.imageURL != nil {
                    Section("Artwork") {
                        logoPicker
                        imagePreview
                    }
                }

                Section("Seat Details") {
                    Toggle("General Admission / Standing Room", isOn: $draft.isGeneralAdmission)
                    TextField("Section", text: $draft.section)
                        .textInputAutocapitalization(.characters)
                        .disabled(draft.isGeneralAdmission)
                    TextField("Row", text: $draft.row)
                        .textInputAutocapitalization(.characters)
                        .disabled(draft.isGeneralAdmission)
                    TextField("Seat", text: $draft.seat)
                        .textInputAutocapitalization(.characters)
                        .disabled(draft.isGeneralAdmission)
                }

                Section("Other Details") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                    if let category = draft.category, !category.isEmpty {
                        LabeledContent("Category", value: category)
                    }
                    if !draft.participants.isEmpty {
                        LabeledContent("Participants", value: draft.participants.joined(separator: ", "))
                    }
                    if !draft.barcodePayloads.isEmpty {
                        DisclosureGroup(isExpanded: $isShowingBarcodes) {
                            ForEach(draft.barcodePayloads, id: \.self) { payload in
                                Text(payload)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                            }
                        } label: {
                            Label("Show Barcode", systemImage: "barcode.viewfinder")
                        }
                    }
                }

                if !draft.sourceText.isEmpty {
                    Section("OCR Text") {
                        Text(draft.sourceText)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Review Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: draft.isGeneralAdmission) { _, isGeneralAdmission in
                guard isGeneralAdmission else { return }
                draft.section = ""
                draft.row = ""
                draft.seat = ""
            }
            .onChange(of: draft.venue) { _, newValue in
                guard normalizedLocationName(newValue) != normalizedLocationName(lastLocationMatchQuery) else { return }
                locationMatch = nil
                locationMatchMessage = nil
                locationMatchError = nil
            }
            .onChange(of: draft.date) { _, newDate in
                if let newDate {
                    hasDate = true
                    eventDate = newDate
                }
            }
            .task {
                guard draft.sportsGame == nil else { return }
                await matchLocationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var sportsLookupControls: some View {
        HStack(spacing: 10) {
            if case .searching = sportsLookupStatus {
                ProgressView()
            } else {
                Image(systemName: sportsLookupIcon)
                    .foregroundStyle(.secondary)
            }
            Text(sportsLookupStatus.label)
                .foregroundStyle(.primary)
        }

        switch sportsLookupStatus {
        case .matched(let match):
            SportsMatchSummary(match: match)
            Button(role: .destructive) {
                onRevertSportsMatch()
            } label: {
                Label("Revert ESPN Details", systemImage: "arrow.uturn.backward")
            }

        case .candidates(let candidates):
            ForEach(candidates.prefix(5)) { match in
                Button {
                    onApplySportsMatch(match, selectedLogoURL(for: match))
                    hasDate = true
                    eventDate = match.gameDate
                } label: {
                    SportsMatchCandidateRow(match: match)
                }
            }

        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)

        case .noMatch:
            Text("No matching ESPN scoreboard event was found for the imported title and date.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .idle:
            Text("Lookup starts from the seat confirmation screen when the ticket has a date.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .searching:
            Text("Using the event date, team names, and venue from the ticket.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sportsLookupIcon: String {
        switch sportsLookupStatus {
        case .matched:
            return "checkmark.seal"
        case .candidates:
            return "list.bullet"
        case .failed:
            return "exclamationmark.triangle"
        case .noMatch:
            return "magnifyingglass"
        default:
            return "sportscourt"
        }
    }

    @ViewBuilder
    private var logoPicker: some View {
        if let game = draft.sportsGame {
            Picker("Logo", selection: Binding(
                get: { draft.imageURL?.absoluteString ?? "" },
                set: { newValue in
                    draft.imageURL = newValue.isEmpty ? nil : URL(string: newValue)
                }
            )) {
                Text("None").tag("")
                if let awayLogo = game.awayTeam.logoURL {
                    Text(game.awayTeam.name).tag(awayLogo.absoluteString)
                }
                if let homeLogo = game.homeTeam.logoURL {
                    Text(game.homeTeam.name).tag(homeLogo.absoluteString)
                }
            }
            .pickerStyle(.inline)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let url = draft.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    imagePlaceholder
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } else {
            imagePlaceholder
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var locationMatchControls: some View {
        if draft.sportsGame != nil {
            if isMatchingLocation {
                HStack {
                    ProgressView()
                    Text("Checking Apple Maps")
                }
                .foregroundStyle(.secondary)
            } else if let locationMatch, !isStaleLocationMatch {
                Button {
                    apply(locationMatch)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Use \(locationMatch.name)", systemImage: "mappin.and.ellipse")
                        if !locationMatch.subtitle.isEmpty {
                            Text(locationMatch.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let locationMatchMessage {
                Label(locationMatchMessage, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await matchLocation(applyExactMatch: false)
                }
            } label: {
                Label("Search Apple Maps Instead", systemImage: "map")
            }
            .disabled(isMatchingLocation || draft.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            if isMatchingLocation {
                HStack {
                    ProgressView()
                    Text("Checking Apple Maps")
                }
                .foregroundStyle(.secondary)
            } else if let locationMatch, !isStaleLocationMatch {
                Button {
                    apply(locationMatch)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Use \(locationMatch.name)", systemImage: "mappin.and.ellipse")
                        if !locationMatch.subtitle.isEmpty {
                            Text(locationMatch.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let locationMatchMessage {
                Label(locationMatchMessage, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await matchLocation(applyExactMatch: false)
                }
            } label: {
                Label("Match Location in Apple Maps", systemImage: "map")
            }
            .disabled(isMatchingLocation || draft.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        if let locationMatchError {
            Text(locationMatchError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @MainActor
    private func matchLocationIfNeeded() async {
        guard locationMatch == nil, locationMatchMessage == nil else { return }
        guard !draft.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await matchLocation(applyExactMatch: true)
    }

    @MainActor
    private func matchLocation(applyExactMatch: Bool) async {
        let query = draft.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isMatchingLocation = true
        locationMatch = nil
        locationMatchMessage = nil
        locationMatchError = nil
        defer { isMatchingLocation = false }

        do {
            lastLocationMatchQuery = query
            guard let match = try await locationMatcher.match(query: query) else {
                locationMatchError = "No Apple Maps match found."
                return
            }

            if applyExactMatch, normalizedLocationName(match.name) == normalizedLocationName(query) {
                draft.venue = match.name
                lastLocationMatchQuery = match.name
                locationMatchMessage = "Matched in Apple Maps."
            } else {
                locationMatch = match
            }
        } catch {
            locationMatchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var isStaleLocationMatch: Bool {
        normalizedLocationName(lastLocationMatchQuery) != normalizedLocationName(draft.venue)
    }

    private func apply(_ match: AppleMapsLocationMatch) {
        draft.venue = match.name
        lastLocationMatchQuery = match.name
        locationMatch = nil
        locationMatchError = nil
        locationMatchMessage = "Matched in Apple Maps."
    }

    private func save() {
        var savedDraft = draft
        savedDraft.date = hasDate ? eventDate : nil
        if savedDraft.isGeneralAdmission {
            savedDraft.section = ""
            savedDraft.row = ""
            savedDraft.seat = ""
        }
        onSave(savedDraft)
        dismiss()
    }

    private func selectedLogoURL(for match: SportsGameMatch) -> URL? {
        draft.imageURL ?? match.homeTeam.logoURL ?? match.awayTeam.logoURL
    }
}

private struct SportsMatchSummary: View {
    var match: SportsGameMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(match.title)
                .font(.headline)
            Label(match.gameDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            if let venue = match.venue {
                Label(venue, systemImage: "mappin.and.ellipse")
            }
            if let score = match.scoreSummary {
                Label(score, systemImage: "sportscourt")
            }
            if let status = match.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct SportsMatchCandidateRow: View {
    var match: SportsGameMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(match.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(match.confidence)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(match.gameDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let venue = match.venue {
                Text(venue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppleMapsLocationMatch: Equatable {
    var name: String
    var subtitle: String
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: AppleMapsLocationMatch, rhs: AppleMapsLocationMatch) -> Bool {
        lhs.name == rhs.name &&
            lhs.subtitle == rhs.subtitle &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

private struct AppleMapsLocationMatcher {
    func match(query: String) async throws -> AppleMapsLocationMatch? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        request.resultTypes = [.pointOfInterest, .address]

        let response = try await MKLocalSearch(request: request).start()
        guard let mapItem = response.mapItems.first else { return nil }

        return AppleMapsLocationMatch(
            name: mapItem.name ?? trimmedQuery,
            subtitle: formattedAddress(for: mapItem),
            coordinate: mapItem.location.coordinate
        )
    }

    private func formattedAddress(for mapItem: MKMapItem) -> String {
        mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? mapItem.address?.shortAddress
            ?? mapItem.addressRepresentations?.cityWithContext
            ?? ""
    }
}

private func normalizedLocationName(_ value: String) -> String {
    value
        .lowercased()
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
}
