import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized: Bool = false
    
    private init() {
        Task {
            await checkAuthorization()
        }
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }
    
    @discardableResult
    func requestPermission() async -> Bool {
        await requestAuthorization()
    }
    
    func registerCategories() {
        let checkInCategory = UNNotificationCategory(
            identifier: "CHECK_IN_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let leaveRoomCategory = UNNotificationCategory(
            identifier: "LEAVE_ROOM_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([checkInCategory, leaveRoomCategory])
    }
    
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    func scheduleCheckNotification(afterSeconds seconds: TimeInterval, checkNumber: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Check"
        content.body = "Check #\(checkNumber) - Time to briefly comfort your baby"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "CHECK_IN_REMINDER"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "check-\(checkNumber)-\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleLeaveRoomNotification(afterSeconds seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Leave"
        content.body = "Wrap up this check-in and leave the room."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "LEAVE_ROOM_REMINDER"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "leave-room-\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule leave-room notification: \(error)")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func triggerImpactFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
