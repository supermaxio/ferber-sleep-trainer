import CloudKit
import Foundation
import SwiftData

@MainActor
final class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()
    
    private let recordType = "HouseholdSession"
    private let activeSessionRecordType = "HouseholdActiveSession"
    private let database = CKContainer.default().publicCloudDatabase
    
    private init() { }
    
    func sync(householdCode: String, modelContext: ModelContext) async throws -> SyncResult {
        let normalizedCode = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            throw CloudKitSyncError.missingHouseholdCode
        }
        
        let localSessions = LocalSessionStore.load().map { $0.makeSleepSession() }
        var localSessionsBySyncID: [String: SleepSession] = [:]
        
        for session in localSessions {
            if session.syncID == nil {
                session.syncID = UUID().uuidString
            }
            if let syncID = session.syncID {
                localSessionsBySyncID[syncID] = session
            }
        }
        let remoteRecords = try await fetchRemoteSessionRecords(householdCode: normalizedCode)
        var remoteSyncIDs = Set(remoteRecords.compactMap { $0["syncID"] as? String })
        var importedCount = 0
        var uploadedCount = 0
        
        for record in remoteRecords {
            guard let syncID = record["syncID"] as? String else { continue }
            guard record["endTime"] as? Date != nil else { continue }
            
            if localSessionsBySyncID[syncID] == nil {
                let session = try session(from: record)
                LocalSessionStore.upsert(storedSession(from: session))
                localSessionsBySyncID[syncID] = session
                importedCount += 1
            }
        }
        
        for session in localSessions {
            guard let syncID = session.syncID else { continue }
            guard session.endTime != nil else { continue }
            guard !remoteSyncIDs.contains(syncID) else { continue }
            
            let uploadResult = try await uploadSessionIfNeeded(
                session,
                householdCode: normalizedCode,
                syncID: syncID
            )
            if uploadResult == .created {
                uploadedCount += 1
                remoteSyncIDs.insert(syncID)
            }
        }
        
        return SyncResult(importedCount: importedCount, uploadedCount: uploadedCount)
    }
    
    func saveActiveSession(_ activeSession: SharedActiveSessionState, householdCode: String) async throws {
        let normalizedCode = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            throw CloudKitSyncError.missingHouseholdCode
        }
        
        let timestamp = Int(activeSession.updatedAt.timeIntervalSince1970 * 1000)
        let recordID = CKRecord.ID(recordName: "active-\(normalizedCode)-\(activeSession.sessionID)-\(timestamp)-\(UUID().uuidString)")
        let record = CKRecord(recordType: activeSessionRecordType, recordID: recordID)
        populateActiveSessionRecord(record, with: activeSession, householdCode: normalizedCode)
        
        _ = try await database.save(record)
    }
    
    func fetchActiveSession(householdCode: String) async throws -> SharedActiveSessionState? {
        let normalizedCode = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            throw CloudKitSyncError.missingHouseholdCode
        }
        
        do {
            let predicate = NSPredicate(format: "householdCode == %@", normalizedCode)
            let query = CKQuery(recordType: activeSessionRecordType, predicate: predicate)
            let result = try await database.records(matching: query, resultsLimit: 100)
            let records = result.matchResults.compactMap { _, recordResult in
                try? recordResult.get()
            }
            guard let latestRecord = records.max(by: { first, second in
                let firstDate = first["updatedAt"] as? Date ?? .distantPast
                let secondDate = second["updatedAt"] as? Date ?? .distantPast
                return firstDate < secondDate
            }) else {
                return nil
            }
            return try activeSession(from: latestRecord)
        } catch {
            return try await fetchLegacyActiveSession(householdCode: normalizedCode)
        }
    }
    
    func clearActiveSession(householdCode: String) async throws {
        let normalizedCode = householdCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            throw CloudKitSyncError.missingHouseholdCode
        }
        
        do {
            _ = try await database.deleteRecord(withID: activeSessionRecordID(householdCode: normalizedCode))
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }
    
    private func fetchRemoteSessionRecords(householdCode: String) async throws -> [CKRecord] {
        do {
            let predicate = NSPredicate(format: "householdCode == %@", householdCode)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
            
            let result = try await database.records(matching: query, resultsLimit: 200)
            return result.matchResults.compactMap { _, recordResult in
                try? recordResult.get()
            }
        } catch {
            return await fetchRemoteSessionRecordsFromManifest(householdCode: householdCode)
        }
    }
    
    private func fetchRemoteSessionRecordsFromManifest(householdCode: String) async -> [CKRecord] {
        guard let manifest = try? await database.record(for: CKRecord.ID(recordName: "household-\(householdCode)")) else {
            return []
        }
        let syncIDs = manifest["sessionSyncIDs"] as? [String] ?? []
        var records: [CKRecord] = []
        
        for syncID in syncIDs {
            let recordID = CKRecord.ID(recordName: "\(householdCode)-\(syncID)")
            if let record = try? await database.record(for: recordID) {
                records.append(record)
            }
        }
        
        return records
    }
    
    private func fetchLegacyActiveSession(householdCode: String) async throws -> SharedActiveSessionState? {
        do {
            let record = try await database.record(for: activeSessionRecordID(householdCode: householdCode))
            return try activeSession(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
    
    private func populateActiveSessionRecord(_ record: CKRecord, with activeSession: SharedActiveSessionState, householdCode: String) {
        record["householdCode"] = householdCode as NSString
        record["sessionID"] = activeSession.sessionID as NSString
        record["phase"] = activeSession.phase.rawValue as NSString
        record["nightNumber"] = NSNumber(value: activeSession.nightNumber)
        record["sessionStartTime"] = activeSession.sessionStartTime as NSDate
        record["stateStartedAt"] = activeSession.stateStartedAt as NSDate
        record["intervalSeconds"] = NSNumber(value: activeSession.intervalSeconds)
        record["checkInNumber"] = NSNumber(value: activeSession.checkInNumber)
        record["maxCheckInDuration"] = NSNumber(value: activeSession.maxCheckInDuration)
        record["updatedAt"] = activeSession.updatedAt as NSDate
    }
    
    private func activeSessionRecordID(householdCode: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "active-\(householdCode)")
    }
    
    private func activeSession(from record: CKRecord) throws -> SharedActiveSessionState {
        guard let sessionID = record["sessionID"] as? String,
              let phaseValue = record["phase"] as? String,
              let phase = SharedActiveSessionPhase(rawValue: phaseValue),
              let nightNumber = intValue(for: "nightNumber", in: record),
              let sessionStartTime = record["sessionStartTime"] as? Date,
              let stateStartedAt = record["stateStartedAt"] as? Date,
              let intervalSeconds = intValue(for: "intervalSeconds", in: record),
              let checkInNumber = intValue(for: "checkInNumber", in: record),
              let maxCheckInDuration = intValue(for: "maxCheckInDuration", in: record),
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitSyncError.invalidRecord
        }
        
        return SharedActiveSessionState(
            sessionID: sessionID,
            phase: phase,
            nightNumber: nightNumber,
            sessionStartTime: sessionStartTime,
            stateStartedAt: stateStartedAt,
            intervalSeconds: intervalSeconds,
            checkInNumber: checkInNumber,
            maxCheckInDuration: maxCheckInDuration,
            updatedAt: updatedAt
        )
    }
    
    private enum SessionUploadResult {
        case created
        case alreadyExists
    }
    
    private func uploadSessionIfNeeded(_ session: SleepSession, householdCode: String, syncID: String) async throws -> SessionUploadResult {
        let recordID = CKRecord.ID(recordName: "\(householdCode)-\(syncID)")
        do {
            _ = try await database.record(for: recordID)
            return .alreadyExists
        } catch let error as CKError {
            guard error.code == .unknownItem else { throw error }
        }
        
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["householdCode"] = householdCode as NSString
        record["syncID"] = syncID as NSString
        record["nightNumber"] = NSNumber(value: session.nightNumber)
        record["date"] = session.date as NSDate
        record["startTime"] = session.startTime as NSDate
        record["fellAsleep"] = NSNumber(value: session.fellAsleep)
        record["checkInsJSON"] = checkInsJSON(from: session.checkIns) as NSString
        
        if let endTime = session.endTime {
            record["endTime"] = endTime as NSDate
        }
        if let notes = session.notes {
            record["notes"] = notes as NSString
        }
        
        do {
            _ = try await database.save(record)
            return .created
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .batchRequestFailed || error.code == .partialFailure || error.code == .permissionFailure {
            return .alreadyExists
        }
    }
    
    private func session(from record: CKRecord) throws -> SleepSession {
        guard let syncID = record["syncID"] as? String,
              let nightNumber = intValue(for: "nightNumber", in: record),
              let date = record["date"] as? Date,
              let startTime = record["startTime"] as? Date else {
            throw CloudKitSyncError.invalidRecord
        }
        
        let endTime = record["endTime"] as? Date
        let fellAsleep = boolValue(for: "fellAsleep", in: record)
        let notes = record["notes"] as? String
        let checkInsJSON = record["checkInsJSON"] as? String ?? "[]"
        let checkIns = try checkIns(from: checkInsJSON)
        let session = SleepSession(
            nightNumber: nightNumber,
            date: date,
            startTime: startTime,
            endTime: endTime,
            fellAsleep: fellAsleep,
            notes: notes,
            checkIns: checkIns
        )
        session.syncID = syncID
        return session
    }
    
    private func update(_ session: SleepSession, from record: CKRecord) throws {
        guard let nightNumber = intValue(for: "nightNumber", in: record),
              let date = record["date"] as? Date,
              let startTime = record["startTime"] as? Date else {
            throw CloudKitSyncError.invalidRecord
        }
        
        session.nightNumber = nightNumber
        session.date = date
        session.startTime = startTime
        session.endTime = record["endTime"] as? Date
        session.fellAsleep = boolValue(for: "fellAsleep", in: record)
        session.notes = record["notes"] as? String
        
        let checkInsJSON = record["checkInsJSON"] as? String ?? "[]"
        let remoteCheckIns = try checkIns(from: checkInsJSON)
        
        for remoteCheckIn in remoteCheckIns {
            if let localCheckIn = session.checkIns.first(where: { $0.checkInNumber == remoteCheckIn.checkInNumber }) {
                localCheckIn.syncID = remoteCheckIn.syncID
                localCheckIn.timestamp = remoteCheckIn.timestamp
                localCheckIn.intervalMinutes = remoteCheckIn.intervalMinutes
                localCheckIn.endTime = remoteCheckIn.endTime
                localCheckIn.notes = remoteCheckIn.notes
            } else {
                session.checkIns.append(remoteCheckIn)
            }
        }
    }
    
    private func storedSession(from session: SleepSession) -> StoredSleepSession {
        StoredSleepSession(
            syncID: session.syncID ?? UUID().uuidString,
            nightNumber: session.nightNumber,
            date: session.date,
            startTime: session.startTime,
            endTime: session.endTime,
            fellAsleep: session.fellAsleep,
            notes: session.notes,
            checkIns: session.checkIns.map { checkIn in
                StoredCheckIn(
                    syncID: checkIn.syncID ?? UUID().uuidString,
                    timestamp: checkIn.timestamp,
                    intervalMinutes: checkIn.intervalMinutes,
                    checkInNumber: checkIn.checkInNumber,
                    endTime: checkIn.endTime,
                    notes: checkIn.notes
                )
            }
        )
    }
    
    private func checkInsJSON(from checkIns: [CheckIn]) -> String {
        let payload = checkIns.sorted { $0.checkInNumber < $1.checkInNumber }.map { checkIn in
            SyncedCheckIn(
                syncID: checkIn.syncID ?? UUID().uuidString,
                timestamp: checkIn.timestamp,
                intervalMinutes: checkIn.intervalMinutes,
                checkInNumber: checkIn.checkInNumber,
                endTime: checkIn.endTime,
                notes: checkIn.notes
            )
        }
        guard let data = try? JSONEncoder().encode(payload) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
    
    private func checkIns(from json: String) throws -> [CheckIn] {
        guard let data = json.data(using: .utf8) else { return [] }
        let payload = try JSONDecoder().decode([SyncedCheckIn].self, from: data)
        return payload.map { synced in
            let checkIn = CheckIn(
                timestamp: synced.timestamp,
                intervalMinutes: synced.intervalMinutes,
                checkInNumber: synced.checkInNumber,
                endTime: synced.endTime,
                notes: synced.notes
            )
            checkIn.syncID = synced.syncID
            return checkIn
        }
    }
    
    private func intValue(for key: String, in record: CKRecord) -> Int? {
        if let value = record[key] as? Int {
            return value
        }
        if let value = record[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }
    
    private func boolValue(for key: String, in record: CKRecord) -> Bool {
        if let value = record[key] as? Bool {
            return value
        }
        if let value = record[key] as? NSNumber {
            return value.boolValue
        }
        return false
    }
}

struct SyncResult {
    let importedCount: Int
    let uploadedCount: Int
}

struct SyncedCheckIn: Codable {
    let syncID: String
    let timestamp: Date
    let intervalMinutes: Int
    let checkInNumber: Int
    let endTime: Date?
    let notes: String?
}

enum SharedActiveSessionPhase: String, Codable, Equatable {
    case waiting
    case checkIn
    case ended
    case cancelled
}

struct SharedActiveSessionState: Codable, Equatable {
    let sessionID: String
    let phase: SharedActiveSessionPhase
    let nightNumber: Int
    let sessionStartTime: Date
    let stateStartedAt: Date
    let intervalSeconds: Int
    let checkInNumber: Int
    let maxCheckInDuration: Int
    let updatedAt: Date
}

enum CloudKitSyncError: LocalizedError {
    case missingHouseholdCode
    case invalidRecord
    
    var errorDescription: String? {
        switch self {
        case .missingHouseholdCode:
            return "Create or enter a household code before syncing."
        case .invalidRecord:
            return "A synced session was missing required fields."
        }
    }
}
