import CloudKit
import Foundation
import os

/// iCloud hesap durumu. `.unknown` henüz sorulmadığı anlamına gelir; diğerleri `CKAccountStatus` karşılığıdır.
enum iCloudAccountStatus: Sendable, Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

enum CloudWriteResult: Sendable {
    case saved
    /// `retryAfterSeconds` dolana kadar yeni CloudKit çağrısı yapılmamalı.
    case notNow(until: Date)
    case failed
}

enum CloudFetchResult: Sendable {
    case records([DeviceBatteryRecord])
    case failed
}

/// Kullanıcının kendi iCloud özel veritabanına cihaz pili yazar ve oradan okur.
/// Public veya shared veritabanı kullanılmaz. Ağ, kota ve geçici hatalar yutulur.
actor BatterySyncService {
    static let containerIdentifier = "iCloud.tr.ouzsrcm.MenuMonitor"

    private let containerIdentifier: String
    private var container: CKContainer?
    private var database: CKDatabase?
    /// Kota veya servis `retryAfterSeconds` verdiyse bu ana kadar yeni istek gitmez.
    private var backoffUntil: Date?
    private let logger = Logger(subsystem: "tr.ouzsrcm.MenuMonitor", category: "cloudkit")

    init(containerIdentifier: String = BatterySyncService.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    /// İlk gerçek istekte özel veritabanı istemcisini kurar.
    /// Senkron ayarı kapalıyken bu yol hiç çalışmaz; public veritabanına bağlanılmaz.
    private func open() -> (container: CKContainer, database: CKDatabase) {
        if let container, let database {
            return (container, database)
        }
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        self.container = container
        self.database = database
        return (container, database)
    }

    /// Bekleme süresi dolmadıysa o anı döndürür. Bu bir ağ çağrısı değildir.
    func backoffDeadline() -> Date? {
        guard let backoffUntil, Date() < backoffUntil else { return nil }
        return backoffUntil
    }

    func accountStatus() async -> iCloudAccountStatus {
        do {
            // Kullanıcının bu container için iCloud oturumunu sorar.
            // Giriş yoksa yazma ve sorgulama yapılmaz.
            let status = try await open().container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .couldNotDetermine
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            note(error, context: "iCloud hesap durumu alınamadı")
            return .couldNotDetermine
        }
    }

    func upsert(_ payload: DeviceBatteryRecord) async -> CloudWriteResult {
        if let until = backoffDeadline() {
            return .notNow(until: until)
        }
        let status = await accountStatus()
        guard status == .available else { return .failed }
        return await save(payload.makeRecord(), payload: payload, allowConflictRetry: true)
    }

    /// `since` verilmezse son 7 günün kayıtları, `updatedAt` azalan sırada gelir.
    func fetchAll(since: Date = Date().addingTimeInterval(-DeviceBatteryRecord.recentWindow)) async -> CloudFetchResult {
        if backoffDeadline() != nil {
            return .failed
        }
        let status = await accountStatus()
        guard status == .available else { return .failed }

        let predicate = NSPredicate(format: "%K > %@", DeviceBatteryRecord.Field.updatedAt, since as NSDate)
        let query = CKQuery(recordType: DeviceBatteryRecord.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: DeviceBatteryRecord.Field.updatedAt, ascending: false)]

        var collected: [DeviceBatteryRecord] = []
        do {
            // Özel veritabanında eşiği geçen DeviceBattery kayıtlarını sayfa sayfa okur.
            var page = try await open().database.records(
                matching: query,
                desiredKeys: DeviceBatteryRecord.Field.all,
                resultsLimit: CKQueryOperation.maximumResults
            )
            var pageCount = 0
            while pageCount < 20 {
                pageCount += 1
                append(page.matchResults, to: &collected)
                guard let cursor = page.queryCursor else { break }
                // İmleç varsa aynı sorgunun sonraki sayfasını ister.
                page = try await open().database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: DeviceBatteryRecord.Field.all,
                    resultsLimit: CKQueryOperation.maximumResults
                )
            }
        } catch {
            note(error, context: "Pil kayıtları sorgulanamadı")
            return .failed
        }

        backoffUntil = nil
        collected.sort { $0.updatedAt > $1.updatedAt }
        return .records(collected)
    }

    private func save(_ record: CKRecord, payload: DeviceBatteryRecord, allowConflictRetry: Bool) async -> CloudWriteResult {
        do {
            // recordName = deviceId olduğu için bu çağrı cihazın tek kaydını oluşturur veya üzerine yazar.
            // changedKeys yalnızca değişen alanları gönderir.
            let outcome = try await open().database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
            for (_, result) in outcome.saveResults {
                if case .failure(let error) = result {
                    return await handleSaveError(error, payload: payload, allowConflictRetry: allowConflictRetry)
                }
            }
            backoffUntil = nil
            logger.info("Cihaz pili iCloud'a yazıldı.")
            return .saved
        } catch {
            return await handleSaveError(error, payload: payload, allowConflictRetry: allowConflictRetry)
        }
    }

    private func handleSaveError(
        _ error: Error,
        payload: DeviceBatteryRecord,
        allowConflictRetry: Bool
    ) async -> CloudWriteResult {
        if allowConflictRetry, isServerRecordChanged(error) {
            guard let server = await conflictedServerRecord(from: error, deviceId: payload.deviceId) else {
                note(error, context: "Pil kaydı yazılamadı")
                return failureResult(for: error)
            }
            // Sunucudaki change tag bizdekinden yeni. Kendi alanlarımızı o kopyanın üzerine yazıp bir kez daha deneriz.
            payload.write(into: server)
            return await save(server, payload: payload, allowConflictRetry: false)
        }
        note(error, context: "Pil kaydı yazılamadı")
        return failureResult(for: error)
    }

    private func append(
        _ matches: [(CKRecord.ID, Result<CKRecord, Error>)],
        to collected: inout [DeviceBatteryRecord]
    ) {
        for (_, result) in matches {
            switch result {
            case .success(let record):
                if let parsed = DeviceBatteryRecord(record: record) {
                    collected.append(parsed)
                }
            case .failure(let error):
                note(error, context: "Pil kaydı okunamadı")
            }
        }
    }

    private func conflictedServerRecord(from error: Error, deviceId: String) async -> CKRecord? {
        if let server = serverRecord(from: error) {
            return server
        }
        guard isServerRecordChanged(error) else { return nil }
        do {
            // Hata sunucu kopyasını taşımıyorsa aynı kaydı özel veritabanından okuruz.
            return try await open().database.record(for: CKRecord.ID(recordName: deviceId))
        } catch {
            note(error, context: "Çakışan pil kaydı okunamadı")
            return nil
        }
    }

    private func serverRecord(from error: Error) -> CKRecord? {
        guard let ckError = error as? CKError else { return nil }
        if let server = ckError.serverRecord {
            return server
        }
        if let partials = ckError.partialErrorsByItemID {
            for item in partials.values {
                if let server = serverRecord(from: item) {
                    return server
                }
            }
        }
        return nil
    }

    private func isServerRecordChanged(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged { return true }
        if let partials = ckError.partialErrorsByItemID {
            return partials.values.contains { isServerRecordChanged($0) }
        }
        return false
    }

    private func failureResult(for error: Error) -> CloudWriteResult {
        if let until = backoffUntil, Date() < until {
            return .notNow(until: until)
        }
        return .failed
    }

    private func note(_ error: Error, context: String) {
        if Task.isCancelled || error is CancellationError { return }
        if let seconds = retryAfterSeconds(in: error), seconds > 0 {
            backoffUntil = Date().addingTimeInterval(seconds)
            logger.error("\(context, privacy: .public). \(seconds, privacy: .public) sn beklenecek: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("\(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func retryAfterSeconds(in error: Error) -> Double? {
        guard let ckError = error as? CKError else { return nil }
        if let seconds = ckError.retryAfterSeconds, seconds > 0 {
            return seconds
        }
        if let partials = ckError.partialErrorsByItemID {
            return partials.values.compactMap { retryAfterSeconds(in: $0) }.max()
        }
        return nil
    }
}
