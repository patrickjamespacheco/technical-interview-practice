import Foundation

public struct Plan: Equatable, Sendable {
    public let requestsPerMinute: Int?
    public let requestsPerDay: Int?
    public init(requestsPerMinute: Int?, requestsPerDay: Int?) {
        self.requestsPerMinute = requestsPerMinute
        self.requestsPerDay = requestsPerDay
    }
}

public struct Usage: Equatable, Sendable {
    public let keyID: String
    public let planID: String
    public let minuteUsed: Int
    public let minuteLimit: Int?
    public let dayUsed: Int
    public let dayLimit: Int?
    public init(keyID: String, planID: String, minuteUsed: Int, minuteLimit: Int?, dayUsed: Int, dayLimit: Int?) {
        self.keyID = keyID; self.planID = planID; self.minuteUsed = minuteUsed
        self.minuteLimit = minuteLimit; self.dayUsed = dayUsed; self.dayLimit = dayLimit
    }
}

public enum DenialReason: Equatable, Sendable {
    case keyNotFound(keyID: String)
    case keyDisabled(keyID: String)
    case perMinuteExceeded(limit: Int, used: Int)
    case perDayExceeded(limit: Int, used: Int)
}

public enum RateLimitDecision: Equatable, Sendable {
    case allowed(Usage)
    case denied(DenialReason)
}

public struct APIKeySnapshot: Equatable, Sendable {
    public let id: String
    public let owner: String
    public let planID: String
    public let isEnabled: Bool
    public let requestDates: [Date]
    public init(id: String, owner: String, planID: String, isEnabled: Bool, requestDates: [Date]) {
        self.id = id; self.owner = owner; self.planID = planID
        self.isEnabled = isEnabled; self.requestDates = requestDates
    }
}

public enum APIRateLimiterError: Error, Equatable, Sendable {
    case duplicateKey(String)
    case unknownKey(String)
    case unknownPlan(String)
    case notImplemented
}

public actor APIRateLimiter {
    /// Internal record. Callers only ever see the immutable `APIKeySnapshot`.
    private struct KeyRecord {
        let id: String
        let owner: String
        var planID: String
        var isEnabled: Bool
        var requestDates: [Date]
    }

    private static let minute: TimeInterval = 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let retention: TimeInterval = 25 * 60 * 60

    private let plans: [String: Plan]
    private let now: @Sendable () -> Date
    private var keys: [String: KeyRecord] = [:]

    public init(plans: [String: Plan], now: @escaping @Sendable () -> Date) {
        self.plans = plans
        self.now = now
    }

    // MARK: Part 1 — keys and rich rate decisions

    public func createKey(id: String, owner: String, planID: String) throws(APIRateLimiterError) {
        guard keys[id] == nil else { throw .duplicateKey(id) }
        guard plans[planID] != nil else { throw .unknownPlan(planID) }
        keys[id] = KeyRecord(id: id, owner: owner, planID: planID, isEnabled: true, requestDates: [])
    }

    public func revokeKey(_ keyID: String) throws(APIRateLimiterError) {
        guard keys[keyID] != nil else { throw .unknownKey(keyID) }
        keys[keyID]!.isEnabled = false
    }

    public func updatePlan(for keyID: String, to planID: String) throws(APIRateLimiterError) {
        guard keys[keyID] != nil else { throw .unknownKey(keyID) }
        guard plans[planID] != nil else { throw .unknownPlan(planID) }
        keys[keyID]!.planID = planID
    }

    public func evaluate(_ keyID: String, at date: Date? = nil) -> RateLimitDecision {
        let instant = date ?? now()
        guard let record = keys[keyID] else { return .denied(.keyNotFound(keyID: keyID)) }
        guard record.isEnabled else { return .denied(.keyDisabled(keyID: keyID)) }
        let usage = makeUsage(for: record, at: instant)
        // The minute window is the tighter, more actionable limit, so it wins.
        if let limit = usage.minuteLimit, usage.minuteUsed >= limit {
            return .denied(.perMinuteExceeded(limit: limit, used: usage.minuteUsed))
        }
        if let limit = usage.dayLimit, usage.dayUsed >= limit {
            return .denied(.perDayExceeded(limit: limit, used: usage.dayUsed))
        }
        return .allowed(usage)
    }

    /// Shared by `evaluate` and `usage(for:at:)` so counting lives in one place.
    private func makeUsage(for record: KeyRecord, at instant: Date) -> Usage {
        let plan = plans[record.planID] ?? Plan(requestsPerMinute: nil, requestsPerDay: nil)
        return Usage(
            keyID: record.id,
            planID: record.planID,
            minuteUsed: count(record.requestDates, within: Self.minute, endingAt: instant),
            minuteLimit: plan.requestsPerMinute,
            dayUsed: count(record.requestDates, within: Self.day, endingAt: instant),
            dayLimit: plan.requestsPerDay
        )
    }

    /// Sliding window is half-open on the left: (instant - span, instant].
    private func count(_ dates: [Date], within span: TimeInterval, endingAt instant: Date) -> Int {
        let start = instant.addingTimeInterval(-span)
        return dates.filter { $0 > start && $0 <= instant }.count
    }

    // MARK: Part 2 — atomic request handling

    public func handleRequest(_ keyID: String, at date: Date? = nil) -> RateLimitDecision {
        let instant = date ?? now()
        // Actor isolation makes decide-then-record a single atomic step: no
        // suspension point sits between the check and the append.
        let decision = evaluate(keyID, at: instant)
        guard case .allowed = decision else { return decision }
        keys[keyID]!.requestDates.append(instant)
        keys[keyID]!.requestDates.removeAll { $0 <= instant.addingTimeInterval(-Self.retention) }
        return .allowed(makeUsage(for: keys[keyID]!, at: instant))
    }

    // MARK: Part 3 — usage and immutable snapshots

    public func usage(for keyID: String, at date: Date? = nil) throws(APIRateLimiterError) -> Usage {
        guard let record = keys[keyID] else { throw .unknownKey(keyID) }
        return makeUsage(for: record, at: date ?? now())
    }

    public func keySnapshots() -> [APIKeySnapshot] {
        keys.values
            .sorted { $0.id < $1.id }
            .map { APIKeySnapshot(id: $0.id, owner: $0.owner, planID: $0.planID, isEnabled: $0.isEnabled, requestDates: $0.requestDates) }
    }
}
