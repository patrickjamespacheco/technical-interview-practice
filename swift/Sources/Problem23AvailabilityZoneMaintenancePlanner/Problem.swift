// Problem 23: Availability-Zone Maintenance Planner
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A fleet operator drains availability zones to do maintenance on them. Two
// zones that are neighbours in the redundancy topology may never be drained in
// the same cycle: that would leave the service with no surviving replica. Each
// zone carries the maintenance debt that draining it would clear.
//
// The planner has to count how many legal advance schedules a cycle admits,
// then maximise cleared debt across three real deployment shapes: a linear rack,
// a replication ring where the last zone neighbours the first, and a
// hierarchical fleet where a zone's neighbours are its parent and its children.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state.
//
/*
# Example
let planner = MaintenancePlanner()
try planner.scheduleCount(zoneCount: 5, allowedGaps: [1, 2])   // -> 8
let rack = [Zone(id: "az-1", debtCleared: 4),
            Zone(id: "az-2", debtCleared: 9),
            Zone(id: "az-3", debtCleared: 3),
            Zone(id: "az-4", debtCleared: 7)]
try planner.planLinear(zones: rack).selectedZoneIDs             // -> ["az-2", "az-4"]
try planner.planLinear(zones: rack).totalDebtCleared            // -> 16
try planner.bestLinearValue(zones: rack)                        // -> 16
try planner.bestRingValue(zones: rack)                          // -> 16
let ring = [Zone(id: "r-1", debtCleared: 2),
            Zone(id: "r-2", debtCleared: 3),
            Zone(id: "r-3", debtCleared: 2)]
try planner.bestRingValue(zones: ring)                          // -> 3
let tree = ZoneNode(zone: Zone(id: "root", debtCleared: 3), children: [
    ZoneNode(zone: Zone(id: "left", debtCleared: 2), children: []),
    ZoneNode(zone: Zone(id: "right", debtCleared: 3), children: [
        ZoneNode(zone: Zone(id: "leaf", debtCleared: 1), children: [])
    ])
])
try planner.bestHierarchicalValue(root: tree)                    // -> 5
*/
//
// PART 1 - Count legal advance schedules  (~9 min)
// A maintenance cycle walks a drain cursor from the start of a rack of
// zoneCount zones to exactly past its end, advancing by one of allowedGaps each
// time. Count the distinct advance schedules. A cycle of no zones has exactly
// one schedule: the empty one. A repeated gap describes the same advance and is
// counted once. A negative zone count, an empty gap set, and a gap that does not
// advance the cursor are each a typed failure, and so is a cycle long enough
// that the count would not fit in an Int: refuse rather than report a wrapped
// number.
//
// PART 2 - Plan a linear rack  (~13 min)
// Maximise the debt cleared on a rack where each zone neighbours the zone before
// and after it, and report which zones the plan drains, ascending by position.
// Both methods below must share one table: make the plan the method that does
// the work, and the value method a projection of it. Where draining and skipping
// clear the same debt, skip. A negative debt is a typed failure that names the
// zone.
//
// PART 3 - Plan a ring  (~11 min)
// On a replication ring the last zone neighbours the first. This is not a new
// recurrence: ask yourself what every legal ring plan must leave out, and answer
// it with calls to Part 2. Rings of two or fewer zones need no special code if
// you pick the right call.
//
// PART 4 - Plan a hierarchical fleet  (~12 min)
// In a hierarchical fleet a zone's neighbours are its parent and its children.
// This is the one part that cannot call an earlier one, because the rack table
// is indexed by position and a tree has no positions. What does carry over is
// the pair of states that table encoded positionally: for the rack you tracked
// the best with this zone drained and the best without it. Ask both questions of
// every subtree and fold them upward. An absent fleet clears nothing.

/// One availability zone and the maintenance debt draining it would clear.
public struct Zone: Equatable, Sendable {
    public let id: String
    public let debtCleared: Int

    public init(id: String, debtCleared: Int) {
        self.id = id
        self.debtCleared = debtCleared
    }
}

/// A zone in a hierarchical fleet. Build trees with this initializer; note that
/// Array(repeating:count:) would give every slot the same node, because this is
/// a reference type and not a value type.
public final class ZoneNode: Sendable {
    public let zone: Zone
    public let children: [ZoneNode]

    public init(zone: Zone, children: [ZoneNode]) {
        self.zone = zone
        self.children = children
    }
}

public struct MaintenancePlan: Equatable, Sendable {
    public let totalDebtCleared: Int
    /// Ascending by rack position.
    public let selectedZoneIDs: [String]

    public init(totalDebtCleared: Int, selectedZoneIDs: [String]) {
        self.totalDebtCleared = totalDebtCleared
        self.selectedZoneIDs = selectedZoneIDs
    }
}

public enum PlannerError: Error, Equatable, Sendable {
    case negativeZoneCount
    case emptyGapSet
    case nonPositiveGap(Int)
    case negativeDebt(String)
    case countOverflow
    case notImplemented
}

public struct MaintenancePlanner: Sendable {
    public init() {}

    // MARK: Part 1 - Count legal advance schedules
    public func scheduleCount(zoneCount: Int, allowedGaps: [Int]) throws(PlannerError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 2 - Plan a linear rack
    public func planLinear(zones: [Zone]) throws(PlannerError) -> MaintenancePlan {
        throw .notImplemented
    }

    public func bestLinearValue(zones: [Zone]) throws(PlannerError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - Plan a ring
    public func bestRingValue(zones: [Zone]) throws(PlannerError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 4 - Plan a hierarchical fleet
    public func bestHierarchicalValue(root: ZoneNode?) throws(PlannerError) -> Int {
        throw .notImplemented
    }
}
