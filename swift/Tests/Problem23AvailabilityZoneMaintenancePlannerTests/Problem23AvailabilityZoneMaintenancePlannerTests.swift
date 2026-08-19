import Testing
@testable import Problem23AvailabilityZoneMaintenancePlanner

private func makeFreshPlanner() -> MaintenancePlanner {
    MaintenancePlanner()
}

/// Builds a rack whose zone IDs are unique to the caller, so an accidental
/// static cache keyed by ID shows up as a wrong answer rather than as a pass.
private func makeRack(_ prefix: String, _ debts: [Int]) -> [Zone] {
    debts.enumerated().map { Zone(id: "\(prefix)-\($0.offset + 1)", debtCleared: $0.element) }
}

private func makeChain(_ prefix: String, _ debts: [Int]) -> ZoneNode? {
    var node: ZoneNode?
    for (offset, debt) in debts.enumerated().reversed() {
        node = ZoneNode(
            zone: Zone(id: "\(prefix)-\(offset + 1)", debtCleared: debt),
            children: node.map { [$0] } ?? []
        )
    }
    return node
}

@Suite("Part 1 - Count legal advance schedules")
struct MaintenancePart1Tests {
    @Test("an empty cycle has exactly one schedule: the empty one")
    func emptyCycle() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.scheduleCount(zoneCount: 0, allowedGaps: [1, 2]) == 1)
    }

    @Test("gaps of one and two reproduce the classic doubling-back sequence")
    func gapsOfOneAndTwo() throws {
        let planner = makeFreshPlanner()
        var counts: [Int] = []
        for zoneCount in 1...6 {
            counts.append(try planner.scheduleCount(zoneCount: zoneCount, allowedGaps: [1, 2]))
        }
        #expect(counts == [1, 2, 3, 5, 8, 13])
    }

    @Test("a wider gap set changes the sequence")
    func gapsOfOneAndThree() throws {
        let planner = makeFreshPlanner()
        var counts: [Int] = []
        for zoneCount in 1...6 {
            counts.append(try planner.scheduleCount(zoneCount: zoneCount, allowedGaps: [1, 3]))
        }
        #expect(counts == [1, 1, 2, 3, 4, 6])
    }

    @Test("a single gap admits exactly one schedule of any length")
    func singleGap() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.scheduleCount(zoneCount: 7, allowedGaps: [1]) == 1)
        #expect(try planner.scheduleCount(zoneCount: 7, allowedGaps: [2]) == 0)
        #expect(try planner.scheduleCount(zoneCount: 8, allowedGaps: [2]) == 1)
    }

    @Test("a repeated gap describes the same advance and is counted once")
    func duplicateGapsAreOneAdvance() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.scheduleCount(zoneCount: 6, allowedGaps: [1, 2, 2]) == 13)
    }

    @Test("a negative zone count is a typed failure")
    func negativeZoneCountFails() {
        let planner = makeFreshPlanner()
        #expect(throws: PlannerError.negativeZoneCount) {
            try planner.scheduleCount(zoneCount: -1, allowedGaps: [1])
        }
    }

    @Test("an empty gap set is a typed failure")
    func emptyGapSetFails() {
        let planner = makeFreshPlanner()
        #expect(throws: PlannerError.emptyGapSet) {
            try planner.scheduleCount(zoneCount: 4, allowedGaps: [])
        }
    }

    @Test("a gap that does not advance the cursor is a typed failure")
    func nonPositiveGapFails() {
        let planner = makeFreshPlanner()
        #expect(throws: PlannerError.nonPositiveGap(0)) {
            try planner.scheduleCount(zoneCount: 4, allowedGaps: [1, 0])
        }
        #expect(throws: PlannerError.nonPositiveGap(-2)) {
            try planner.scheduleCount(zoneCount: 4, allowedGaps: [-2])
        }
    }

    @Test("a cycle long enough to overflow the count is refused, not wrapped")
    func overflowIsRefused() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.scheduleCount(zoneCount: 60, allowedGaps: [1, 2]) > 0)
        #expect(throws: PlannerError.countOverflow) {
            try planner.scheduleCount(zoneCount: 61, allowedGaps: [1, 2])
        }
    }
}

@Suite("Part 2 - Plan a linear rack")
struct MaintenancePart2Tests {
    @Test("an empty rack clears nothing and drains nothing")
    func emptyRack() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: [])
        #expect(plan == MaintenancePlan(totalDebtCleared: 0, selectedZoneIDs: []))
    }

    @Test("a single zone is drained on its own")
    func singleZone() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: makeRack("solo", [5]))
        #expect(plan == MaintenancePlan(totalDebtCleared: 5, selectedZoneIDs: ["solo-1"]))
    }

    @Test("two zones drain only the larger")
    func twoZones() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: makeRack("pair", [4, 9]))
        #expect(plan == MaintenancePlan(totalDebtCleared: 9, selectedZoneIDs: ["pair-2"]))
    }

    @Test("the worked rack drains the second and fourth zones")
    func workedRack() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: makeRack("worked", [4, 9, 3, 7]))
        try #require(plan.selectedZoneIDs.count == 2)
        #expect(plan.selectedZoneIDs[0] == "worked-2")
        #expect(plan.selectedZoneIDs[1] == "worked-4")
        #expect(plan.totalDebtCleared == 16)
    }

    @Test("skipping two zones in a row can beat draining every other one")
    func skippingTwoInARow() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: makeRack("gap3", [2, 1, 1, 2]))
        #expect(plan.totalDebtCleared == 4)
        #expect(plan.selectedZoneIDs == ["gap3-1", "gap3-4"])
    }

    @Test("a rack of zeroes drains nothing, because a tie prefers skipping")
    func tiesPreferSkipping() throws {
        let planner = makeFreshPlanner()
        let plan = try planner.planLinear(zones: makeRack("zeroes", [0, 0, 0]))
        #expect(plan == MaintenancePlan(totalDebtCleared: 0, selectedZoneIDs: []))
    }

    @Test("the value method reports exactly the plan's total")
    func valueMatchesPlan() throws {
        let planner = makeFreshPlanner()
        let fixtures = [
            makeRack("agree-a", [4, 9, 3, 7]),
            makeRack("agree-b", [2, 1, 1, 2]),
            makeRack("agree-c", [6]),
            makeRack("agree-d", [1, 20, 3, 4, 5, 30, 2]),
        ]
        for rack in fixtures {
            #expect(try planner.planLinear(zones: rack).totalDebtCleared == planner.bestLinearValue(zones: rack))
        }
    }

    @Test("no two drained zones are neighbours on the rack")
    func selectionIsNeverAdjacent() throws {
        let planner = makeFreshPlanner()
        let rack = makeRack("spaced", [1, 20, 3, 4, 5, 30, 2])
        let plan = try planner.planLinear(zones: rack)
        let positions = plan.selectedZoneIDs.compactMap { id in rack.firstIndex { $0.id == id } }
        #expect(positions.count == plan.selectedZoneIDs.count)
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $1 - $0 >= 2 })
        #expect(plan.totalDebtCleared == 54)
    }

    @Test("a negative debt names the offending zone")
    func negativeDebtFails() {
        let planner = makeFreshPlanner()
        #expect(throws: PlannerError.negativeDebt("bad-3")) {
            try planner.planLinear(zones: makeRack("bad", [4, 2, -1, 7]))
        }
    }

    @Test("planners are stateless: a second planner agrees and the caller's rack is untouched")
    func plannersAreIndependent() throws {
        let busy = makeFreshPlanner()
        let fresh = makeFreshPlanner()
        let rack = makeRack("isolation", [4, 9, 3, 7])

        for _ in 0..<5 {
            _ = try busy.planLinear(zones: rack)
            _ = try busy.planLinear(zones: makeRack("noise", [100, 1, 100]))
        }

        #expect(try fresh.planLinear(zones: rack) == MaintenancePlan(totalDebtCleared: 16, selectedZoneIDs: ["isolation-2", "isolation-4"]))
        #expect(rack == makeRack("isolation", [4, 9, 3, 7]))
        #expect(try busy.bestLinearValue(zones: rack) == 16)
    }
}

@Suite("Part 3 - Plan a ring")
struct MaintenancePart3Tests {
    @Test("a ring cannot drain both ends of the rack it is made from")
    func ringExcludesOneEnd() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestRingValue(zones: makeRack("ring3", [2, 3, 2])) == 3)
    }

    @Test("the worked ring matches its rack when the ends are not both drained")
    func workedRing() throws {
        let planner = makeFreshPlanner()
        let rack = makeRack("ring4", [4, 9, 3, 7])
        #expect(try planner.bestRingValue(zones: rack) == 16)
        #expect(try planner.bestLinearValue(zones: rack) == 16)
    }

    @Test("an empty ring clears nothing")
    func emptyRing() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestRingValue(zones: []) == 0)
    }

    @Test("a ring of one zone drains that zone")
    func singleZoneRing() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestRingValue(zones: makeRack("ring1", [8])) == 8)
    }

    @Test("a ring of two zones drains only the larger")
    func twoZoneRing() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestRingValue(zones: makeRack("ring2", [8, 3])) == 8)
    }

    @Test("a ring where dropping the first zone wins")
    func dropFirstWins() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestRingValue(zones: makeRack("ring5", [1, 9, 1, 9, 1])) == 18)
    }

    @Test("a negative debt is still a typed failure on a ring")
    func negativeDebtFails() {
        let planner = makeFreshPlanner()
        #expect(throws: PlannerError.negativeDebt("ringbad-2")) {
            try planner.bestRingValue(zones: makeRack("ringbad", [4, -5, 7, 1]))
        }
    }
}

@Suite("Part 4 - Plan a hierarchical fleet")
struct MaintenancePart4Tests {
    @Test("an absent fleet clears nothing")
    func emptyFleet() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.bestHierarchicalValue(root: nil) == 0)
    }

    @Test("a fleet of one zone drains that zone")
    func singleNode() throws {
        let planner = makeFreshPlanner()
        let root = ZoneNode(zone: Zone(id: "only", debtCleared: 11), children: [])
        #expect(try planner.bestHierarchicalValue(root: root) == 11)
    }

    @Test("the worked tree leaves the root intact and drains beneath it")
    func workedTree() throws {
        let planner = makeFreshPlanner()
        let tree = ZoneNode(zone: Zone(id: "tree-root", debtCleared: 3), children: [
            ZoneNode(zone: Zone(id: "tree-left", debtCleared: 2), children: []),
            ZoneNode(zone: Zone(id: "tree-right", debtCleared: 3), children: [
                ZoneNode(zone: Zone(id: "tree-leaf", debtCleared: 1), children: []),
            ]),
        ])
        #expect(try planner.bestHierarchicalValue(root: tree) == 5)
    }

    @Test("a deep chain alternates exactly as the rack of the same debts does")
    func deepChainMatchesTheRack() throws {
        let planner = makeFreshPlanner()
        let debts = [4, 9, 3, 7, 2, 6]
        let chain = makeChain("chain", debts)
        #expect(try planner.bestHierarchicalValue(root: chain) == 22)
        #expect(try planner.bestLinearValue(zones: makeRack("chain", debts)) == 22)
    }

    @Test("a wide star drains the children when the root cannot beat them")
    func wideStar() throws {
        let planner = makeFreshPlanner()
        let star = ZoneNode(zone: Zone(id: "star-root", debtCleared: 5), children: [
            ZoneNode(zone: Zone(id: "star-a", debtCleared: 3), children: []),
            ZoneNode(zone: Zone(id: "star-b", debtCleared: 4), children: []),
            ZoneNode(zone: Zone(id: "star-c", debtCleared: 2), children: []),
        ])
        #expect(try planner.bestHierarchicalValue(root: star) == 9)
    }

    @Test("a negative debt anywhere in the fleet is a typed failure")
    func negativeDebtFails() {
        let planner = makeFreshPlanner()
        let tree = ZoneNode(zone: Zone(id: "neg-root", debtCleared: 3), children: [
            ZoneNode(zone: Zone(id: "neg-child", debtCleared: -1), children: []),
        ])
        #expect(throws: PlannerError.negativeDebt("neg-child")) {
            try planner.bestHierarchicalValue(root: tree)
        }
    }

    @Test("a shared subtree yields independent results in two different fleets")
    func sharedSubtreeIsNotCached() throws {
        let planner = makeFreshPlanner()
        let shared = ZoneNode(zone: Zone(id: "shared-top", debtCleared: 4), children: [
            ZoneNode(zone: Zone(id: "shared-leaf", debtCleared: 6), children: []),
        ])
        let quietParent = ZoneNode(zone: Zone(id: "quiet-parent", debtCleared: 1), children: [shared])
        let loudParent = ZoneNode(zone: Zone(id: "loud-parent", debtCleared: 20), children: [shared])

        #expect(try planner.bestHierarchicalValue(root: shared) == 6)
        #expect(try planner.bestHierarchicalValue(root: quietParent) == 7)
        #expect(try planner.bestHierarchicalValue(root: loudParent) == 26)
        #expect(try planner.bestHierarchicalValue(root: shared) == 6)
    }
}
