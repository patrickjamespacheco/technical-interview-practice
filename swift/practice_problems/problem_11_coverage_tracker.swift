import Foundation

// Problem 11: Coverage Tracker
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Track receiver stations, heartbeats, outages, and regional coverage using
// typed temporal values. You choose the internal data structures; the public
// interface is the contract. Store mutable state only in this instance.
// Returned arrays and summaries are immutable snapshots.
//
/*
 * Example
 */
// let tracker = CoverageTracker(now: { Date(timeIntervalSince1970: 1_700_000_300) })
// try tracker.register(Station(id: "sta-001", name: "North Tower", region: "downtown"))
// try tracker.recordHeartbeat(for: "sta-001", at: Date(timeIntervalSince1970: 1_700_000_000))
// try tracker.staleStations(after: .seconds(120)) // -> [Station(id: "sta-001", ...)]
// try tracker.coverageStatus(in: "downtown", staleAfter: .seconds(120)) // -> .unavailable(...)
//
// PART 1 — Stations and heartbeats  (~12 min)
// Register unique string IDs, accept only strictly increasing heartbeats, and
// return station snapshots sorted by ID. Calls without `asOf` use injected time.
//
// PART 2 — Staleness and outage history  (~16 min)
// A station is stale when it has no heartbeat or its heartbeat age is greater
// than the threshold. Allow one open outage per station. Ending an outage must
// be after its start. Return outage snapshots sorted by start date.
//
// PART 3 — Coverage and duration summaries  (~17 min)
// coverageStatus must compose stations(in:) and staleStations(asOf:after:).
// outageSummary must compose outages(for:) and count an open outage through
// the requested/injected time.

public struct Station: Equatable, Sendable {
    public let id: String
    public let name: String
    public let region: String
    public init(id: String, name: String, region: String) {
        self.id = id; self.name = name; self.region = region
    }
}

public struct Outage: Equatable, Sendable {
    public let stationID: String
    public let startedAt: Date
    public let endedAt: Date?
    public init(stationID: String, startedAt: Date, endedAt: Date? = nil) {
        self.stationID = stationID; self.startedAt = startedAt; self.endedAt = endedAt
    }
}

public enum CoverageStatus: Equatable, Sendable {
    case noStations(region: String)
    case unavailable(region: String, total: Int, stale: Int)
    case available(region: String, total: Int, healthy: Int, stale: Int)
}

public struct OutageSummary: Equatable, Sendable {
    public let stationID: String
    public let totalOutages: Int
    public let hasOpenOutage: Bool
    public let totalDuration: Duration
    public init(stationID: String, totalOutages: Int, hasOpenOutage: Bool, totalDuration: Duration) {
        self.stationID = stationID; self.totalOutages = totalOutages
        self.hasOpenOutage = hasOpenOutage; self.totalDuration = totalDuration
    }
}

public enum CoverageTrackerError: Error, Equatable, Sendable {
    case duplicateStation(String)
    case unknownStation(String)
    case heartbeatNotIncreasing(stationID: String)
    case outageAlreadyOpen(stationID: String)
    case noOpenOutage(stationID: String)
    case outageEndNotAfterStart(stationID: String)
    case notImplemented
}

public final class CoverageTracker {
    public init(now: @escaping @Sendable () -> Date) {}

    // MARK: Part 1 — stations and heartbeats
    public func register(_ station: Station) throws(CoverageTrackerError) { throw .notImplemented }
    public func recordHeartbeat(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func lastHeartbeat(for stationID: String) throws(CoverageTrackerError) -> Date? { throw .notImplemented }
    public func stations(in region: String? = nil) -> [Station] { [] }

    // MARK: Part 2 — staleness and outage history
    public func staleStations(asOf date: Date? = nil, after threshold: Duration) throws(CoverageTrackerError) -> [Station] { throw .notImplemented }
    public func startOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func endOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func outages(for stationID: String) throws(CoverageTrackerError) -> [Outage] { throw .notImplemented }

    // MARK: Part 3 — coverage and duration summaries
    public func coverageStatus(in region: String, asOf date: Date? = nil, staleAfter threshold: Duration) throws(CoverageTrackerError) -> CoverageStatus { throw .notImplemented }
    public func outageSummary(for stationID: String, asOf date: Date? = nil) throws(CoverageTrackerError) -> OutageSummary { throw .notImplemented }
}
