import Foundation

// Problem 02: API Rate Limiter
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build an actor that protects API keys with per-minute and per-day sliding
// windows. You choose the actor's internal data structures; the public
// interface is the contract. Store all mutable state in actor instance state.
// Limits of nil are unlimited. Window intervals are (start, now].
//
/*
 * Example
 */
// let clock = { Date(timeIntervalSince1970: 1_700_000_000) }
// let limiter = APIRateLimiter(plans: ["free": Plan(requestsPerMinute: 2, requestsPerDay: 10)], now: clock)
// try await limiter.createKey(id: "pk.demo", owner: "alice", planID: "free")
// await limiter.evaluate("pk.demo") // -> .allowed(Usage(...))
// await limiter.handleRequest("pk.demo") // -> .allowed(Usage(...))
//
// PART 1 — Keys and rich rate decisions  (~20 min)
// Register, revoke, and change plans. evaluate(_:at:) must distinguish every
// denial reason and return current Usage with an allowed decision. Check the
// minute limit before the day limit. Calls without `at` use the injected clock.
//
// PART 2 — Atomic request handling  (~15 min)
// handleRequest(_:at:) must call evaluate(_:at:). If allowed, append the
// request before returning an updated allowed Usage. Denials have no side
// effects. Prune timestamps at least 25 hours old when recording.
//
// PART 3 — Usage and immutable snapshots  (~10 min)
// usage(for:at:) returns current counts and limits. keySnapshots() returns
// copies sorted by key ID, never mutable actor storage.

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
    public init(plans: [String: Plan], now: @escaping @Sendable () -> Date) {}

    // MARK: Part 1 — keys and rich rate decisions
    public func createKey(id: String, owner: String, planID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func revokeKey(_ keyID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func updatePlan(for keyID: String, to planID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func evaluate(_ keyID: String, at date: Date? = nil) -> RateLimitDecision {
        .denied(.keyNotFound(keyID: keyID))
    }

    // MARK: Part 2 — atomic request handling
    public func handleRequest(_ keyID: String, at date: Date? = nil) -> RateLimitDecision {
        .denied(.keyNotFound(keyID: keyID))
    }

    // MARK: Part 3 — usage and immutable snapshots
    public func usage(for keyID: String, at date: Date? = nil) throws(APIRateLimiterError) -> Usage { throw .notImplemented }
    public func keySnapshots() -> [APIKeySnapshot] { [] }
}
