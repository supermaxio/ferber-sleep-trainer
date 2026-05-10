import Foundation
import SwiftData

/// Represents a single check-in during a sleep training session
@Model
final class CheckIn {
    var timestamp: Date
    var intervalMinutes: Int // Scheduled interval before this check-in (in minutes)
    var checkInNumber: Int
    var endTime: Date?
    var notes: String?
    
    var session: SleepSession?
    
    init(timestamp: Date = Date(), intervalMinutes: Int, checkInNumber: Int, endTime: Date? = nil, notes: String? = nil) {
        self.timestamp = timestamp
        self.intervalMinutes = intervalMinutes
        self.checkInNumber = checkInNumber
        self.endTime = endTime
        self.notes = notes
    }
    
    /// Duration of the check-in (how long parent was in room)
    var checkInDuration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(timestamp)
    }
    
    /// Formatted check-in duration string (e.g., "45 sec")
    var formattedCheckInDuration: String {
        guard let duration = checkInDuration else { return "--" }
        let seconds = Int(duration)
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds) sec"
    }
    
    /// Formatted interval string (e.g., "3 min")
    var formattedInterval: String {
        return "\(intervalMinutes) min"
    }
}

/// Represents a complete sleep training session (one night)
@Model
final class SleepSession {
    var nightNumber: Int
    var date: Date
    var startTime: Date
    var endTime: Date? // When session ended (either fell asleep or cancelled)
    var fellAsleep: Bool // True if baby fell asleep, false if session was cancelled
    var notes: String?
    
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.session)
    var checkIns: [CheckIn]
    
    init(nightNumber: Int, date: Date = Date(), startTime: Date = Date(), endTime: Date? = nil, fellAsleep: Bool = false, notes: String? = nil, checkIns: [CheckIn] = []) {
        self.nightNumber = nightNumber
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.fellAsleep = fellAsleep
        self.notes = notes
        self.checkIns = checkIns
    }
    
    /// Total time from start to when baby fell asleep
    var totalDurationToSleep: TimeInterval? {
        guard let endTime = endTime, fellAsleep else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Whether session was completed (baby fell asleep)
    var isCompleted: Bool {
        fellAsleep && endTime != nil
    }
    
    /// Formatted total duration string
    var formattedTotalDuration: String {
        guard let duration = totalDurationToSleep else { return "--" }
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes) min"
    }
    
    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Formatted start time
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    /// Formatted end time
    var formattedEndTime: String {
        guard let endTime = endTime else { return "--" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endTime)
    }
    
    /// Number of check-ins for this session
    var checkInCount: Int {
        checkIns.count
    }
    
    /// Average check-in duration for this session
    var averageCheckInDuration: TimeInterval? {
        let durations = checkIns.compactMap { $0.checkInDuration }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
}

/// Configuration for Ferber intervals per night
@Model
final class NightConfiguration {
    var nightNumber: Int
    var firstInterval: Int  // First wait time (in minutes)
    var secondInterval: Int
    var thirdInterval: Int
    var subsequentInterval: Int // Max interval for all subsequent check-ins
    
    init(nightNumber: Int, firstInterval: Int, secondInterval: Int, thirdInterval: Int, subsequentInterval: Int) {
        self.nightNumber = nightNumber
        self.firstInterval = firstInterval
        self.secondInterval = secondInterval
        self.thirdInterval = thirdInterval
        self.subsequentInterval = subsequentInterval
    }
    
    /// Get intervals array for a specific night
    var intervals: [Int] {
        [firstInterval, secondInterval, thirdInterval, subsequentInterval]
    }
    
    /// Standard Ferber method intervals for a given night (returns array of minutes)
    static func defaultIntervals(for night: Int) -> [Int] {
        switch night {
        case 1: return [3, 5, 10, 10]      // Night 1: 3, 5, 10, 10+ min
        case 2: return [5, 10, 12, 12]     // Night 2: 5, 10, 12, 12+ min
        case 3: return [10, 12, 15, 15]    // Night 3: 10, 12, 15, 15+ min
        case 4: return [12, 15, 18, 18]    // Night 4: 12, 15, 18, 18+ min
        case 5: return [15, 18, 20, 20]    // Night 5: 15, 18, 20, 20+ min
        case 6: return [18, 20, 25, 25]    // Night 6: 18, 20, 25, 25+ min
        case 7: return [20, 25, 30, 30]    // Night 7: 20, 25, 30, 30+ min
        default: return [20, 25, 30, 30]   // Night 8+: same as night 7
        }
    }
    
    /// Get all default configurations
    static func defaultConfigurations() -> [NightConfiguration] {
        return (1...7).map { night in
            let intervals = defaultIntervals(for: night)
            return NightConfiguration(
                nightNumber: night,
                firstInterval: intervals[0],
                secondInterval: intervals[1],
                thirdInterval: intervals[2],
                subsequentInterval: intervals[3]
            )
        }
    }
}
