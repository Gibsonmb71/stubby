import SwiftUI

struct ImportReviewFlowView: View {
    @State private var draft: ImportedEventDraft
    @State private var originalDraft: ImportedEventDraft
    @State private var step: ImportReviewStep = .seating
    @State private var sportsLookupStatus: SportsLookupStatus = .idle
    @State private var sportsMatchFeedbackTrigger = false
    @State private var sportsNeedsChoiceFeedbackTrigger = false
    @State private var sportsFailureFeedbackTrigger = false
    @State private var stepFeedbackTrigger = false

    private let previewImageData: Data?
    private let onSave: (ImportedEventDraft) -> Void
    private let onCancel: () -> Void
    private let sportsMatcher = SportsGameMatcher()

    init(
        importResult: TicketImportResult,
        onSave: @escaping (ImportedEventDraft) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: importResult.draft)
        _originalDraft = State(initialValue: importResult.draft)
        previewImageData = importResult.previewImageData
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Group {
            switch step {
            case .seating:
                SeatingConfirmationView(
                    draft: $draft,
                    sportsLookupStatus: sportsLookupStatus,
                    previewImageData: previewImageData,
                    onCancel: onCancel
                ) {
                    stepFeedbackTrigger.toggle()
                    withAnimation(.snappy) {
                        step = .details
                    }
                }
                .task {
                    await startSportsLookupIfNeeded()
                }
            case .details:
                EventEditorView(
                    draft: $draft,
                    originalDraft: originalDraft,
                    sportsLookupStatus: $sportsLookupStatus,
                    onApplySportsMatch: applySportsMatch,
                    onRevertSportsMatch: revertSportsMatch,
                    onSave: onSave
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: sportsMatchFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: sportsNeedsChoiceFeedbackTrigger)
        .sensoryFeedback(.error, trigger: sportsFailureFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: stepFeedbackTrigger)
        .onChange(of: draft.date) { _, newDate in
            guard newDate != nil else { return }
            if case .needsDateYear = sportsLookupStatus {
                sportsLookupStatus = .idle
            }
            Task {
                await startSportsLookupIfNeeded()
            }
        }
    }

    @MainActor
    private func startSportsLookupIfNeeded() async {
        guard sportsLookupStatus.canStartLookup else { return }
        guard draft.dateMissingYear == nil else {
            sportsLookupStatus = .needsDateYear
            return
        }
        guard draft.date != nil else {
            sportsLookupStatus = .noMatch
            return
        }

        sportsLookupStatus = .searching
        do {
            let candidates = try await sportsMatcher.matchCandidates(for: draft)
            guard let best = candidates.first else {
                sportsLookupStatus = .noMatch
                return
            }

            let runnerUp = candidates.dropFirst().first
            if best.confidence >= 80, runnerUp.map({ best.confidence - $0.confidence >= 10 }) != false {
                applySportsMatch(best, nil)
                sportsLookupStatus = .matched(best)
                sportsMatchFeedbackTrigger.toggle()
            } else {
                sportsLookupStatus = .candidates(candidates)
                sportsNeedsChoiceFeedbackTrigger.toggle()
            }
        } catch {
            sportsLookupStatus = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            sportsFailureFeedbackTrigger.toggle()
        }
    }

    @MainActor
    private func applySportsMatch(_ match: SportsGameMatch, _ logoURL: URL?) {
        draft.apply(match, logoURL: logoURL)
        sportsLookupStatus = .matched(match)
    }

    @MainActor
    private func revertSportsMatch() {
        let preservedSeatDetails = (draft.section, draft.row, draft.seat, draft.isGeneralAdmission)
        draft = originalDraft
        draft.section = preservedSeatDetails.0
        draft.row = preservedSeatDetails.1
        draft.seat = preservedSeatDetails.2
        draft.isGeneralAdmission = preservedSeatDetails.3
        sportsLookupStatus = .idle
    }
}

private enum ImportReviewStep {
    case seating
    case details
}

private struct SeatingConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: ImportedEventDraft
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var admissionFeedbackTrigger = false
    @State private var cancelFeedbackTrigger = false
    @State private var yearFeedbackTrigger = false

    var sportsLookupStatus: SportsLookupStatus
    var previewImageData: Data?
    var onCancel: () -> Void
    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    TicketPreviewView(imageData: previewImageData)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 230)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Confirm Seat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        cancelFeedbackTrigger.toggle()
                        onCancel()
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .stubbyGlassButton()
                    .tint(.white)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onContinue()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .stubbyProminentButton()
                    .disabled(needsYearConfirmation)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                seatingPanel
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            .statusBarHidden()
            .onChange(of: draft.isGeneralAdmission) { _, isGeneralAdmission in
                admissionFeedbackTrigger.toggle()
                guard isGeneralAdmission else { return }
                draft.section = ""
                draft.row = ""
                draft.seat = ""
            }
            .sensoryFeedback(.selection, trigger: admissionFeedbackTrigger)
            .sensoryFeedback(.warning, trigger: cancelFeedbackTrigger)
            .sensoryFeedback(.success, trigger: yearFeedbackTrigger)
        }
    }

    private var seatingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Did We Get This Right?")
                    .font(.headline)
                Text(draft.title.isEmpty ? "Imported ticket" : draft.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Admission") {
                    Picker("Admission", selection: $draft.isGeneralAdmission) {
                        Label("Reserved Seat", systemImage: "chair")
                            .tag(false)
                        Label("GA / Standing", systemImage: "figure.stand")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                if needsYearConfirmation, let dateMissingYear = draft.dateMissingYear {
                    YearConfirmationField(
                        dateText: dateMissingYear.displayText,
                        selectedYear: $selectedYear
                    ) {
                        yearFeedbackTrigger.toggle()
                        draft.resolveMissingYear(selectedYear)
                    }
                }

                if draft.isGeneralAdmission {
                    Label("No section, row, or seat will be saved.", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    SeatField(title: "Section", text: $draft.section)
                    SeatField(title: "Row", text: $draft.row)
                    SeatField(title: "Seat", text: $draft.seat)
                }
            }

            Divider()

            HStack {
                sportsLookupLabel
                Spacer()
                Button {
                    onContinue()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .stubbyProminentButton()
                .disabled(needsYearConfirmation)
            }
        }
        .stubbyPanel(padding: 14)
        .foregroundStyle(.primary)
    }

    private var needsYearConfirmation: Bool {
        draft.date == nil && draft.dateMissingYear != nil
    }
}

private struct YearConfirmationField: View {
    var dateText: String
    @Binding var selectedYear: Int
    var onUseYear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Year needed for \(dateText)", systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))

            Stepper(value: $selectedYear, in: 2020...2035) {
                LabeledContent("Year", value: String(selectedYear))
            }

            Button(action: onUseYear) {
                Label("Use \(selectedYear)", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 2)
    }
}

private struct SeatField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 150)
        }
    }
}

private extension SeatingConfirmationView {
    private var sportsLookupLabel: some View {
        HStack(spacing: 10) {
            if case .searching = sportsLookupStatus {
                ProgressView()
            } else {
                Image(systemName: sportsLookupIcon)
                    .foregroundStyle(.secondary)
            }
            Text(sportsLookupStatus.label)
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
        case .needsDateYear:
            return "calendar.badge.exclamationmark"
        case .noMatch:
            return "magnifyingglass"
        default:
            return "sportscourt"
        }
    }
}

private extension SportsLookupStatus {
    var canStartLookup: Bool {
        switch self {
        case .idle, .needsDateYear:
            return true
        default:
            return false
        }
    }
}

private struct TicketPreviewView: View {
    var imageData: Data?

    var body: some View {
        previewContent
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        } else {
            ContentUnavailableView {
                Label("No Preview Available", systemImage: "ticket")
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }
}
