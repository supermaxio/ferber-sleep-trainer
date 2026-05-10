import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Simple preferences with @AppStorage
    @AppStorage("currentNight") private var currentNight: Int = 1
    @AppStorage("checkInDurationLimit") private var checkInDurationLimit: Int = 2
    @AppStorage("householdCode") private var householdCode: String = ""
    
    // SwiftData night configurations
    @Query(sort: \NightConfiguration.nightNumber) private var nightConfigurations: [NightConfiguration]
    
    // Local state
    @State private var showResetConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showImportHistory = false
    @State private var showTemplateExporter = false
    @State private var showImportResult = false
    @State private var isSyncingHousehold = false
    @State private var selectedNight: NightConfiguration?
    @State private var importResultTitle = ""
    @State private var importResultMessage = ""
    
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
                        Stepper(value: $checkInDurationLimit, in: 1...40) {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(.teal)
                                Text("\(checkInDurationLimit) minute\(checkInDurationLimit == 1 ? "" : "s")")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Check-in duration limit")
                        .accessibilityValue("\(checkInDurationLimit) minute\(checkInDurationLimit == 1 ? "" : "s")")
                        .accessibilityHint("Adjust from 1 to 40 minutes")
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
                    
                    // MARK: - Household Sync Section
                    Section {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.indigo)
                            TextField("Household code", text: $householdCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .monospaced()
                        }
                        
                        Button {
                            createHouseholdCode()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                                Text(householdCode.isEmpty ? "Create Household Code" : "Create New Household Code")
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Button {
                            syncHousehold()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.teal)
                                Text(isSyncingHousehold ? "Syncing..." : "Sync Household Data")
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(isSyncingHousehold || householdCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("Household Sync")
                            .foregroundColor(.gray)
                    } footer: {
                        Text("Use the same household code on both phones, then sync. This uses iCloud CloudKit and requires both phones to be signed into iCloud.")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.12))
                    
                    // MARK: - Clear History Section
                    Section {
                        Button {
                            showTemplateExporter = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundStyle(.blue)
                                Text("Save Import Template")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Save history import template")
                        
                        Button {
                            showImportHistory = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down.on.square")
                                    .foregroundStyle(.teal)
                                Text("Import History CSV")
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Import history from CSV")
                        
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
                        Text("Save the template, fill it in, then import it from Files. Check-ins use wait minutes/check-in seconds, for example 3/45;5/30. Clearing history permanently deletes all sessions.")
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
            .alert(importResultTitle, isPresented: $showImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
            .fileExporter(
                isPresented: $showTemplateExporter,
                document: HistoryImportTemplateDocument(),
                contentType: .commaSeparatedText,
                defaultFilename: "Comfy-Night-History-Template"
            ) { result in
                if case .failure(let error) = result {
                    showImportResult(
                        title: "Template Export Failed",
                        message: error.localizedDescription
                    )
                }
            }
            .fileImporter(
                isPresented: $showImportHistory,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                importHistory(from: result)
            }
            .onAppear {
                migrateCheckInDurationLimitToMinutes()
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
    
    /// Convert older saved second-based values to minutes.
    private func migrateCheckInDurationLimitToMinutes() {
        if checkInDurationLimit > 40 {
            checkInDurationLimit = min(max(checkInDurationLimit / 60, 1), 40)
        }
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
        LocalSessionStore.clear()
        UserDefaults.standard.removeObject(forKey: "recentSessionSummariesJSON")
        
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
    
    private func createHouseholdCode() {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        householdCode = String((0..<8).compactMap { _ in characters.randomElement() })
    }
    
    private func syncHousehold() {
        let code = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        householdCode = code
        isSyncingHousehold = true
        
        Task {
            do {
                let result = try await CloudKitSyncManager.shared.sync(
                    householdCode: code,
                    modelContext: modelContext
                )
                showImportResult(
                    title: "Sync Complete",
                    message: "Uploaded \(result.uploadedCount) session\(result.uploadedCount == 1 ? "" : "s") and imported \(result.importedCount) session\(result.importedCount == 1 ? "" : "s")."
                )
            } catch {
                showImportResult(
                    title: "Sync Failed",
                    message: error.localizedDescription
                )
            }
            
            isSyncingHousehold = false
        }
    }
    
    private func importHistory(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let csv = try String(contentsOf: url, encoding: .utf8)
            let importedSessions = try HistoryCSVImporter.importSessions(from: csv)
            
            for session in importedSessions {
                modelContext.insert(session)
            }
            
            try modelContext.save()
            syncHouseholdSilentlyIfConfigured()
            showImportResult(
                title: "Import Complete",
                message: "Imported \(importedSessions.count) session\(importedSessions.count == 1 ? "" : "s")."
            )
        } catch {
            showImportResult(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }
    
    private func showImportResult(title: String, message: String) {
        importResultTitle = title
        importResultMessage = message
        showImportResult = true
    }
    
    private func syncHouseholdSilentlyIfConfigured() {
        let code = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        
        Task {
            try? await CloudKitSyncManager.shared.sync(
                householdCode: code,
                modelContext: modelContext
            )
        }
    }
}

struct HistoryImportTemplateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    init() { }
    
    init(configuration: ReadConfiguration) throws { }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(Self.template.utf8))
    }
    
    private static let template = """
    night,date,start_time,end_time,fell_asleep,check_ins
    1,2026-05-10,19:30,20:15,true,3/45;5/30;10/40
    1,2026-05-10,21:00,21:25,true,3/30;5/20
    2,2026-05-11,19:45,20:10,false,5/60;10/45
    
    """
}

enum HistoryCSVImportError: LocalizedError {
    case emptyFile
    case invalidHeader
    case invalidRow(line: Int, reason: String)
    
    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file is empty."
        case .invalidHeader:
            return "The CSV header must be: night,date,start_time,end_time,fell_asleep,check_ins"
        case .invalidRow(let line, let reason):
            return "Line \(line): \(reason)"
        }
    }
}

struct HistoryCSVImporter {
    static func importSessions(from csv: String) throws -> [SleepSession] {
        let rows = parseRows(csv)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        
        guard !rows.isEmpty else {
            throw HistoryCSVImportError.emptyFile
        }
        
        let expectedHeader = ["night", "date", "start_time", "end_time", "fell_asleep", "check_ins"]
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard header == expectedHeader else {
            throw HistoryCSVImportError.invalidHeader
        }
        
        return try rows.dropFirst().enumerated().map { index, row in
            try importSession(from: row, line: index + 2)
        }
    }
    
    private static func importSession(from row: [String], line: Int) throws -> SleepSession {
        guard row.count == 6 else {
            throw HistoryCSVImportError.invalidRow(line: line, reason: "Expected 6 columns.")
        }
        
        let nightText = trimmed(row[0])
        let dateText = trimmed(row[1])
        let startTimeText = trimmed(row[2])
        let endTimeText = trimmed(row[3])
        let fellAsleepText = trimmed(row[4]).lowercased()
        let checkInsText = trimmed(row[5])
        
        guard let nightNumber = Int(nightText), (1...7).contains(nightNumber) else {
            throw HistoryCSVImportError.invalidRow(line: line, reason: "Night must be a number from 1 to 7.")
        }
        
        guard let startTime = makeDate(date: dateText, time: startTimeText) else {
            throw HistoryCSVImportError.invalidRow(line: line, reason: "Date and start_time must use YYYY-MM-DD and HH:mm.")
        }
        
        let explicitEndTime = makeDate(date: dateText, time: endTimeText)
        let fellAsleep = ["true", "yes", "y", "1"].contains(fellAsleepText)
        var cursor = startTime
        var checkIns: [CheckIn] = []
        
        if !checkInsText.isEmpty {
            let entries = checkInsText.split(separator: ";").map(String.init)
            for (entryIndex, entry) in entries.enumerated() {
                let parts = entry.split(separator: "/").map { trimmed(String($0)) }
                guard parts.count == 2,
                      let waitMinutes = Int(parts[0]),
                      let checkInSeconds = Int(parts[1]),
                      waitMinutes >= 0,
                      checkInSeconds >= 0 else {
                    throw HistoryCSVImportError.invalidRow(
                        line: line,
                        reason: "Check-ins must use waitMinutes/checkInSeconds, like 3/45;5/30."
                    )
                }
                
                let checkInStart = cursor.addingTimeInterval(TimeInterval(waitMinutes * 60))
                let checkInEnd = checkInStart.addingTimeInterval(TimeInterval(checkInSeconds))
                let checkIn = CheckIn(
                    timestamp: checkInStart,
                    intervalMinutes: waitMinutes,
                    checkInNumber: entryIndex + 1,
                    endTime: checkInEnd
                )
                checkIns.append(checkIn)
                cursor = checkInEnd
            }
        }
        
        let sessionEndTime = explicitEndTime ?? (fellAsleep ? cursor : nil)
        let session = SleepSession(
            nightNumber: nightNumber,
            date: startTime,
            startTime: startTime,
            endTime: sessionEndTime,
            fellAsleep: fellAsleep,
            checkIns: checkIns
        )
        
        return session
    }
    
    private static func parseRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = csv.makeIterator()
        
        while let character = iterator.next() {
            switch character {
            case "\"":
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        field.append(next)
                    } else {
                        isQuoted = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            case "," where !isQuoted:
                row.append(field)
                field = ""
            case "\n" where !isQuoted:
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            case "\r":
                break
            default:
                field.append(character)
            }
        }
        
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        
        return rows
    }
    
    private static func makeDate(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }
    
    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
