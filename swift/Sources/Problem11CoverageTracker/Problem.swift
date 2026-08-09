import Foundation

public struct Station: Equatable, Sendable { public let id: String; public let name: String; public let region: String; public init(id: String, name: String, region: String) { self.id = id; self.name = name; self.region = region } }
public struct Outage: Equatable, Sendable { public let stationID: String; public let startedAt: Date; public let endedAt: Date?; public init(stationID: String, startedAt: Date, endedAt: Date? = nil) { self.stationID = stationID; self.startedAt = startedAt; self.endedAt = endedAt } }
public enum CoverageStatus: Equatable, Sendable { case noStations(region: String); case unavailable(region: String, total: Int, stale: Int); case available(region: String, total: Int, healthy: Int, stale: Int) }
public struct OutageSummary: Equatable, Sendable { public let stationID: String; public let totalOutages: Int; public let hasOpenOutage: Bool; public let totalDuration: Duration; public init(stationID: String, totalOutages: Int, hasOpenOutage: Bool, totalDuration: Duration) { self.stationID = stationID; self.totalOutages = totalOutages; self.hasOpenOutage = hasOpenOutage; self.totalDuration = totalDuration } }
public enum CoverageTrackerError: Error, Equatable, Sendable { case duplicateStation(String); case unknownStation(String); case heartbeatNotIncreasing(stationID: String); case outageAlreadyOpen(stationID: String); case noOpenOutage(stationID: String); case outageEndNotAfterStart(stationID: String); case notImplemented }
public final class CoverageTracker {
    public init(now: @escaping @Sendable () -> Date) {}
    public func register(_ station: Station) throws(CoverageTrackerError) { throw .notImplemented }
    public func recordHeartbeat(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func lastHeartbeat(for stationID: String) throws(CoverageTrackerError) -> Date? { throw .notImplemented }
    public func stations(in region: String? = nil) -> [Station] { [] }
    public func staleStations(asOf date: Date? = nil, after threshold: Duration) throws(CoverageTrackerError) -> [Station] { throw .notImplemented }
    public func startOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func endOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) { throw .notImplemented }
    public func outages(for stationID: String) throws(CoverageTrackerError) -> [Outage] { throw .notImplemented }
    public func coverageStatus(in region: String, asOf date: Date? = nil, staleAfter threshold: Duration) throws(CoverageTrackerError) -> CoverageStatus { throw .notImplemented }
    public func outageSummary(for stationID: String, asOf date: Date? = nil) throws(CoverageTrackerError) -> OutageSummary { throw .notImplemented }
}
