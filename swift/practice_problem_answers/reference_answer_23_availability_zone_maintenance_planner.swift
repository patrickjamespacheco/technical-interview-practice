/// One availability zone and the maintenance debt draining it would clear.
public struct Zone: Equatable, Sendable {
    public let id: String
    public let debtCleared: Int

    public init(id: String, debtCleared: Int) {
        self.id = id
        self.debtCleared = debtCleared
    }
}

/// A zone in a hierarchical fleet. A zone's neighbours here are its parent and
/// its children, so the adjacency rule is the same rule the rack obeys, stated
/// over a different topology.
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
    /// A cycle longer than this can produce more schedules than an Int holds, so
    /// the planner refuses rather than reporting a wrapped count.
    private static let maximumCountableZones = 60

    public init() {}

    // MARK: Part 1 - Count legal advance schedules

    /// How many distinct advance sequences walk the drain cursor from the start
    /// of a cycle to exactly past its end.
    ///
    /// The table entry is "schedules that end with the cursor resting on
    /// position i", which makes the transition a sum over the gaps that could
    /// have produced the last advance. Position 0 has exactly one schedule: the
    /// empty one. Duplicate gaps describe the same advance and are counted once.
    public func scheduleCount(zoneCount: Int, allowedGaps: [Int]) throws(PlannerError) -> Int {
        guard zoneCount >= 0 else { throw .negativeZoneCount }
        guard !allowedGaps.isEmpty else { throw .emptyGapSet }
        for gap in allowedGaps where gap <= 0 { throw .nonPositiveGap(gap) }
        guard zoneCount <= Self.maximumCountableZones else { throw .countOverflow }

        let gaps = Set(allowedGaps)
        var schedules = Array(repeating: 0, count: zoneCount + 1)
        schedules[0] = 1
        for position in 1..<(zoneCount + 1) {
            for gap in gaps where gap <= position {
                schedules[position] += schedules[position - gap]
            }
        }
        return schedules[zoneCount]
    }

    // MARK: Part 2 - Plan a linear rack

    /// The plan is the primitive: it owns the only linear table in this file, and
    /// the value method below is a projection of it. Two neighbours may never be
    /// drained in the same cycle, so the choice at each position is "drain this
    /// zone and forfeit its predecessor" or "skip it and keep the best so far".
    ///
    /// The backtrack reads the same table in reverse. Where draining and skipping
    /// tie, the plan skips, which keeps the selection minimal.
    public func planLinear(zones: [Zone]) throws(PlannerError) -> MaintenancePlan {
        try validateDebts(zones)
        guard !zones.isEmpty else { return MaintenancePlan(totalDebtCleared: 0, selectedZoneIDs: []) }

        var best = Array(repeating: 0, count: zones.count)
        best[0] = zones[0].debtCleared
        if zones.count > 1 {
            best[1] = max(zones[0].debtCleared, zones[1].debtCleared)
        }
        for position in 2..<max(2, zones.count) {
            best[position] = max(best[position - 1], best[position - 2] + zones[position].debtCleared)
        }

        var selected: [String] = []
        var position = zones.count - 1
        while position >= 0 {
            if position == 0 {
                if best[0] > 0 { selected.append(zones[0].id) }
                break
            }
            if best[position] == best[position - 1] {
                position -= 1                       // a tie means this zone was skipped
            } else {
                selected.append(zones[position].id)
                position -= 2                       // its neighbour is forfeited
            }
        }

        return MaintenancePlan(totalDebtCleared: best[zones.count - 1], selectedZoneIDs: selected.reversed())
    }

    public func bestLinearValue(zones: [Zone]) throws(PlannerError) -> Int {
        try planLinear(zones: zones).totalDebtCleared
    }

    // MARK: Part 3 - Plan a ring

    /// A ring adds exactly one constraint to a rack: the first and last zones are
    /// now neighbours, so they cannot both be drained. Every legal ring plan
    /// therefore leaves out the first zone or the last one, which makes this two
    /// rack problems rather than a new recurrence.
    ///
    /// A cycle of two or fewer zones is already a rack: no pair of them is
    /// adjacent twice, so the linear planner answers it directly.
    public func bestRingValue(zones: [Zone]) throws(PlannerError) -> Int {
        guard zones.count > 2 else { return try bestLinearValue(zones: zones) }
        let withoutLast = try bestLinearValue(zones: Array(zones.dropLast()))
        let withoutFirst = try bestLinearValue(zones: Array(zones.dropFirst()))
        return max(withoutLast, withoutFirst)
    }

    // MARK: Part 4 - Plan a hierarchical fleet

    /// This is the one part that cannot call an earlier one: the rack table is
    /// indexed by position, and a tree has no positions. What does carry over is
    /// the pair of states the table encoded positionally. Where the rack asked
    /// "best up to here having drained this zone" and "best up to here without
    /// it", the tree asks the same two questions of every subtree and folds them
    /// upward in post-order.
    public func bestHierarchicalValue(root: ZoneNode?) throws(PlannerError) -> Int {
        guard let root else { return 0 }
        try validateTreeDebts(root)
        let outcome = fold(root)
        return max(outcome.drained, outcome.intact)
    }

    /// The best cleared debt for the subtree rooted at `node`, in both states.
    /// Draining a zone forfeits every child; leaving it intact lets each child
    /// choose its own better state.
    private func fold(_ node: ZoneNode) -> (drained: Int, intact: Int) {
        var drained = node.zone.debtCleared
        var intact = 0
        for child in node.children {
            let childOutcome = fold(child)
            drained += childOutcome.intact
            intact += max(childOutcome.drained, childOutcome.intact)
        }
        return (drained, intact)
    }

    // MARK: Validation shared by every planning method

    private func validateDebts(_ zones: [Zone]) throws(PlannerError) {
        for zone in zones where zone.debtCleared < 0 { throw .negativeDebt(zone.id) }
    }

    private func validateTreeDebts(_ node: ZoneNode) throws(PlannerError) {
        if node.zone.debtCleared < 0 { throw .negativeDebt(node.zone.id) }
        for child in node.children { try validateTreeDebts(child) }
    }
}
