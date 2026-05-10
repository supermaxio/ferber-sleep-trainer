import SwiftUI
import SwiftData

@main
struct FerberApp: App {
    
    init() {
        // Register notification categories on app launch
        NotificationManager.shared.registerCategories()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request notification permission on first launch
                    await NotificationManager.shared.requestPermission()
                }
        }
        .modelContainer(for: [SleepSession.self, CheckIn.self, NightConfiguration.self])
    }
}
