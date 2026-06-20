import SwiftUI
import UIKit

struct ImportReviewFlowView: View {
    @State private var draft: ImportedEventDraft
    @State private var originalDraft: ImportedEventDraft
    @State private var step: ImportReviewStep = .seating
    @State private var sportsLookupStatus: SportsLookupStatus = .idle

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
        switch step {
        case .seating:
            SeatingConfirmationView(
                draft: $draft,
                sportsLookupStatus: sportsLookupStatus,
                previewImageData: previewImageData,
                onCancel: onCancel
            ) {
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

    @MainActor
    private func startSportsLookupIfNeeded() async {
        guard case .idle = sportsLookupStatus else { return }
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                sportsLookupStatus = .candidates(candidates)
            }
        } catch {
            sportsLookupStatus = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
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

    var sportsLookupStatus: SportsLookupStatus
    var previewImageData: Data?
    var onCancel: () -> Void
    var onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                TicketPreviewView(imageData: previewImageData)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 210)
            }

            reviewPanel
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .stubbyGlassButton()
            .tint(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Did We Get This Right?")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(draft.title.isEmpty ? "Imported ticket" : draft.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onContinue()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .stubbyProminentButton()
        }
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Admission", selection: $draft.isGeneralAdmission) {
                Label("Reserved Seat", systemImage: "chair")
                    .tag(false)
                Label("GA / Standing", systemImage: "figure.stand")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.isGeneralAdmission) { _, isGeneralAdmission in
                guard isGeneralAdmission else { return }
                draft.section = ""
                draft.row = ""
                draft.seat = ""
            }

            if draft.isGeneralAdmission {
                Label("No section, row, or seat will be saved.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    SeatField(title: "Section", text: $draft.section)
                    SeatField(title: "Row", text: $draft.row)
                    SeatField(title: "Seat", text: $draft.seat)
                }
            }

            sportsLookupLabel

            Button {
                onContinue()
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .stubbyProminentButton()
        }
        .stubbyPanel(padding: 14)
    }

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
        case .noMatch:
            return "magnifyingglass"
        default:
            return "sportscourt"
        }
    }
}

private struct SeatField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)

            TextField(title, text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct TicketPreviewView: View {
    var imageData: Data?

    var body: some View {
        GeometryReader { proxy in
            previewContent
                .frame(maxWidth: proxy.size.width - 20, maxHeight: proxy.size.height - 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
            VStack(spacing: 12) {
                Image(systemName: "ticket")
                    .font(.system(size: 52))
                Text("No Preview Available")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.75))
        }
    }
}
