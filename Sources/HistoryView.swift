import SwiftUI
import SwiftData
import Charts

// MARK: - History View
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SleepSession.date, order: .reverse) private var sessions: [SleepSession]
    
    @State private var selectedTab: HistoryTab = .history
    
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
                
                if sessions.isEmpty {
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
                            SessionHistoryList(sessions: sessions)
                                .tag(HistoryTab.history)
                            
                            TrendsView(sessions: sessions)
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
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    SessionRowView(session: session)
                }
            }
            .padding()
        }
    }
}

// MARK: - Session Row View (Expandable)
struct SessionRowView: View {
    let session: SleepSession
    @State private var isExpanded: Bool = false
    
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
            
            // Expanded check-ins
            if isExpanded && !session.checkIns.isEmpty {
                VStack(spacing: 0) {
                    ForEach(session.checkIns.sorted(by: { $0.checkInNumber < $1.checkInNumber })) { checkIn in
                        CheckInRowView(checkIn: checkIn)
                    }
                }
                .padding(.leading, 40)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Check-In Row View
struct CheckInRowView: View {
    let checkIn: CheckIn
    
    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 8, height: 8)
            }
            
            // Check-in info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check-in #\(checkIn.checkInNumber)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    if let duration = checkIn.checkInDuration {
                        Text("In room: \(checkIn.formattedCheckInDuration)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Text("after \(checkIn.formattedInterval)")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.2))
                    )
            }
            .padding(.vertical, 8)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Trends View
struct TrendsView: View {
    let sessions: [SleepSession]
    
    private var completedSessions: [SleepSession] {
        sessions.filter { $0.fellAsleep && $0.totalDurationToSleep != nil }
            .sorted { $0.nightNumber < $1.nightNumber }
    }
    
    private var totalNights: Int {
        sessions.count
    }
    
    private var successfulNights: Int {
        sessions.filter { $0.fellAsleep }.count
    }
    
    private var averageCheckInDuration: TimeInterval {
        let allCheckIns = sessions.flatMap { $0.checkIns }
        let durations = allCheckIns.compactMap { $0.checkInDuration }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }
    
    private var bestNight: SleepSession? {
        completedSessions.min { ($0.totalDurationToSleep ?? .infinity) < ($1.totalDurationToSleep ?? .infinity) }
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
                if completedSessions.count >= 2 {
                    ChartCard(title: "Time to Sleep", subtitle: "Should trend down over time") {
                        TimeToSleepChart(sessions: completedSessions)
                    }
                    
                    // Check-ins Chart
                    ChartCard(title: "Check-ins per Night", subtitle: "Number of visits needed") {
                        CheckInsChart(sessions: completedSessions)
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
    let bestNight: SleepSession?
    
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
                        subtitle: best.formattedTotalDuration,
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
    let sessions: [SleepSession]
    
    var body: some View {
        Chart(sessions) { session in
            LineMark(
                x: .value("Night", "Night \(session.nightNumber)"),
                y: .value("Minutes", (session.totalDurationToSleep ?? 0) / 60)
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
                x: .value("Night", "Night \(session.nightNumber)"),
                y: .value("Minutes", (session.totalDurationToSleep ?? 0) / 60)
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
                x: .value("Night", "Night \(session.nightNumber)"),
                y: .value("Minutes", (session.totalDurationToSleep ?? 0) / 60)
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
    let sessions: [SleepSession]
    
    var body: some View {
        Chart(sessions) { session in
            BarMark(
                x: .value("Night", "Night \(session.nightNumber)"),
                y: .value("Check-ins", session.checkInCount)
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
