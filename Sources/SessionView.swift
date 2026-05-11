import SwiftUI
import SwiftData
import Combine

// MARK: - Session State

enum SessionState: Equatable {
    case idle
    case waiting(intervalSeconds: Int, checkInNumber: Int)
    case checkIn(checkInNumber: Int)
}

struct ActiveSessionDraft {
    var syncID: String
    var nightNumber: Int
    var date: Date
    var startTime: Date
    var checkIns: [ActiveCheckInDraft] = []
}

struct ActiveCheckInDraft {
    var syncID: String
    var timestamp: Date
    var intervalMinutes: Int
    var checkInNumber: Int
    var endTime: Date?
    var notes: String?
}

struct CompletedSessionDraft {
    var syncID: String
    var nightNumber: Int
    var date: Date
    var startTime: Date
    var endTime: Date
    var fellAsleep: Bool
    var checkIns: [ActiveCheckInDraft]
}

// MARK: - Session View Model

@MainActor
@Observable
final class SessionViewModel {
    var state: SessionState = .idle
    var currentSession: SleepSession?
    var currentSessionDraft: ActiveSessionDraft?
    var currentCheckInStartTime: Date?
    var currentStateStartTime: Date?
    
    // Timer values (computed from wall clock on each tick)
    var waitingSecondsRemaining: Int = 0
    var checkInSecondsElapsed: Int = 0
    var sessionSecondsElapsed: Int = 0
    var waitingPaused: Bool = false
    
    // Wall clock anchors for accurate background timing
    private var waitingResumedAt: Date?
    private var waitingSecondsAtResume: Int = 0
    
    // Configuration
    var currentNight: Int = 1
    var nightConfig: NightConfiguration?
    var maxCheckInDuration: Int = 120 // seconds
    
    private var timerCancellable: AnyCancellable?
    
    var checkInCount: Int {
        currentSessionDraft?.checkIns.count ?? currentSession?.checkIns.count ?? 0
    }
    
    /// Get the interval in seconds for a given check-in number based on Ferber method
    func intervalForCheckIn(_ checkInNumber: Int) -> TimeInterval {
        let intervals = nightConfig?.intervals ?? NightConfiguration.defaultIntervals(for: currentNight)
        let intervalMinutes: Int
        
        switch checkInNumber {
        case 1: intervalMinutes = intervals[0]
        case 2: intervalMinutes = intervals[1]
        case 3: intervalMinutes = intervals[2]
        default: intervalMinutes = intervals[3]
        }
        
        return TimeInterval(intervalMinutes * 60)
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
    
    var formattedCheckInTimeRemaining: String {
        formatTime(max(0, maxCheckInDuration - checkInSecondsElapsed))
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
        let descriptor = FetchDescriptor<NightConfiguration>(
            predicate: #Predicate { $0.nightNumber == currentNight }
        )
        nightConfig = try? modelContext.fetch(descriptor).first
    }
    
    private func saveSessionData(_ modelContext: ModelContext, action: String) {
        do {
            try modelContext.save()
            let count = (try? modelContext.fetch(FetchDescriptor<SleepSession>()).count) ?? -1
            print("SwiftData save succeeded during \(action). Local session count: \(count)")
        } catch {
            print("SwiftData save failed during \(action): \(error.localizedDescription)")
        }
    }
    
    func startSession(modelContext: ModelContext) {
        let startTime = Date()
        currentSessionDraft = ActiveSessionDraft(
            syncID: UUID().uuidString,
            nightNumber: currentNight,
            date: startTime,
            startTime: startTime
        )
        currentSession = nil
        
        let intervalSeconds = currentIntervalSeconds
        startWaiting(intervalSeconds: intervalSeconds, checkInNumber: 1)
        startTimer()
        
        // Schedule notification for first check-in
        NotificationManager.shared.scheduleCheckNotification(afterSeconds: TimeInterval(intervalSeconds), checkNumber: 1)
    }
    
    private func startWaiting(intervalSeconds: Int, checkInNumber: Int) {
        state = .waiting(intervalSeconds: intervalSeconds, checkInNumber: checkInNumber)
        waitingSecondsRemaining = intervalSeconds
        waitingSecondsAtResume = intervalSeconds
        waitingResumedAt = Date()
        checkInSecondsElapsed = 0
        currentStateStartTime = Date()
    }
    
    func startCheckIn(modelContext: ModelContext) {
        guard case .waiting(let intervalSeconds, let checkInNumber) = state else { return }
        
        // Record the check-in with the duration waited
        let checkIn = ActiveCheckInDraft(
            syncID: UUID().uuidString,
            timestamp: Date(),
            intervalMinutes: intervalSeconds / 60,
            checkInNumber: checkInNumber
        )
        currentSessionDraft?.checkIns.append(checkIn)
        currentCheckInStartTime = checkIn.timestamp
        currentStateStartTime = currentCheckInStartTime
        
        state = .checkIn(checkInNumber: checkInNumber)
        checkInSecondsElapsed = 0
        
        NotificationManager.shared.cancelAllNotifications()
        
        // Schedule leave room reminder
        NotificationManager.shared.scheduleLeaveRoomNotification(afterSeconds: TimeInterval(maxCheckInDuration))
    }
    
    func finishCheckIn(modelContext: ModelContext) {
        guard case .checkIn(let checkInNumber) = state else { return }
        
        currentCheckInStartTime = nil
        
        let nextCheckInNumber = checkInNumber + 1
        let nextIntervalSeconds = Int(intervalForCheckIn(nextCheckInNumber))
        
        startWaiting(intervalSeconds: nextIntervalSeconds, checkInNumber: nextCheckInNumber)
        waitingPaused = true
        waitingResumedAt = nil
        
        if let lastIndex = currentSessionDraft?.checkIns.indices.last {
            currentSessionDraft?.checkIns[lastIndex].endTime = Date()
        } else {
            currentSession?.checkIns.last?.endTime = Date()
        }
        
        NotificationManager.shared.cancelAllNotifications()
    }
    
    func resumeWaiting() {
        guard case .waiting(_, let checkInNumber) = state else { return }
        waitingPaused = false
        waitingResumedAt = Date()
        waitingSecondsAtResume = waitingSecondsRemaining
        currentStateStartTime = Date()
        
        NotificationManager.shared.scheduleCheckNotification(afterSeconds: TimeInterval(waitingSecondsRemaining), checkNumber: checkInNumber)
    }
    
    func pauseWaiting() {
        guard case .waiting = state else { return }
        recalculateFromWallClock()
        waitingPaused = true
        waitingResumedAt = nil
        NotificationManager.shared.cancelAllNotifications()
    }
    
    func goBackFromCheckIn() {
        guard case .checkIn(let checkInNumber) = state else { return }
        
        let intervalSeconds = Int(intervalForCheckIn(checkInNumber))
        state = .waiting(intervalSeconds: intervalSeconds, checkInNumber: checkInNumber)
        waitingPaused = true
        waitingResumedAt = nil
        waitingSecondsRemaining = intervalSeconds
        waitingSecondsAtResume = intervalSeconds
        checkInSecondsElapsed = 0
        currentCheckInStartTime = nil
        currentStateStartTime = Date()
        
        if let lastIndex = currentSessionDraft?.checkIns.indices.last {
            currentSessionDraft?.checkIns.remove(at: lastIndex)
        }
        
        NotificationManager.shared.cancelAllNotifications()
    }
    
    func cancelSessionSilently() {
        stopTimer()
        resetSession()
    }
    
    func goBackFromWaiting() {
        guard case .waiting(_, let checkInNumber) = state, checkInNumber > 1 else { return }
        
        let previousCheckInNumber = checkInNumber - 1
        state = .checkIn(checkInNumber: previousCheckInNumber)
        checkInSecondsElapsed = 0
        waitingSecondsRemaining = 0
        waitingPaused = false
        currentCheckInStartTime = Date()
        currentStateStartTime = currentCheckInStartTime
        
        if let lastIndex = currentSessionDraft?.checkIns.indices.last {
            currentSessionDraft?.checkIns[lastIndex].endTime = nil
        }
        
        NotificationManager.shared.cancelAllNotifications()
        NotificationManager.shared.scheduleLeaveRoomNotification(afterSeconds: TimeInterval(maxCheckInDuration))
    }
    
    func restartWaiting() {
        guard case .waiting(let intervalSeconds, let checkInNumber) = state else { return }
        waitingSecondsRemaining = intervalSeconds
        waitingSecondsAtResume = intervalSeconds
        currentStateStartTime = Date()
        
        if !waitingPaused {
            waitingResumedAt = Date()
            NotificationManager.shared.cancelAllNotifications()
            NotificationManager.shared.scheduleCheckNotification(afterSeconds: TimeInterval(intervalSeconds), checkNumber: checkInNumber)
        } else {
            waitingResumedAt = nil
        }
    }
    
    func finishSessionDraft(fellAsleep: Bool) -> CompletedSessionDraft? {
        let endTime = Date()
        
        if var draft = currentSessionDraft {
            if let lastIndex = draft.checkIns.indices.last, draft.checkIns[lastIndex].endTime == nil {
                draft.checkIns[lastIndex].endTime = endTime
            }
            
            stopTimer()
            resetSession()
            return CompletedSessionDraft(
                syncID: draft.syncID,
                nightNumber: draft.nightNumber,
                date: draft.date,
                startTime: draft.startTime,
                endTime: endTime,
                fellAsleep: fellAsleep,
                checkIns: draft.checkIns
            )
        }
        
        guard let session = currentSession else { return nil }
        let checkIns = session.checkIns.map { checkIn in
            ActiveCheckInDraft(
                syncID: checkIn.syncID ?? UUID().uuidString,
                timestamp: checkIn.timestamp,
                intervalMinutes: checkIn.intervalMinutes,
                checkInNumber: checkIn.checkInNumber,
                endTime: checkIn.endTime,
                notes: checkIn.notes
            )
        }
        
        stopTimer()
        resetSession()
        return CompletedSessionDraft(
            syncID: session.syncID ?? UUID().uuidString,
            nightNumber: session.nightNumber,
            date: session.date,
            startTime: session.startTime,
            endTime: endTime,
            fellAsleep: fellAsleep,
            checkIns: checkIns
        )
    }
    
    private func resetSession() {
        state = .idle
        currentSession = nil
        currentSessionDraft = nil
        currentCheckInStartTime = nil
        currentStateStartTime = nil
        waitingSecondsRemaining = 0
        checkInSecondsElapsed = 0
        sessionSecondsElapsed = 0
        waitingPaused = false
        waitingResumedAt = nil
        waitingSecondsAtResume = 0
        
        // Cancel all pending notifications when session ends
        NotificationManager.shared.cancelAllNotifications()
    }
    
    private func startTimer() {
        stopTimer()
        
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recalculateFromWallClock()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    func recalculateFromWallClock() {
        let now = Date()
        
        if let sessionStart = currentSessionDraft?.startTime ?? currentSession?.startTime {
            sessionSecondsElapsed = max(0, Int(now.timeIntervalSince(sessionStart)))
        }
        
        switch state {
        case .idle:
            break
        case .waiting:
            if !waitingPaused, let resumedAt = waitingResumedAt {
                let elapsed = max(0, Int(now.timeIntervalSince(resumedAt)))
                waitingSecondsRemaining = max(0, waitingSecondsAtResume - elapsed)
            }
        case .checkIn:
            if let stateStart = currentStateStartTime {
                checkInSecondsElapsed = max(0, Int(now.timeIntervalSince(stateStart)))
            }
        }
    }
    
    func makeSharedActiveSessionState() -> SharedActiveSessionState? {
        guard let draft = currentSessionDraft else { return nil }
        guard let currentStateStartTime else { return nil }
        
        switch state {
        case .idle:
            return nil
        case .waiting(let intervalSeconds, let checkInNumber):
            return SharedActiveSessionState(
                sessionID: draft.syncID,
                phase: .waiting,
                nightNumber: draft.nightNumber,
                sessionStartTime: draft.startTime,
                stateStartedAt: currentStateStartTime,
                intervalSeconds: intervalSeconds,
                checkInNumber: checkInNumber,
                maxCheckInDuration: maxCheckInDuration,
                updatedAt: Date()
            )
        case .checkIn(let checkInNumber):
            return SharedActiveSessionState(
                sessionID: draft.syncID,
                phase: .checkIn,
                nightNumber: draft.nightNumber,
                sessionStartTime: draft.startTime,
                stateStartedAt: currentStateStartTime,
                intervalSeconds: Int(intervalForCheckIn(checkInNumber)),
                checkInNumber: checkInNumber,
                maxCheckInDuration: maxCheckInDuration,
                updatedAt: Date()
            )
        }
    }
    
    func makeSharedEndedSessionState(phase: SharedActiveSessionPhase) -> SharedActiveSessionState? {
        guard phase == .ended || phase == .cancelled else { return nil }
        guard let draft = currentSessionDraft else { return nil }
        
        return SharedActiveSessionState(
            sessionID: draft.syncID,
            phase: phase,
            nightNumber: draft.nightNumber,
            sessionStartTime: draft.startTime,
            stateStartedAt: Date(),
            intervalSeconds: 0,
            checkInNumber: checkInCount + 1,
            maxCheckInDuration: maxCheckInDuration,
            updatedAt: Date()
        )
    }
    
    func applySharedActiveSessionState(_ sharedState: SharedActiveSessionState, modelContext: ModelContext) {
        currentNight = sharedState.nightNumber
        maxCheckInDuration = sharedState.maxCheckInDuration
        
        if sharedState.phase == .ended || sharedState.phase == .cancelled {
            if currentSessionDraft?.syncID == sharedState.sessionID || currentSession?.syncID == sharedState.sessionID {
                resetSession()
            }
            return
        }
        
        ensureDraftExists(for: sharedState)
        currentSession = nil
        sessionSecondsElapsed = max(0, Int(Date().timeIntervalSince(sharedState.sessionStartTime)))
        currentStateStartTime = sharedState.stateStartedAt
        
        switch sharedState.phase {
        case .waiting:
            closePreviousDraftCheckInIfNeeded(for: sharedState)
            
            let elapsed = max(0, Int(Date().timeIntervalSince(sharedState.stateStartedAt)))
            state = .waiting(intervalSeconds: sharedState.intervalSeconds, checkInNumber: sharedState.checkInNumber)
            waitingSecondsRemaining = max(0, sharedState.intervalSeconds - elapsed)
            checkInSecondsElapsed = 0
            currentCheckInStartTime = nil
        case .checkIn:
            state = .checkIn(checkInNumber: sharedState.checkInNumber)
            waitingSecondsRemaining = 0
            checkInSecondsElapsed = max(0, Int(Date().timeIntervalSince(sharedState.stateStartedAt)))
            currentCheckInStartTime = sharedState.stateStartedAt
            ensureDraftCheckInExists(for: sharedState)
        case .ended, .cancelled:
            return
        }
        
        startTimer()
    }
    
    private func ensureDraftExists(for sharedState: SharedActiveSessionState) {
        guard currentSessionDraft?.syncID != sharedState.sessionID else { return }
        currentSessionDraft = ActiveSessionDraft(
            syncID: sharedState.sessionID,
            nightNumber: sharedState.nightNumber,
            date: sharedState.sessionStartTime,
            startTime: sharedState.sessionStartTime
        )
    }
    
    private func ensureDraftCheckInExists(for sharedState: SharedActiveSessionState) {
        guard var draft = currentSessionDraft else { return }
        
        if let index = draft.checkIns.firstIndex(where: { $0.checkInNumber == sharedState.checkInNumber }) {
            draft.checkIns[index].timestamp = sharedState.stateStartedAt
            draft.checkIns[index].intervalMinutes = sharedState.intervalSeconds / 60
            currentSessionDraft = draft
            return
        }
        
        draft.checkIns.append(
            ActiveCheckInDraft(
                syncID: UUID().uuidString,
                timestamp: sharedState.stateStartedAt,
                intervalMinutes: sharedState.intervalSeconds / 60,
                checkInNumber: sharedState.checkInNumber
            )
        )
        currentSessionDraft = draft
    }
    
    private func closePreviousDraftCheckInIfNeeded(for sharedState: SharedActiveSessionState) {
        guard var draft = currentSessionDraft else { return }
        let previousCheckInNumber = sharedState.checkInNumber - 1
        guard previousCheckInNumber > 0 else { return }
        guard let index = draft.checkIns.firstIndex(where: { $0.checkInNumber == previousCheckInNumber && $0.endTime == nil }) else { return }
        
        draft.checkIns[index].endTime = sharedState.stateStartedAt
        currentSessionDraft = draft
    }
    
    private func session(for sharedState: SharedActiveSessionState, modelContext: ModelContext) -> SleepSession {
        if currentSession?.syncID == sharedState.sessionID, let currentSession {
            return currentSession
        }
        
        if let existingSession = existingSession(withSyncID: sharedState.sessionID, modelContext: modelContext) {
            return existingSession
        }
        
        let session = SleepSession(
            syncID: sharedState.sessionID,
            nightNumber: sharedState.nightNumber,
            date: sharedState.sessionStartTime,
            startTime: sharedState.sessionStartTime
        )
        modelContext.insert(session)
        return session
    }
    
    private func existingSession(withSyncID syncID: String, modelContext: ModelContext) -> SleepSession? {
        guard let sessions = try? modelContext.fetch(FetchDescriptor<SleepSession>()) else { return nil }
        return sessions.first { $0.syncID == syncID }
    }
    
    private func ensureCheckInExists(for sharedState: SharedActiveSessionState, modelContext: ModelContext) {
        guard let currentSession else { return }
        
        if let existingCheckIn = currentSession.checkIns.first(where: { $0.checkInNumber == sharedState.checkInNumber }) {
            existingCheckIn.timestamp = sharedState.stateStartedAt
            existingCheckIn.intervalMinutes = sharedState.intervalSeconds / 60
            return
        }
        
        let checkIn = CheckIn(
            timestamp: sharedState.stateStartedAt,
            intervalMinutes: sharedState.intervalSeconds / 60,
            checkInNumber: sharedState.checkInNumber
        )
        currentSession.checkIns.append(checkIn)
        modelContext.insert(checkIn)
    }
}

// MARK: - Session View

struct RecentSessionSummary: Identifiable, Codable, Equatable {
    let id: String
    let nightNumber: Int
    let startTime: Date
    let isCompleted: Bool
    let formattedDate: String
    let formattedStartTime: String
    let formattedEndTime: String
    let formattedTotalDuration: String
    let checkInCount: Int
    
    init(storedSession: StoredSleepSession) {
        id = storedSession.syncID
        nightNumber = storedSession.nightNumber
        startTime = storedSession.startTime
        isCompleted = storedSession.isCompleted
        formattedDate = storedSession.formattedDate
        formattedStartTime = storedSession.formattedStartTime
        formattedEndTime = storedSession.formattedEndTime
        formattedTotalDuration = storedSession.formattedTotalDuration
        checkInCount = storedSession.checkIns.count
    }
    
    init(session: SleepSession) {
        id = session.syncID ?? "\(session.startTime.timeIntervalSince1970)-\(session.nightNumber)"
        nightNumber = session.nightNumber
        startTime = session.startTime
        isCompleted = session.isCompleted
        formattedDate = session.formattedDate
        formattedStartTime = session.formattedStartTime
        formattedEndTime = session.formattedEndTime
        formattedTotalDuration = session.formattedTotalDuration
        checkInCount = session.checkInCount
    }
}

struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SleepSession.startTime, order: .reverse) private var sessions: [SleepSession]
    @AppStorage("currentNight") private var currentNight: Int = 1
    @AppStorage("checkInDurationLimit") private var checkInDurationLimit: Int = 2
    @AppStorage("householdCode") private var householdCode: String = ""
    @AppStorage("recentSessionSummariesJSON") private var recentSessionSummariesJSON: String = "[]"
    @State private var viewModel = SessionViewModel()
    @State private var showCancelConfirmation = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var lastSharedActiveSessionUpdate: Date?
    @State private var recentSessionSummaries: [RecentSessionSummary] = []
    
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
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            migrateCheckInDurationLimitToMinutes()
            viewModel.currentNight = currentNight
            viewModel.maxCheckInDuration = checkInDurationLimit * 60
            viewModel.loadNightConfiguration(modelContext: modelContext)
            refreshLocalSessions()
            syncHouseholdIfConfigured()
        }
        .task(id: householdCode) {
            syncHouseholdIfConfigured()
            await pollActiveSessionWhileNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            viewModel.recalculateFromWallClock()
            refreshLocalSessions()
            Task {
                syncHouseholdIfConfigured()
                await refreshActiveSessionFromCloud()
            }
        }
        .onChange(of: showSettings) { _, isShowing in
            guard !isShowing else { return }
            refreshLocalSessions()
            syncHouseholdIfConfigured()
        }
        .onChange(of: showHistory) { _, isShowing in
            guard !isShowing else { return }
            refreshLocalSessions()
        }
        .onChange(of: currentNight) { _, newValue in
            viewModel.currentNight = newValue
            viewModel.loadNightConfiguration(modelContext: modelContext)
        }
        .onChange(of: checkInDurationLimit) { _, newValue in
            if newValue > 40 {
                migrateCheckInDurationLimitToMinutes()
            } else {
                viewModel.maxCheckInDuration = newValue * 60
            }
        }
        .confirmationDialog(
            "End Session?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                let endedState = viewModel.makeSharedEndedSessionState(phase: .cancelled)
                if let draft = viewModel.finishSessionDraft(fellAsleep: false),
                   let session = persistCompletedSession(draft, action: "cancel session") {
                    saveRecentSessionSummary(RecentSessionSummary(session: session))
                }
                refreshLocalSessions()
                publishActiveSessionState(endedState)
                syncHouseholdIfConfigured()
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
            HStack(spacing: 6) {
                Button {
                    goToPreviousNight()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentNight == 1 ? Color.secondary.opacity(0.35) : Color.indigo)
                .disabled(currentNight == 1 || viewModel.state != .idle)
                .accessibilityLabel("Previous Night")
                
                Label("Night \(viewModel.currentNight)", systemImage: "moon.stars.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.indigo.opacity(0.9))
                
                Button {
                    goToNextNight()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentNight == 7 ? Color.secondary.opacity(0.35) : Color.indigo)
                .disabled(currentNight == 7 || viewModel.state != .idle)
                .accessibilityLabel("Next Night")
            }
            
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
            
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("History")
            
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.state {
        case .idle:
            idleView
        case .waiting(_, let checkInNumber):
            waitingView(checkInNumber)
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
            
            VStack(spacing: 18) {
                Button {
                    viewModel.startSession(modelContext: modelContext)
                    refreshLocalSessions()
                    publishActiveSessionState()
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
                
                recentSessionsView
            }
            .padding(.top, 16)
        }
    }
    
    private var formattedCheckInDurationLimit: String {
        let minutes = max(1, checkInDurationLimit)
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    
    private var currentNightSessions: [RecentSessionSummary] {
        displayedSessions.filter { $0.nightNumber == currentNight }
    }
    
    private var displayedSessions: [RecentSessionSummary] {
        recentSessionSummaries
    }
    
    private var completedCurrentNightSessions: Int {
        currentNightSessions.filter(\.isCompleted).count
    }
    
    @ViewBuilder
    private var recentSessionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Night \(currentNight) sessions")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(completedCurrentNightSessions) completed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            if currentNightSessions.isEmpty {
                Text("No sessions recorded for this night yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(currentNightSessions.prefix(3))) { session in
                        recentSessionRow(session)
                    }
                }
            }
            
            Text("Saved locally: \(displayedSessions.count)")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.45))
        }
        .padding(.horizontal, 4)
    }
    
    private func recentSessionRow(_ session: RecentSessionSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.isCompleted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption)
                .foregroundStyle(session.isCompleted ? .teal.opacity(0.75) : .secondary.opacity(0.6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.formattedDate)
                Text("\(session.formattedStartTime) - \(session.formattedEndTime)")
                    .foregroundStyle(.secondary.opacity(0.62))
            }
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.82))
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.isCompleted ? session.formattedTotalDuration : "Ended")
                Text("\(session.checkInCount) check-ins")
                    .foregroundStyle(.secondary.opacity(0.62))
            }
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.72))
            .monospacedDigit()
        }
    }
    
    private func migrateCheckInDurationLimitToMinutes() {
        if checkInDurationLimit > 40 {
            checkInDurationLimit = min(max(checkInDurationLimit / 60, 1), 40)
        } else {
            viewModel.maxCheckInDuration = checkInDurationLimit * 60
        }
    }
    
    private func goToPreviousNight() {
        currentNight = max(currentNight - 1, 1)
    }
    
    private func goToNextNight() {
        currentNight = min(currentNight + 1, 7)
    }
    
    private func refreshLocalSessions() {
        let storedSessions = LocalSessionStore.load()
        recentSessionSummaries = mergedRecentSessionSummaries(
            storedSessions.map(RecentSessionSummary.init),
            decodedRecentSessionSummaries
        )
    }
    
    private var decodedRecentSessionSummaries: [RecentSessionSummary] {
        guard let data = recentSessionSummariesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RecentSessionSummary].self, from: data)) ?? []
    }
    
    private func saveRecentSessionSummary(_ summary: RecentSessionSummary) {
        let merged = mergedRecentSessionSummaries([summary], decodedRecentSessionSummaries)
        if let data = try? JSONEncoder().encode(Array(merged.prefix(20))),
           let json = String(data: data, encoding: .utf8) {
            recentSessionSummariesJSON = json
        }
        recentSessionSummaries = merged
    }
    
    private func mergedRecentSessionSummaries(_ primary: [RecentSessionSummary], _ secondary: [RecentSessionSummary]) -> [RecentSessionSummary] {
        var seenIDs = Set<String>()
        return (primary + secondary)
            .sorted { $0.startTime > $1.startTime }
            .filter { summary in
                guard !seenIDs.contains(summary.id) else { return false }
                seenIDs.insert(summary.id)
                return true
            }
    }
    
    // MARK: - Waiting View
    
    @ViewBuilder
    private func waitingView(_ checkInNumber: Int) -> some View {
        VStack(spacing: 24) {
                // Status label
                Label(viewModel.waitingPaused ? "Paused" : "Waiting", systemImage: viewModel.waitingPaused ? "pause.circle" : "hourglass")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange.opacity(0.8))
                
                // Main countdown timer
                Text(viewModel.formattedWaitingTime)
                    .font(.system(size: 96, weight: .light, design: .rounded))
                    .foregroundStyle(viewModel.waitingPaused ? .white.opacity(0.4) : .white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: viewModel.waitingSecondsRemaining)
                
                // Timer controls
                HStack(spacing: 32) {
                    Button {
                        if checkInNumber == 1 {
                            let cancelledState = viewModel.makeSharedEndedSessionState(phase: .cancelled)
                            viewModel.cancelSessionSilently()
                            refreshLocalSessions()
                            publishActiveSessionState(cancelledState)
                        } else {
                            viewModel.goBackFromWaiting()
                            publishActiveSessionState()
                        }
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body)
                            .foregroundStyle(.orange.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        viewModel.restartWaiting()
                        publishActiveSessionState()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body)
                            .foregroundStyle(.orange.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if viewModel.waitingPaused {
                            viewModel.resumeWaiting()
                        } else {
                            viewModel.pauseWaiting()
                        }
                        publishActiveSessionState()
                    } label: {
                        Image(systemName: viewModel.waitingPaused ? "play.fill" : "pause.fill")
                            .font(.body)
                            .foregroundStyle(.orange.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                
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
                
                Button {
                    viewModel.startCheckIn(modelContext: modelContext)
                    refreshLocalSessions()
                    publishActiveSessionState()
                } label: {
                    Label("Check In", systemImage: "figure.walk")
                        .font(.headline)
                        .foregroundStyle(viewModel.waitingSecondsRemaining == 0 ? .black : .orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            viewModel.waitingSecondsRemaining == 0 ? .orange : .orange.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.orange.opacity(0.7), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
    
    // MARK: - Check-In View
    
    @ViewBuilder
    private func checkInView(checkInNumber: Int) -> some View {
        VStack(spacing: 24) {
                // Status label
                Label("Check-In #\(checkInNumber)", systemImage: "figure.and.child.holdinghands")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.teal.opacity(0.9))
                
                // Countdown timer
                Text(viewModel.formattedCheckInTimeRemaining)
                    .font(.system(size: 96, weight: .light, design: .rounded))
                    .foregroundStyle(checkInTimeColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: viewModel.checkInSecondsElapsed)
                
                Button {
                    viewModel.goBackFromCheckIn()
                    publishActiveSessionState()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body)
                        .foregroundStyle(.teal.opacity(0.5))
                }
                .buttonStyle(.plain)
                
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
                    
                    Text("Max \(formattedCheckInDurationLimit) recommended")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .padding(.top, 8)
                
                // Done checking button
                Button {
                    viewModel.finishCheckIn(modelContext: modelContext)
                    refreshLocalSessions()
                    publishActiveSessionState()
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
    
    private func persistCompletedSession(_ draft: CompletedSessionDraft, action: String) -> SleepSession? {
        let storedSession = StoredSleepSession(
            syncID: draft.syncID,
            nightNumber: draft.nightNumber,
            date: draft.date,
            startTime: draft.startTime,
            endTime: draft.endTime,
            fellAsleep: draft.fellAsleep,
            notes: nil,
            checkIns: draft.checkIns.map { draftCheckIn in
                StoredCheckIn(
                    syncID: draftCheckIn.syncID,
                    timestamp: draftCheckIn.timestamp,
                    intervalMinutes: draftCheckIn.intervalMinutes,
                    checkInNumber: draftCheckIn.checkInNumber,
                    endTime: draftCheckIn.endTime,
                    notes: draftCheckIn.notes
                )
            }
        )
        LocalSessionStore.upsert(storedSession)
        
        print("Local JSON save succeeded during \(action). Local session count: \(LocalSessionStore.load().count)")
        return storedSession.makeSleepSession()
    }
    
    private func syncHouseholdIfConfigured() {
        let code = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        
        Task {
            _ = try? await CloudKitSyncManager.shared.sync(
                householdCode: code,
                modelContext: modelContext
            )
            refreshLocalSessions()
        }
    }
    
    private func pollActiveSessionWhileNeeded() async {
        while !Task.isCancelled {
            if scenePhase == .active {
                await refreshActiveSessionFromCloud()
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
    
    private func refreshActiveSessionFromCloud() async {
        guard let code = normalizedHouseholdCode else { return }
        guard let sharedState = try? await CloudKitSyncManager.shared.fetchActiveSession(householdCode: code) else { return }
        
        if let lastSharedActiveSessionUpdate, sharedState.updatedAt <= lastSharedActiveSessionUpdate {
            return
        }
        
        lastSharedActiveSessionUpdate = sharedState.updatedAt
        currentNight = sharedState.nightNumber
        viewModel.loadNightConfiguration(modelContext: modelContext)
        viewModel.applySharedActiveSessionState(sharedState, modelContext: modelContext)
        refreshLocalSessions()
        
        if sharedState.phase == .ended || sharedState.phase == .cancelled {
            syncHouseholdIfConfigured()
        }
    }
    
    private func publishActiveSessionState() {
        publishActiveSessionState(viewModel.makeSharedActiveSessionState())
    }
    
    private func publishActiveSessionState(_ sharedState: SharedActiveSessionState?) {
        guard let code = normalizedHouseholdCode else { return }
        guard let sharedState else { return }
        
        lastSharedActiveSessionUpdate = sharedState.updatedAt
        Task {
            try? await CloudKitSyncManager.shared.saveActiveSession(sharedState, householdCode: code)
        }
    }
    
    private var normalizedHouseholdCode: String? {
        let code = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? nil : code
    }
    
    // MARK: - Bottom Actions
    
    @ViewBuilder
    private var bottomActions: some View {
        if viewModel.state != .idle {
            VStack(spacing: 16) {
                // Baby fell asleep button - prominent but requires deliberate tap
                Button {
                    let endedState = viewModel.makeSharedEndedSessionState(phase: .ended)
                    if let draft = viewModel.finishSessionDraft(fellAsleep: true),
                       let session = persistCompletedSession(draft, action: "baby fell asleep") {
                        saveRecentSessionSummary(RecentSessionSummary(session: session))
                    }
                    refreshLocalSessions()
                    publishActiveSessionState(endedState)
                    syncHouseholdIfConfigured()
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
