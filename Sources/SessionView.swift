import SwiftUI
import SwiftData
import Combine

// MARK: - Session State

enum SessionState: Equatable {
    case idle
    case waiting(intervalSeconds: Int, checkInNumber: Int)
    case checkIn(checkInNumber: Int)
}

// MARK: - Session View Model

@Observable
final class SessionViewModel {
    var state: SessionState = .idle
    var currentSession: SleepSession?
    var currentCheckInStartTime: Date?
    
    // Timer values
    var waitingSecondsRemaining: Int = 0
    var checkInSecondsElapsed: Int = 0
    var sessionSecondsElapsed: Int = 0
    
    // Configuration
    var currentNight: Int = 1
    var nightConfig: NightConfiguration?
    var maxCheckInDuration: Int = 60 // seconds
    
    private var timerCancellable: AnyCancellable?
    
    var checkInCount: Int {
        currentSession?.checkIns.count ?? 0
    }
    
    /// Get the interval for a given check-in number based on Ferber method
    func intervalForCheckIn(_ checkInNumber: Int) -> TimeInterval {
        guard let config = nightConfig else {
            // Default night 1 intervals if no config
            switch checkInNumber {
            case 1: return 180  // 3 min
            case 2: return 300  // 5 min
            default: return 600 // 10 min
            }
        }
        
        switch checkInNumber {
        case 1: return config.firstInterval
        case 2: return config.secondInterval
        case 3: return config.thirdInterval
        default: return config.subsequentInterval
        }
    }
    
    var currentIntervalSeconds: Int {
        Int(intervalForCheckIn(checkInCount + 1))
    }
    
    var waitingProgress: Double {
        guard case .waiting(let intervalSeconds, _) = state else { return 0 }
        guard intervalSeconds > 0 else { return 0 }
        return 1.0 - (Double(waitingSecondsRemaining) / Double(intervalSeconds))
    }
    
    var checkInProgress: Double {
        guard maxCheckInDuration > 0 else { return 0 }
        return min(1.0, Double(checkInSecondsElapsed) / Double(maxCheckInDuration))
    }
    
    var formattedSessionTime: String {
        formatTime(sessionSecondsElapsed)
    }
    
    var formattedWaitingTime: String {
        formatTime(waitingSecondsRemaining)
    }
    
    var formattedCheckInTime: String {
        formatTime(checkInSecondsElapsed)
    }
    
    /// Format intervals for display (e.g., "3m → 5m → 10m")
    var formattedIntervals: String {
        let intervals = [
            Int(intervalForCheckIn(1) / 60),
            Int(intervalForCheckIn(2) / 60),
            Int(intervalForCheckIn(3) / 60)
        ]
        return intervals.map { "\($0)m" }.joined(separator: " → ") + "+"
    }
    
    private func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    func loadNightConfiguration(modelContext: ModelContext) {
        let configs = NightConfiguration.defaultIntervals()
        nightConfig = configs.first { $0.nightNumber == currentNight }
    }
    
    func startSession(modelContext: ModelContext) {
        let session = SleepSession(nightNumber: currentNight)
        modelContext.insert(session)
        currentSession = session
        
        let intervalSeconds = currentIntervalSeconds
        startWaiting(intervalSeconds: intervalSeconds, checkInNumber: 1)
        startTimer()
        
        // Schedule notification for first check-in
        NotificationManager.shared.scheduleCheckInAlert(in: intervalSeconds)
    }
    
    private func startWaiting(intervalSeconds: Int, checkInNumber: Int) {
        state = .waiting(intervalSeconds: intervalSeconds, checkInNumber: checkInNumber)
        waitingSecondsRemaining = intervalSeconds
        checkInSecondsElapsed = 0
    }
    
    func startCheckIn(modelContext: ModelContext) {
        guard case .waiting(let intervalSeconds, let checkInNumber) = state else { return }
        
        // Record the check-in with the duration waited
        let checkIn = CheckIn(
            duration: TimeInterval(intervalSeconds),
            checkInNumber: checkInNumber
        )
        currentSession?.checkIns.append(checkIn)
        modelContext.insert(checkIn)
        currentCheckInStartTime = Date()
        
        state = .checkIn(checkInNumber: checkInNumber)
        checkInSecondsElapsed = 0
        
        // Schedule leave room reminder
        NotificationManager.shared.scheduleLeaveRoomAlert(in: maxCheckInDuration)
    }
    
    func finishCheckIn(modelContext: ModelContext) {
        guard case .checkIn(let checkInNumber) = state else { return }
        
        currentCheckInStartTime = nil
        
        let nextCheckInNumber = checkInNumber + 1
        let nextIntervalSeconds = Int(intervalForCheckIn(nextCheckInNumber))
        
        startWaiting(intervalSeconds: nextIntervalSeconds, checkInNumber: nextCheckInNumber)
        
        // Schedule next check-in notification
        NotificationManager.shared.scheduleCheckInAlert(in: nextIntervalSeconds)
    }
    
    func babyFellAsleep(modelContext: ModelContext) {
        guard let session = currentSession else { return }
        
        session.endTime = Date()
        session.isCompleted = true
        
        stopTimer()
        resetSession()
        
        // Increment night for next session (max 7)
        currentNight = min(currentNight + 1, 7)
        loadNightConfiguration(modelContext: modelContext)
    }
    
    func cancelSession(modelContext: ModelContext) {
        guard let session = currentSession else { return }
        
        session.endTime = Date()
        session.isCompleted = false
        
        stopTimer()
        resetSession()
    }
    
    private func resetSession() {
        state = .idle
        currentSession = nil
        currentCheckInStartTime = nil
        waitingSecondsRemaining = 0
        checkInSecondsElapsed = 0
        sessionSecondsElapsed = 0
        
        // Cancel all pending notifications when session ends
        NotificationManager.shared.cancelAll()
    }
    
    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func tick() {
        sessionSecondsElapsed += 1
        
        switch state {
        case .idle:
            break
        case .waiting:
            if waitingSecondsRemaining > 0 {
                waitingSecondsRemaining -= 1
            }
        case .checkIn:
            checkInSecondsElapsed += 1
        }
    }
}

// MARK: - Session View

struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SessionViewModel()
    @State private var showCancelConfirmation = false
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 20)
                
                Spacer()
                
                // Main timer area
                mainContent
                
                Spacer()
                
                // Bottom action area
                bottomActions
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "End Session?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                viewModel.cancelSession(modelContext: modelContext)
            }
            Button("Continue", role: .cancel) { }
        } message: {
            Text("This will end the current session without marking baby as asleep.")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Night indicator
            Label("Night \(viewModel.currentNight)", systemImage: "moon.stars.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.indigo.opacity(0.9))
            
            Spacer()
            
            // Session info (visible during active session)
            if viewModel.state != .idle {
                HStack(spacing: 16) {
                    // Check-in count
                    Label("\(viewModel.checkInCount)", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Session duration
                    Label(viewModel.formattedSessionTime, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.state {
        case .idle:
            idleView
        case .waiting(_, let checkInNumber):
            waitingView(checkInNumber: checkInNumber)
        case .checkIn(let checkInNumber):
            checkInView(checkInNumber: checkInNumber)
        }
    }
    
    // MARK: - Idle View
    
    private var idleView: some View {
        VStack(spacing: 32) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 80))
                .foregroundStyle(.indigo.gradient)
            
            VStack(spacing: 8) {
                Text("Ready for Night \(viewModel.currentNight)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Text("Intervals: \(viewModel.formattedIntervals)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                viewModel.startSession(modelContext: modelContext)
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
    }
    
    // MARK: - Waiting View
    
    private var waitingView: (Int) -> some View {
        { checkInNumber in
            VStack(spacing: 24) {
                // Status label
                Label("Waiting", systemImage: "hourglass")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange.opacity(0.8))
                
                // Main countdown timer
                Text(viewModel.formattedWaitingTime)
                    .font(.system(size: 96, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: viewModel.waitingSecondsRemaining)
                
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    
                    Circle()
                        .trim(from: 0, to: viewModel.waitingProgress)
                        .stroke(
                            AngularGradient(
                                colors: [.orange, .yellow, .orange],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: viewModel.waitingProgress)
                }
                .frame(width: 120, height: 120)
                
                // Next check-in info
                VStack(spacing: 4) {
                    Text("Check-in #\(checkInNumber)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("Interval: \(Int(viewModel.intervalForCheckIn(checkInNumber) / 60)) minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                
                // Time's up - Start check-in button
                if viewModel.waitingSecondsRemaining == 0 {
                    Button {
                        viewModel.startCheckIn(modelContext: modelContext)
                    } label: {
                        Label("Time to Check In", systemImage: "figure.walk")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Check-In View
    
    private var checkInView: (Int) -> some View {
        { checkInNumber in
            VStack(spacing: 24) {
                // Status label
                Label("Check-In #\(checkInNumber)", systemImage: "figure.and.child.holdinghands")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.teal.opacity(0.9))
                
                // Count-up timer
                Text(viewModel.formattedCheckInTime)
                    .font(.system(size: 96, weight: .light, design: .rounded))
                    .foregroundStyle(checkInTimeColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: viewModel.checkInSecondsElapsed)
                
                // Progress indicator
                ProgressView(value: viewModel.checkInProgress)
                    .progressViewStyle(CheckInProgressStyle())
                    .frame(height: 8)
                    .padding(.horizontal, 32)
                
                // Guidance text
                VStack(spacing: 4) {
                    Text(checkInGuidanceText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Max \(viewModel.maxCheckInDuration) seconds recommended")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .padding(.top, 8)
                
                // Done checking button
                Button {
                    viewModel.finishCheckIn(modelContext: modelContext)
                } label: {
                    Label("Done Checking", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.teal, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
    }
    
    private var checkInTimeColor: Color {
        if viewModel.checkInSecondsElapsed >= viewModel.maxCheckInDuration {
            return .red
        } else if viewModel.checkInSecondsElapsed >= viewModel.maxCheckInDuration - 15 {
            return .orange
        }
        return .teal
    }
    
    private var checkInGuidanceText: String {
        if viewModel.checkInSecondsElapsed >= viewModel.maxCheckInDuration {
            return "Time to leave the room"
        } else if viewModel.checkInSecondsElapsed >= viewModel.maxCheckInDuration - 15 {
            return "Start wrapping up..."
        }
        return "Brief comfort, no picking up"
    }
    
    // MARK: - Bottom Actions
    
    @ViewBuilder
    private var bottomActions: some View {
        if viewModel.state != .idle {
            VStack(spacing: 16) {
                // Baby fell asleep button - prominent but requires deliberate tap
                Button {
                    viewModel.babyFellAsleep(modelContext: modelContext)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.title2)
                        Text("Baby Fell Asleep")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.indigo.opacity(0.6), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.indigo.opacity(0.15))
                            )
                    )
                }
                .buttonStyle(.plain)
                
                // Cancel button - subtle
                Button {
                    showCancelConfirmation = true
                } label: {
                    Text("End Session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Custom Progress Style

struct CheckInProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor(for: configuration.fractionCompleted ?? 0))
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                    .animation(.linear(duration: 0.5), value: configuration.fractionCompleted)
            }
        }
    }
    
    private func progressColor(for fraction: Double) -> Color {
        if fraction >= 1.0 {
            return .red
        } else if fraction >= 0.75 {
            return .orange
        }
        return .teal
    }
}



// MARK: - Preview

#Preview {
    SessionView()
        .modelContainer(for: [SleepSession.self, CheckIn.self, NightConfiguration.self], inMemory: true)
}
