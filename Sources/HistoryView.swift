import SwiftUI
import SwiftData
import Charts

// MARK: - History View
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepSession.date, order: .reverse) private var sessions: [SleepSession]
    
    @State private var selectedTab: HistoryTab = .history
    @State private var localSessions: [SleepSession] = []
    
    enum HistoryTab: String, CaseIterable {
        case history = "History"
        case trends = "Trends"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black
                    .ignoresSafeArea()
                
                if displayedSessions.isEmpty {
                    EmptyStateView()
                } else {
                    VStack(spacing: 0) {
                        // Tab selector
                        Picker("View", selection: $selectedTab) {
                            ForEach(HistoryTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        // Content based on selected tab
                        TabView(selection: $selectedTab) {
                            SessionHistoryList(
                                sessions: displayedSessions,
                                onDelete: deleteSession
                            )
                            .tag(HistoryTab.history)
                            
                            TrendsView(sessions: displayedSessions)
                                .tag(HistoryTab.trends)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("Sleep Training")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .foregroundColor(.blue)
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                refreshLocalSessions()
            }
        }
    }
    
    private var displayedSessions: [SleepSession] {
        localSessions
    }
    
    private func refreshLocalSessions() {
        localSessions = LocalSessionStore.load()
            .map { $0.makeSleepSession() }
            .sorted { $0.date > $1.date }
        print("History JSON fetch found \(localSessions.count) local sessions")
    }
    
    private func deleteSession(_ session: SleepSession) {
        guard let syncID = session.syncID else { return }
        LocalSessionStore.delete(syncID: syncID)
        removeRecentSessionSummary(id: syncID)
        deleteLegacySwiftDataSession(syncID: syncID)
        refreshLocalSessions()
    }
    
    private func removeRecentSessionSummary(id: String) {
        let key = "recentSessionSummariesJSON"
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              var summaries = try? JSONDecoder().decode([RecentSessionSummary].self, from: data) else {
            return
        }
        
        summaries.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(summaries),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: key)
        }
    }
    
    private func deleteLegacySwiftDataSession(syncID: String) {
        let descriptor = FetchDescriptor<SleepSession>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return }
        sessions
            .filter { $0.syncID == syncID }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("No Sessions Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Start your first sleep training session\nto see history and trends here.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

// MARK: - Session History List
struct SessionHistoryList: View {
    let sessions: [SleepSession]
    let onDelete: (SleepSession) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    SessionRowView(session: session, onDelete: onDelete)
                }
            }
            .padding()
        }
    }
}

// MARK: - Session Row View (Expandable)
struct SessionRowView: View {
    let session: SleepSession
    let onDelete: (SleepSession) -> Void
    @State private var isExpanded: Bool = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 16) {
                    // Night badge
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: session.fellAsleep ? [.purple, .blue] : [.gray, .gray.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        VStack(spacing: 0) {
                            Text("Night")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text("\(session.nightNumber)")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                    }
                    
                    // Session info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(session.formattedDate)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if !session.fellAsleep && session.endTime != nil {
                                Text("Cancelled")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.2))
                                    )
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Label(session.formattedStartTime, systemImage: "play.fill")
                            if session.fellAsleep {
                                Label(session.formattedEndTime, systemImage: "moon.zzz.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Stats
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.purple)
                            Text(session.formattedTotalDuration)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        
                        Text("\(session.checkInCount) check-ins")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
            }
            .buttonStyle(.plain)
            
            // Expanded check-ins and actions
            if isExpanded {
                VStack(spacing: 0) {
                    if !session.checkIns.isEmpty {
                        ForEach(sortedCheckIns.indices, id: \.self) { index in
                            let checkIn = sortedCheckIns[index]
                            CheckInRowView(
                                checkIn: checkIn,
                                waitDuration: waitDuration(for: index, in: sortedCheckIns)
                            )
                        }
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.leading, 16)
                }
                .padding(.leading, 40)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) {
                onDelete(session)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the session from this device's history.")
        }
    }
    
    private var sortedCheckIns: [CheckIn] {
        session.checkIns.sorted { $0.checkInNumber < $1.checkInNumber }
    }
    
    private func waitDuration(for index: Int, in checkIns: [CheckIn]) -> TimeInterval {
        let waitStart = index == 0
            ? session.startTime
            : checkIns[index - 1].endTime ?? checkIns[index - 1].timestamp
        return max(0, checkIns[index].timestamp.timeIntervalSince(waitStart))
    }
}

// MARK: - Check-In Row View
struct CheckInRowView: View {
    let checkIn: CheckIn
    let waitDuration: TimeInterval
    
    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 8, height: 8)
            }
            
            // Check-in info
            VStack(alignment: .leading, spacing: 6) {
                Text("Check-in #\(checkIn.checkInNumber)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                
                HStack(spacing: 10) {
                    Label("Waited \(formatDuration(waitDuration))", systemImage: "hourglass")
                    Label("Check-in \(formattedCheckInDuration)", systemImage: "timer")
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .padding(.leading, 16)
    }
    
    private var formattedCheckInDuration: String {
        guard let duration = checkIn.checkInDuration else { return "in progress" }
        return formatDuration(duration)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Night Trend Summary
struct NightTrendSummary: Identifiable {
    let nightNumber: Int
    let sessions: [SleepSession]
    
    var id: Int { nightNumber }
    
    var completedSessions: [SleepSession] {
        sessions.filter { $0.totalDurationToSleep != nil }
    }
    
    var bestCompletedSession: SleepSession? {
        completedSessions.min { ($0.totalDurationToSleep ?? .infinity) < ($1.totalDurationToSleep ?? .infinity) }
    }
    
    var totalCheckIns: Int {
        sessions.reduce(0) { $0 + $1.checkInCount }
    }
    
    var formattedBestDuration: String {
        bestCompletedSession?.formattedTotalDuration ?? "--"
    }
}

// MARK: - Trends View
struct TrendsView: View {
    let sessions: [SleepSession]
    
    private var nightSummaries: [NightTrendSummary] {
        Dictionary(grouping: sessions, by: \.nightNumber)
            .map { nightNumber, sessions in
                NightTrendSummary(
                    nightNumber: nightNumber,
                    sessions: sessions.sorted { $0.startTime < $1.startTime }
                )
            }
            .sorted { $0.nightNumber < $1.nightNumber }
    }
    
    private var completedNightSummaries: [NightTrendSummary] {
        nightSummaries.filter { !$0.completedSessions.isEmpty }
    }
    
    private var totalNights: Int {
        nightSummaries.count
    }
    
    private var successfulNights: Int {
        completedNightSummaries.count
    }
    
    private var averageCheckInDuration: TimeInterval {
        let allCheckIns = sessions.flatMap { $0.checkIns }
        let durations = allCheckIns.compactMap { $0.checkInDuration }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }
    
    private var bestNight: NightTrendSummary? {
        completedNightSummaries.min {
            ($0.bestCompletedSession?.totalDurationToSleep ?? .infinity) <
                ($1.bestCompletedSession?.totalDurationToSleep ?? .infinity)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary Stats
                SummaryStatsView(
                    totalNights: totalNights,
                    successfulNights: successfulNights,
                    averageCheckInDuration: averageCheckInDuration,
                    bestNight: bestNight
                )
                
                // Time to Sleep Chart
                if completedNightSummaries.count >= 2 {
                    ChartCard(title: "Time to Sleep", subtitle: "Best completed session per night") {
                        TimeToSleepChart(nights: completedNightSummaries)
                    }
                    
                    // Check-ins Chart
                    ChartCard(title: "Check-ins per Night", subtitle: "Total check-ins across sessions") {
                        CheckInsChart(nights: nightSummaries)
                    }
                } else {
                    InsufficientDataCard()
                }
            }
            .padding()
        }
    }
}

// MARK: - Summary Stats View
struct SummaryStatsView: View {
    let totalNights: Int
    let successfulNights: Int
    let averageCheckInDuration: TimeInterval
    let bestNight: NightTrendSummary?
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(
                    icon: "moon.stars.fill",
                    title: "Total Nights",
                    value: "\(totalNights)",
                    subtitle: "\(successfulNights) successful",
                    color: .purple
                )
                
                StatCard(
                    icon: "timer",
                    title: "Avg Check-in",
                    value: formatDuration(averageCheckInDuration),
                    color: .blue
                )
            }
            
            if let best = bestNight {
                HStack(spacing: 16) {
                    StatCard(
                        icon: "trophy.fill",
                        title: "Best Night",
                        value: "Night \(best.nightNumber)",
                        subtitle: best.formattedBestDuration,
                        color: .yellow
                    )
                    
                    StatCard(
                        icon: "chart.line.downtrend.xyaxis",
                        title: "Success Rate",
                        value: successRate,
                        color: .green
                    )
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds == 0 {
            return "--"
        }
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds) sec"
    }
    
    private var successRate: String {
        guard totalNights > 0 else { return "--" }
        let rate = Double(successfulNights) / Double(totalNights) * 100
        return "\(Int(rate))%"
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.gray)
            }
            .font(.caption)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
        )
    }
}

// MARK: - Chart Card
struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            content()
                .frame(height: 200)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
        )
    }
}

// MARK: - Time to Sleep Chart
struct TimeToSleepChart: View {
    let nights: [NightTrendSummary]
    
    var body: some View {
        Chart(nights) { night in
            LineMark(
                x: .value("Night", "Night \(night.nightNumber)"),
                y: .value("Minutes", (night.bestCompletedSession?.totalDurationToSleep ?? 0) / 60)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            
            AreaMark(
                x: .value("Night", "Night \(night.nightNumber)"),
                y: .value("Minutes", (night.bestCompletedSession?.totalDurationToSleep ?? 0) / 60)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
            
            PointMark(
                x: .value("Night", "Night \(night.nightNumber)"),
                y: .value("Minutes", (night.bestCompletedSession?.totalDurationToSleep ?? 0) / 60)
            )
            .foregroundStyle(.white)
            .symbolSize(40)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(.gray)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.3))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)m")
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }
}

// MARK: - Check-ins Chart
struct CheckInsChart: View {
    let nights: [NightTrendSummary]
    
    var body: some View {
        Chart(nights) { night in
            BarMark(
                x: .value("Night", "Night \(night.nightNumber)"),
                y: .value("Check-ins", night.totalCheckIns)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(6)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(.gray)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.3))
                AxisValueLabel()
                    .foregroundStyle(.gray)
            }
        }
    }
}

// MARK: - Insufficient Data Card
struct InsufficientDataCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("More Data Needed")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Complete at least 2 nights to see\ntrend charts and progress analysis.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
        )
    }
}

// MARK: - Preview
#Preview("With Sessions") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SleepSession.self, CheckIn.self, configurations: config)
    
    // Add sample data
    let session1 = SleepSession(nightNumber: 1, date: Calendar.current.date(byAdding: .day, value: -6, to: Date())!, fellAsleep: true)
    session1.startTime = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: session1.date)!
    session1.endTime = Calendar.current.date(byAdding: .minute, value: 45, to: session1.startTime)!
    let checkIn1_1 = CheckIn(intervalMinutes: 3, checkInNumber: 1)
    checkIn1_1.endTime = Calendar.current.date(byAdding: .second, value: 45, to: checkIn1_1.timestamp)
    let checkIn1_2 = CheckIn(intervalMinutes: 5, checkInNumber: 2)
    checkIn1_2.endTime = Calendar.current.date(byAdding: .second, value: 30, to: checkIn1_2.timestamp)
    let checkIn1_3 = CheckIn(intervalMinutes: 10, checkInNumber: 3)
    checkIn1_3.endTime = Calendar.current.date(byAdding: .second, value: 40, to: checkIn1_3.timestamp)
    session1.checkIns = [checkIn1_1, checkIn1_2, checkIn1_3]
    
    let session2 = SleepSession(nightNumber: 2, date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, fellAsleep: true)
    session2.startTime = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: session2.date)!
    session2.endTime = Calendar.current.date(byAdding: .minute, value: 35, to: session2.startTime)!
    let checkIn2_1 = CheckIn(intervalMinutes: 5, checkInNumber: 1)
    checkIn2_1.endTime = Calendar.current.date(byAdding: .second, value: 35, to: checkIn2_1.timestamp)
    let checkIn2_2 = CheckIn(intervalMinutes: 10, checkInNumber: 2)
    checkIn2_2.endTime = Calendar.current.date(byAdding: .second, value: 40, to: checkIn2_2.timestamp)
    session2.checkIns = [checkIn2_1, checkIn2_2]
    
    let session3 = SleepSession(nightNumber: 3, date: Calendar.current.date(byAdding: .day, value: -4, to: Date())!, fellAsleep: true)
    session3.startTime = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: session3.date)!
    session3.endTime = Calendar.current.date(byAdding: .minute, value: 25, to: session3.startTime)!
    let checkIn3_1 = CheckIn(intervalMinutes: 10, checkInNumber: 1)
    checkIn3_1.endTime = Calendar.current.date(byAdding: .second, value: 30, to: checkIn3_1.timestamp)
    session3.checkIns = [checkIn3_1]
    
    container.mainContext.insert(session1)
    container.mainContext.insert(session2)
    container.mainContext.insert(session3)
    
    return HistoryView()
        .modelContainer(container)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SleepSession.self, CheckIn.self, configurations: config)
    
    return HistoryView()
        .modelContainer(container)
}
