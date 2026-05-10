import SwiftUI
import SwiftData

@main
struct FerberApp: App {
    init() {
        NotificationManager.shared.registerCategories()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationManager.shared.requestPermission()
                }
        }
        .modelContainer(for: [SleepSession.self, CheckIn.self, NightConfiguration.self])
    }
}
