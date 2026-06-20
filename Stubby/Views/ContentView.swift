import PhotosUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var eventStore: EventStore

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isShowingPhotoPicker = false
    @State private var importedTicket: TicketImportResult?
    @State private var queuedImports: [TicketImportResult] = []
    @State private var importError: ImportErrorMessage?
    @State private var isImporting = false

    private let importService = TicketImportService()

    var body: some View {
        TabView {
            NavigationStack {
                MyEventsView(isImporting: isImporting)
                    .navigationTitle("My Events")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            importButton
                        }
                    }
            }
            .tabItem {
                Label("Events", systemImage: "ticket")
            }

            NavigationStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                    .navigationTitle("Print")
            }
            .tabItem {
                Label("Print", systemImage: "printer")
            }
        }
        .fullScreenCover(item: $importedTicket) { result in
            ImportReviewFlowView(importResult: result) { savedDraft in
                eventStore.add(savedDraft)
                showNextQueuedImport()
            } onCancel: {
                showNextQueuedImport()
            }
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 20,
            matching: .images,
            preferredItemEncoding: .compatible
        )
        .alert(item: $importError) { error in
            Alert(
                title: Text("Import Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: selectedPhotos) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await handlePhotoImport(newItems)
            }
        }
    }

    private var importButton: some View {
        Menu {
            Button {
                isShowingPhotoPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }

            Button {
                isShowingPhotoPicker = true
            } label: {
                Label("Bulk From Photo Library", systemImage: "square.stack")
            }
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .disabled(isImporting)
        .stubbyProminentButton()
    }

    @MainActor
    private func handlePhotoImport(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            selectedPhotos = []
        }

        var importedResults: [TicketImportResult] = []
        var firstError: Error?

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw TicketImportError.unreadableImage
                }
                importedResults.append(try await importService.importTicket(fromImageData: data))
            } catch {
                firstError = firstError ?? error
            }
        }

        if let first = importedResults.first {
            queuedImports.append(contentsOf: importedResults.dropFirst())
            if importedTicket == nil {
                importedTicket = first
            } else {
                queuedImports.insert(first, at: 0)
            }
        } else if let firstError {
            importError = ImportErrorMessage(firstError)
        }
    }

    @MainActor
    private func showNextQueuedImport() {
        if queuedImports.isEmpty {
            importedTicket = nil
        } else {
            importedTicket = queuedImports.removeFirst()
        }
    }
}

struct ImportErrorMessage: Identifiable {
    var id = UUID()
    var message: String

    init(_ error: Error) {
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
