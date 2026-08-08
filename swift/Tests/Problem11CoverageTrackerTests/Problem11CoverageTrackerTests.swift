import Foundation
import Testing
@testable import Problem11CoverageTracker

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private let t1 = t0.addingTimeInterval(60)
private let t2 = t0.addingTimeInterval(120)
private let t3 = t0.addingTimeInterval(300)
private let t4 = t0.addingTimeInterval(600)
private func makeFreshTracker(now: Date = t4) -> CoverageTracker { CoverageTracker(now: { now }) }
private func makeSeededTracker(now: Date = t4) throws -> CoverageTracker {
    let tracker = makeFreshTracker(now: now)
    try tracker.register(Station(id: "sta-seed-1", name: "North Tower", region: "downtown"))
    try tracker.register(Station(id: "sta-seed-2", name: "South Tower", region: "downtown"))
    try tracker.register(Station(id: "sta-seed-3", name: "East Hub", region: "eastside"))
    try tracker.recordHeartbeat(for: "sta-seed-1", at: t0)
    try tracker.recordHeartbeat(for: "sta-seed-2", at: t1)
    return tracker
}

@Suite("Part 1 — Stations and heartbeats")
struct CoveragePart1 {
    @Test("registration returns sorted snapshots and rejects duplicates")
    func registration() throws {
        let tracker = makeFreshTracker()
        try tracker.register(Station(id: "sta-zed", name: "Zed", region: "north"))
        try tracker.register(Station(id: "sta-alpha", name: "Alpha", region: "south"))
        #expect(tracker.stations().map(\.id) == ["sta-alpha", "sta-zed"])
        #expect(tracker.stations(in: "north").map(\.id) == ["sta-zed"])
        #expect(throws: CoverageTrackerError.duplicateStation("sta-zed")) {
            try tracker.register(Station(id: "sta-zed", name: "Duplicate", region: "north"))
        }
    }

    @Test("heartbeats must increase strictly")
    func heartbeatOrder() throws {
        let tracker = try makeSeededTracker()
        try tracker.recordHeartbeat(for: "sta-seed-1", at: t2)
        #expect(try tracker.lastHeartbeat(for: "sta-seed-1") == t2)
        #expect(try tracker.lastHeartbeat(for: "sta-seed-3") == nil)
        #expect(throws: CoverageTrackerError.heartbeatNotIncreasing(stationID: "sta-seed-1")) {
            try tracker.recordHeartbeat(for: "sta-seed-1", at: t2)
        }
        #expect(throws: CoverageTrackerError.unknownStation("sta-heartbeat-ghost")) {
            try tracker.recordHeartbeat(for: "sta-heartbeat-ghost", at: t0)
        }
    }

    @Test("instances own independent state")
    func isolation() throws {
        let first = makeFreshTracker(), second = makeFreshTracker()
        try first.register(Station(id: "sta-isolation", name: "Only First", region: "north"))
        #expect(first.stations().count == 1)
        #expect(second.stations().isEmpty)
    }
}

@Suite("Part 2 — Staleness and outage history")
struct CoveragePart2 {
    @Test("staleness uses Duration and an exclusive threshold")
    func staleness() throws {
        let tracker = try makeSeededTracker()
        #expect(try tracker.staleStations(asOf: t2, after: .seconds(120)).map(\.id) == ["sta-seed-3"])
        #expect(try tracker.staleStations(asOf: t3, after: .seconds(120)).map(\.id) == ["sta-seed-1", "sta-seed-2", "sta-seed-3"])
        #expect(try tracker.staleStations(after: .seconds(5)).count == 3)
    }

    @Test("outages open, close, and remain sorted snapshots")
    func outageLifecycle() throws {
        let tracker = makeFreshTracker()
        try tracker.register(Station(id: "sta-outage", name: "Tower", region: "north"))
        try tracker.startOutage(for: "sta-outage", at: t0)
        #expect(throws: CoverageTrackerError.outageAlreadyOpen(stationID: "sta-outage")) {
            try tracker.startOutage(for: "sta-outage", at: t1)
        }
        #expect(throws: CoverageTrackerError.outageEndNotAfterStart(stationID: "sta-outage")) {
            try tracker.endOutage(for: "sta-outage", at: t0)
        }
        try tracker.endOutage(for: "sta-outage", at: t1)
        try tracker.startOutage(for: "sta-outage", at: t2)
        let snapshot = try tracker.outages(for: "sta-outage")
        try tracker.endOutage(for: "sta-outage", at: t3)
        #expect(snapshot.map(\.startedAt) == [t0, t2])
        #expect(snapshot.last?.endedAt == nil)
        #expect(try tracker.outages(for: "sta-outage").last?.endedAt == t3)
    }

    @Test("missing stations and absent open outages are typed failures")
    func outageFailures() throws {
        let tracker = try makeSeededTracker()
        #expect(throws: CoverageTrackerError.noOpenOutage(stationID: "sta-seed-1")) {
            try tracker.endOutage(for: "sta-seed-1", at: t2)
        }
        #expect(throws: CoverageTrackerError.unknownStation("sta-outage-ghost")) {
            try tracker.outages(for: "sta-outage-ghost")
        }
    }
}

@Suite("Part 3 — Coverage and duration summaries")
struct CoveragePart3 {
    @Test("coverage is represented by associated-value states")
    func coverage() throws {
        let tracker = try makeSeededTracker()
        #expect(try tracker.coverageStatus(in: "downtown", asOf: t2, staleAfter: .seconds(90)) == .available(region: "downtown", total: 2, healthy: 1, stale: 1))
        #expect(try tracker.coverageStatus(in: "downtown", asOf: t4, staleAfter: .seconds(30)) == .unavailable(region: "downtown", total: 2, stale: 2))
        #expect(try tracker.coverageStatus(in: "ghost-region", asOf: t0, staleAfter: .seconds(60)) == .noStations(region: "ghost-region"))
    }

    @Test("outage summaries accumulate closed and injected-time durations")
    func summaries() throws {
        let tracker = makeFreshTracker(now: t4)
        try tracker.register(Station(id: "sta-summary", name: "Tower", region: "north"))
        try tracker.startOutage(for: "sta-summary", at: t0)
        try tracker.endOutage(for: "sta-summary", at: t1)
        try tracker.startOutage(for: "sta-summary", at: t2)
        let summary = try tracker.outageSummary(for: "sta-summary")
        #expect(summary.totalOutages == 2)
        #expect(summary.hasOpenOutage)
        #expect(summary.totalDuration == .seconds(540))
    }
}
