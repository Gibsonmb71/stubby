import CloudKit
import Foundation

@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [Event] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Stubby", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("events.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    func add(_ draft: ImportedEventDraft) {
        events.insert(draft.makeEvent(), at: 0)
        persist()
    }

    func delete(_ event: Event) {
        events.removeAll { $0.id == event.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        events.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            events = []
            return
        }

        do {
            events = try decoder.decode([Event].self, from: data)
                .sorted { lhs, rhs in
                    (lhs.date ?? lhs.createdAt) > (rhs.date ?? rhs.createdAt)
                }
        } catch {
            events = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: [.atomic])
            Task {
                await mirrorToICloudIfAvailable()
            }
        } catch {
            assertionFailure("Unable to save events: \(error.localizedDescription)")
        }
    }

    private func mirrorToICloudIfAvailable() async {
        let container = CKContainer(identifier: "iCloud.com.gibsonbell.stubby")
        guard (try? await container.accountStatus()) == .available else { return }
        let cloudDatabase = container.privateCloudDatabase

        for event in events {
            let recordID = CKRecord.ID(recordName: event.id.uuidString)
            let record = CKRecord(recordType: "StubbyEvent", recordID: recordID)
            record["title"] = event.title as CKRecordValue
            record["venue"] = event.venue as CKRecordValue
            record["section"] = event.section as CKRecordValue
            record["row"] = event.row as CKRecordValue
            record["seat"] = event.seat as CKRecordValue
            record["isGeneralAdmission"] = event.isGeneralAdmission as CKRecordValue
            record["notes"] = event.notes as CKRecordValue
            record["createdAt"] = event.createdAt as CKRecordValue
            record["updatedAt"] = event.updatedAt as CKRecordValue
            if let date = event.date {
                record["date"] = date as CKRecordValue
            }
            if let imageURL = event.imageURL {
                record["imageURL"] = imageURL.absoluteString as CKRecordValue
            }
            if let sportsGame = event.sportsGame {
                record["espnEventID"] = sportsGame.espnEventID as CKRecordValue
                record["homeTeam"] = sportsGame.homeTeam.name as CKRecordValue
                record["awayTeam"] = sportsGame.awayTeam.name as CKRecordValue
                record["scoreSummary"] = (sportsGame.scoreSummary ?? "") as CKRecordValue
            }

            _ = try? await cloudDatabase.save(record)
        }
    }
}
