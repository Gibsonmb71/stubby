import SwiftUI

@main
struct StubbyApp: App {
    @StateObject private var eventStore = EventStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventStore)
        }
    }
}
