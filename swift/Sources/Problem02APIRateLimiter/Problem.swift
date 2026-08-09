import Foundation

public struct Plan: Equatable, Sendable { public let requestsPerMinute: Int?; public let requestsPerDay: Int?; public init(requestsPerMinute: Int?, requestsPerDay: Int?) { self.requestsPerMinute = requestsPerMinute; self.requestsPerDay = requestsPerDay } }
public struct Usage: Equatable, Sendable { public let keyID: String; public let planID: String; public let minuteUsed: Int; public let minuteLimit: Int?; public let dayUsed: Int; public let dayLimit: Int?; public init(keyID: String, planID: String, minuteUsed: Int, minuteLimit: Int?, dayUsed: Int, dayLimit: Int?) { self.keyID = keyID; self.planID = planID; self.minuteUsed = minuteUsed; self.minuteLimit = minuteLimit; self.dayUsed = dayUsed; self.dayLimit = dayLimit } }
public enum DenialReason: Equatable, Sendable { case keyNotFound(keyID: String); case keyDisabled(keyID: String); case perMinuteExceeded(limit: Int, used: Int); case perDayExceeded(limit: Int, used: Int) }
public enum RateLimitDecision: Equatable, Sendable { case allowed(Usage); case denied(DenialReason) }
public struct APIKeySnapshot: Equatable, Sendable { public let id: String; public let owner: String; public let planID: String; public let isEnabled: Bool; public let requestDates: [Date]; public init(id: String, owner: String, planID: String, isEnabled: Bool, requestDates: [Date]) { self.id = id; self.owner = owner; self.planID = planID; self.isEnabled = isEnabled; self.requestDates = requestDates } }
public enum APIRateLimiterError: Error, Equatable, Sendable { case duplicateKey(String); case unknownKey(String); case unknownPlan(String); case notImplemented }
public actor APIRateLimiter {
    public init(plans: [String: Plan], now: @escaping @Sendable () -> Date) {}
    public func createKey(id: String, owner: String, planID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func revokeKey(_ keyID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func updatePlan(for keyID: String, to planID: String) throws(APIRateLimiterError) { throw .notImplemented }
    public func evaluate(_ keyID: String, at date: Date? = nil) -> RateLimitDecision { .denied(.keyNotFound(keyID: keyID)) }
    public func handleRequest(_ keyID: String, at date: Date? = nil) -> RateLimitDecision { .denied(.keyNotFound(keyID: keyID)) }
    public func usage(for keyID: String, at date: Date? = nil) throws(APIRateLimiterError) -> Usage { throw .notImplemented }
    public func keySnapshots() -> [APIKeySnapshot] { [] }
}
