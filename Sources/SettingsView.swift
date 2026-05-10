import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Simple preferences with @AppStorage
    @AppStorage("currentNight") private var currentNight: Int = 1
    @AppStorage("checkInDurationLimit") private var checkInDurationLimit: Int = 120
    
    // SwiftData night configurations
    @Query(sort: \NightConfiguration.nightNumber) private var nightConfigurations: [NightConfiguration]
    
    // Local state
    @State private var showResetConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var selectedNight: NightConfiguration?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black
                    .ignoresSafeArea()
                
                Form {
                    // MARK: - Current Night Section
                    Section {
                        Stepper(value: $currentNight, in: 1...7) {
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundStyle(.indigo)
                                Text("Night \(currentNight)")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Current night number")
                        .accessibilityValue("\(currentNight)")
                        .accessibilityHint("Adjust from 1 to 7")
                    } header: {
                        Text("Current Night")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("Override the current night manually. Normally this advances automatically after each successful session.")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - Check-In Duration Section
                    Section {
                        Stepper(value: $checkInDurationLimit, in: 60...180, step: 15) {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(.teal)
                                Text("\(checkInDurationLimit) seconds")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Check-in duration limit")
                        .accessibilityValue("\(checkInDurationLimit) seconds")
                        .accessibilityHint("Adjust from 60 to 180 seconds")
                    } header: {
                        Text("Check-In Duration Limit")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("Maximum recommended time to stay in the room during a check-in. The timer will warn you when approaching this limit.")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - Night Intervals Section
                    Section {
                        ForEach(effectiveNightConfigurations, id: \.nightNumber) { config in
                            NavigationLink {
                                NightIntervalEditView(
                                    nightNumber: config.nightNumber,
                                    configuration: nightConfigurations.first { $0.nightNumber == config.nightNumber }
                                )
                            } label: {
                                HStack {
                                    NightBadge(nightNumber: config.nightNumber)
                                    
                                    Spacer()
                                    
                                    Text(formatIntervals(config))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        Text("Intervals Per Night")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("Customize wait times between check-ins for each night. Tap a night to edit its intervals.")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - Reset Section
                    Section {
                        Button {
                            showResetConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(.orange)
                                Text("Reset to Ferber Defaults")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Reset intervals to Ferber defaults")
                        .accessibilityHint("Restores all night intervals to the standard Ferber method values")
                    } header: {
                        Text("Reset Intervals")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - Clear History Section
                    Section {
                        Button(role: .destructive) {
                            showClearHistoryConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear All History")
                            }
                        }
                        .accessibilityLabel("Clear all sleep training history")
                        .accessibilityHint("Permanently deletes all session records")
                    } header: {
                        Text("Data")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("This permanently deletes all sleep training session history. This action cannot be undone.")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - About Section
                    Section {
                        HStack {
                            Text("Version")
                                .foregroundColor(.white)
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.gray)
                        }
                        
                        Link(destination: URL(string: "https://en.wikipedia.org/wiki/Ferber_method")!) {
                            HStack {
                                Image(systemName: "book.fill")
                                    .foregroundStyle(.purple)
                                Text("About Ferber Method")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    } header: {
                        Text("About")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .confirmationDialog(
                "Reset to Defaults?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset All Intervals", role: .destructive) {
                    resetToDefaults()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset all night intervals to the standard Ferber method values.")
            }
            .confirmationDialog(
                "Clear All History?",
                isPresented: $showClearHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Sessions", role: .destructive) {
                    clearAllHistory()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all sleep training session data. This cannot be undone.")
            }
            .onAppear {
                ensureNightConfigurationsExist()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Returns effective configurations (from SwiftData or defaults)
    private var effectiveNightConfigurations: [NightConfiguration] {
        if nightConfigurations.isEmpty {
            return NightConfiguration.defaultConfigurations()
        }
        return Array(nightConfigurations)
    }
    
    /// Format intervals for display (e.g., "3, 5, 10, 10+ min")
    private func formatIntervals(_ config: NightConfiguration) -> String {
        let intervals = config.intervals
        return intervals.dropLast().map { "\($0)" }.joined(separator: ", ") + ", \(intervals.last ?? 0)+ min"
    }
    
    /// Ensure night configurations exist in SwiftData
    private func ensureNightConfigurationsExist() {
        guard nightConfigurations.isEmpty else { return }
        
        for config in NightConfiguration.defaultConfigurations() {
            modelContext.insert(config)
        }
        
        try? modelContext.save()
    }
    
    /// Reset all intervals to Ferber defaults
    private func resetToDefaults() {
        // Delete existing configurations
        for config in nightConfigurations {
            modelContext.delete(config)
        }
        
        // Insert fresh defaults
        for config in NightConfiguration.defaultConfigurations() {
            modelContext.insert(config)
        }
        
        try? modelContext.save()
    }
    
    /// Clear all session history
    private func clearAllHistory() {
        // Fetch and delete all sessions (CheckIns are cascade deleted)
        let descriptor = FetchDescriptor<SleepSession>()
        if let sessions = try? modelContext.fetch(descriptor) {
            for session in sessions {
                modelContext.delete(session)
            }
        }
        
        // Reset current night
        currentNight = 1
        
        try? modelContext.save()
    }
}

// MARK: - Night Badge

struct NightBadge: View {
    let nightNumber: Int
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
            
            VStack(spacing: -2) {
                Text("N")
                    .font(.system(size: 8, weight: .medium))
                Text("\(nightNumber)")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
        }
    }
}

// MARK: - Night Interval Edit View

struct NightIntervalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let nightNumber: Int
    var configuration: NightConfiguration?
    
    // Editable intervals in minutes
    @State private var firstInterval: Int = 3
    @State private var secondInterval: Int = 5
    @State private var thirdInterval: Int = 10
    @State private var subsequentInterval: Int = 10
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            Form {
                Section {
                    IntervalStepper(
                        label: "1st Check-In",
                        value: $firstInterval,
                        range: 1...30
                    )
                    
                    IntervalStepper(
                        label: "2nd Check-In",
                        value: $secondInterval,
                        range: 1...45
                    )
                    
                    IntervalStepper(
                        label: "3rd Check-In",
                        value: $thirdInterval,
                        range: 1...60
                    )
                    
                    IntervalStepper(
                        label: "Subsequent",
                        value: $subsequentInterval,
                        range: 1...60
                    )
                } header: {
                    Text("Wait Times (minutes)")
                        .foregroundColor(.gray)
                } footer: {
                    Text("Set the wait time before each check-in. The subsequent interval is used for all check-ins after the third.")
                        .foregroundColor(.gray)
                }
                .listRowBackground(Color(white: 0.12))
                
                Section {
                    // Visual preview of intervals
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            let interval = [firstInterval, secondInterval, thirdInterval, subsequentInterval][index]
                            let isLast = index == 3
                            
                            HStack(spacing: 4) {
                                Text("\(interval)")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                if isLast {
                                    Text("+")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            if index < 3 {
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                        .foregroundColor(.gray)
                } footer: {
                    Text("Shows the progression of wait times in minutes.")
                        .foregroundColor(.gray)
                }
                .listRowBackground(Color(white: 0.12))
                
                Section {
                    Button {
                        resetToFerberDefault()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.orange)
                            Text("Reset Night \(nightNumber) to Default")
                                .foregroundColor(.white)
                        }
                    }
                } header: {
                    Text("Reset")
                        .foregroundColor(.gray)
                }
                .listRowBackground(Color(white: 0.12))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Night \(nightNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveConfiguration()
                    dismiss()
                }
                .foregroundColor(.blue)
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            loadConfiguration()
        }
    }
    
    // MARK: - Methods
    
    private func loadConfiguration() {
        if let config = configuration {
            firstInterval = config.firstInterval
            secondInterval = config.secondInterval
            thirdInterval = config.thirdInterval
            subsequentInterval = config.subsequentInterval
        } else {
            let defaults = NightConfiguration.defaultIntervals(for: nightNumber)
            firstInterval = defaults[0]
            secondInterval = defaults[1]
            thirdInterval = defaults[2]
            subsequentInterval = defaults[3]
        }
    }
    
    private func resetToFerberDefault() {
        let defaults = NightConfiguration.defaultIntervals(for: nightNumber)
        firstInterval = defaults[0]
        secondInterval = defaults[1]
        thirdInterval = defaults[2]
        subsequentInterval = defaults[3]
    }
    
    private func saveConfiguration() {
        if let config = configuration {
            // Update existing configuration
            config.firstInterval = firstInterval
            config.secondInterval = secondInterval
            config.thirdInterval = thirdInterval
            config.subsequentInterval = subsequentInterval
        } else {
            // Create new configuration
            let newConfig = NightConfiguration(
                nightNumber: nightNumber,
                firstInterval: firstInterval,
                secondInterval: secondInterval,
                thirdInterval: thirdInterval,
                subsequentInterval: subsequentInterval
            )
            modelContext.insert(newConfig)
        }
        
        try? modelContext.save()
    }
}

// MARK: - Interval Stepper

struct IntervalStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(label)
                    .foregroundColor(.white)
                Spacer()
                Text("\(value) min")
                    .foregroundColor(.purple)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("\(label) interval")
        .accessibilityValue("\(value) minutes")
        .accessibilityHint("Adjust from \(range.lowerBound) to \(range.upperBound) minutes")
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: [SleepSession.self, CheckIn.self, NightConfiguration.self], inMemory: true)
}
