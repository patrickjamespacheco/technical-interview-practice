import Foundation

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
    private let now: @Sendable () -> Date
    private var stationsByID: [String: Station] = [:]
    private var heartbeats: [String: Date] = [:]
    private var outagesByStation: [String: [Outage]] = [:]

    public init(now: @escaping @Sendable () -> Date) { self.now = now }

    // MARK: Part 1 — stations and heartbeats

    public func register(_ station: Station) throws(CoverageTrackerError) {
        guard stationsByID[station.id] == nil else { throw .duplicateStation(station.id) }
        stationsByID[station.id] = station
    }

    public func recordHeartbeat(for stationID: String, at date: Date) throws(CoverageTrackerError) {
        try requireStation(stationID)
        if let previous = heartbeats[stationID], date <= previous {
            throw .heartbeatNotIncreasing(stationID: stationID)
        }
        heartbeats[stationID] = date
    }

    public func lastHeartbeat(for stationID: String) throws(CoverageTrackerError) -> Date? {
        try requireStation(stationID)
        return heartbeats[stationID]
    }

    public func stations(in region: String? = nil) -> [Station] {
        stationsByID.values
            .filter { region == nil || $0.region == region }
            .sorted { $0.id < $1.id }
    }

    @discardableResult
    private func requireStation(_ stationID: String) throws(CoverageTrackerError) -> Station {
        guard let station = stationsByID[stationID] else { throw .unknownStation(stationID) }
        return station
    }

    // MARK: Part 2 — staleness and outage history

    public func staleStations(asOf date: Date? = nil, after threshold: Duration) throws(CoverageTrackerError) -> [Station] {
        let instant = date ?? now()
        return stations().filter { station in
            guard let heartbeat = heartbeats[station.id] else { return true }
            return .seconds(instant.timeIntervalSince(heartbeat)) > threshold
        }
    }

    public func startOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) {
        try requireStation(stationID)
        guard openOutageIndex(for: stationID) == nil else { throw .outageAlreadyOpen(stationID: stationID) }
        outagesByStation[stationID, default: []].append(Outage(stationID: stationID, startedAt: date))
    }

    public func endOutage(for stationID: String, at date: Date) throws(CoverageTrackerError) {
        try requireStation(stationID)
        guard let index = openOutageIndex(for: stationID) else { throw .noOpenOutage(stationID: stationID) }
        let open = outagesByStation[stationID]![index]
        guard date > open.startedAt else { throw .outageEndNotAfterStart(stationID: stationID) }
        outagesByStation[stationID]![index] = Outage(stationID: stationID, startedAt: open.startedAt, endedAt: date)
    }

    public func outages(for stationID: String) throws(CoverageTrackerError) -> [Outage] {
        try requireStation(stationID)
        return (outagesByStation[stationID] ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    /// At most one outage is open per station, so this is the single place that
    /// defines what "open" means.
    private func openOutageIndex(for stationID: String) -> Int? {
        outagesByStation[stationID]?.firstIndex { $0.endedAt == nil }
    }

    // MARK: Part 3 — coverage and duration summaries

    public func coverageStatus(in region: String, asOf date: Date? = nil, staleAfter threshold: Duration) throws(CoverageTrackerError) -> CoverageStatus {
        let regional = stations(in: region)
        guard !regional.isEmpty else { return .noStations(region: region) }
        let staleIDs = Set(try staleStations(asOf: date, after: threshold).map(\.id))
        let stale = regional.filter { staleIDs.contains($0.id) }.count
        let healthy = regional.count - stale
        guard healthy > 0 else { return .unavailable(region: region, total: regional.count, stale: stale) }
        return .available(region: region, total: regional.count, healthy: healthy, stale: stale)
    }

    public func outageSummary(for stationID: String, asOf date: Date? = nil) throws(CoverageTrackerError) -> OutageSummary {
        let instant = date ?? now()
        let history = try outages(for: stationID)
        // An open outage still counts, measured through the requested instant.
        let seconds = history.reduce(0.0) { total, outage in
            total + (outage.endedAt ?? instant).timeIntervalSince(outage.startedAt)
        }
        return OutageSummary(
            stationID: stationID,
            totalOutages: history.count,
            hasOpenOutage: history.contains { $0.endedAt == nil },
            totalDuration: .seconds(seconds)
        )
    }
}
