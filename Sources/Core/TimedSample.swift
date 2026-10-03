import Foundation

/// Geçmiş grafikleri için zaman damgalı tek bir ölçüm.
struct TimedSample<Value: Sendable>: Sendable {
    let date: Date
    let value: Value
}
