import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("householdCode") private var householdCode: String = ""
    @State private var lastAutoSyncDate: Date?
    @State private var isAutoSyncing = false
    
    var body: some View {
        SessionView()
            .task {
                await syncHouseholdIfConfigured()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await syncHouseholdIfConfigured()
                }
            }
            .onChange(of: householdCode) { _, _ in
                Task {
                    await syncHouseholdIfConfigured(force: true)
                }
            }
    }
    
    private func syncHouseholdIfConfigured(force: Bool = false) async {
        let code = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        guard !isAutoSyncing else { return }
        
        if !force, let lastAutoSyncDate, Date().timeIntervalSince(lastAutoSyncDate) < 30 {
            return
        }
        
        isAutoSyncing = true
        defer {
            isAutoSyncing = false
            lastAutoSyncDate = Date()
        }
        
        _ = try? await CloudKitSyncManager.shared.sync(
            householdCode: code,
            modelContext: modelContext
        )
    }
}

#Preview {
    ContentView()
}
