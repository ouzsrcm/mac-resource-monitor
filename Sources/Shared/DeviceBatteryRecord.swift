import CloudKit
import Foundation

/// Bir cihazın iCloud özel veritabanındaki pil kaydı.
/// Kayıt tipi `DeviceBattery`; `recordName` cihaz kimliğidir, bu yüzden her cihazın tek kaydı vardır.
struct DeviceBatteryRecord: Identifiable, Sendable, Equatable {
    static let recordType = "DeviceBattery"
    /// Bundan eski kayıtlar sorgulanmaz ve listede gösterilmez.
    static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    enum Platform {
        static let macOS = "macOS"
        static let iOS = "iOS"
        static let iPadOS = "iPadOS"
        static let watchOS = "watchOS"
    }

    enum Field {
        static let deviceId = "deviceId"
        static let deviceName = "deviceName"
        static let deviceModel = "deviceModel"
        static let platform = "platform"
        static let level = "level"
        static let isCharging = "isCharging"
        static let updatedAt = "updatedAt"

        static let all: [CKRecord.FieldKey] = [
            deviceId, deviceName, deviceModel, platform, level, isCharging, updatedAt,
        ]
    }

    var deviceId: String
    var deviceName: String
    var deviceModel: String
    /// `macOS`, `iOS`, `iPadOS` veya `watchOS`.
    var platform: String
    /// 0.0–1.0
    var level: Double
    /// 0 veya 1. CloudKit alanı tam sayı tutulur.
    var isCharging: Int64
    var updatedAt: Date

    var id: String { deviceId }

    var percent: Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    init(
        deviceId: String,
        deviceName: String,
        deviceModel: String,
        platform: String,
        level: Double,
        isCharging: Int64,
        updatedAt: Date
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.platform = platform
        self.level = level
        self.isCharging = isCharging
        self.updatedAt = updatedAt
    }

    init?(record: CKRecord) {
        let deviceId = Self.string(record, Field.deviceId) ?? record.recordID.recordName
        guard !deviceId.isEmpty,
              let deviceName = Self.string(record, Field.deviceName),
              let deviceModel = Self.string(record, Field.deviceModel),
              let platform = Self.string(record, Field.platform),
              let level = Self.double(record, Field.level),
              let isCharging = Self.int64(record, Field.isCharging),
              let updatedAt = Self.date(record, Field.updatedAt)
        else { return nil }

        self.init(
            deviceId: deviceId,
            deviceName: deviceName,
            deviceModel: deviceModel,
            platform: platform,
            level: level,
            isCharging: isCharging,
            updatedAt: updatedAt
        )
    }

    /// `recordName` cihaz kimliğidir; aynı cihazın sonraki yazmaları bu kaydın üzerine gider.
    func makeRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: deviceId))
        write(into: record)
        return record
    }

    func write(into record: CKRecord) {
        record[Field.deviceId] = deviceId
        record[Field.deviceName] = deviceName
        record[Field.deviceModel] = deviceModel
        record[Field.platform] = platform
        record[Field.level] = level
        record[Field.isCharging] = isCharging
        record[Field.updatedAt] = updatedAt
    }

    private static func string(_ record: CKRecord, _ key: CKRecord.FieldKey) -> String? {
        if let value: String = record[key] { return value }
        return record.object(forKey: key) as? String
    }

    private static func double(_ record: CKRecord, _ key: CKRecord.FieldKey) -> Double? {
        if let value: Double = record[key] { return value }
        return (record.object(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func int64(_ record: CKRecord, _ key: CKRecord.FieldKey) -> Int64? {
        if let value: Int64 = record[key] { return value }
        if let value: Int = record[key] { return Int64(value) }
        return (record.object(forKey: key) as? NSNumber)?.int64Value
    }

    private static func date(_ record: CKRecord, _ key: CKRecord.FieldKey) -> Date? {
        if let value: Date = record[key] { return value }
        return record.object(forKey: key) as? Date
    }
}
