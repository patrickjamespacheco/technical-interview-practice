import Testing
@testable import Problem71AllocationYieldOptimiser

private func lots() -> [Lot] { [Lot(id: "a", sizeCents: 10, yieldCents: 60), Lot(id: "b", sizeCents: 20, yieldCents: 100), Lot(id: "c", sizeCents: 30, yieldCents: 120)] }

@Suite("Part 1 - Ratio ordering") struct YieldPart1Tests {
    @Test func exactOrderAndReduction() throws {
        #expect(Ratio(2, over: 4) == Ratio(1, over: 2)); #expect(try YieldOptimiser().orderedByYieldRatio(lots()).map(\.id) == ["a", "b", "c"])
    }
    @Test func validatesAndIsStateless() throws {
        let first = YieldOptimiser(), second = YieldOptimiser(); _ = try first.orderedByYieldRatio(lots())
        #expect(try second.orderedByYieldRatio(lots()).map(\.id) == ["a", "b", "c"])
        #expect(throws: AllocationError.nonPositiveSize(id: "bad-size")) { try first.orderedByYieldRatio([Lot(id: "bad-size", sizeCents: 0, yieldCents: 1)]) }
    }
}
@Suite("Part 2 - Fractional allocation") struct YieldPart2Tests {
    @Test func fillsByRatio() throws {
        let result = try YieldOptimiser().allocateDivisible(lots(), budgetCents: 50)
        #expect(result.wholeLots == ["a", "b"]); #expect(result.partialLot?.id == "c"); #expect(result.partialLot?.fraction == Ratio(2, over: 3)); #expect(result.totalYield == Ratio(240, over: 1))
    }
}
@Suite("Part 3 - All or nothing, and the shortfall") struct YieldPart3Tests {
    @Test func exposesGreedyBoundary() throws {
        let optimiser = YieldOptimiser(); let greedy = try optimiser.allocateWholeByRatio(lots(), budgetCents: 50); let exact = try optimiser.allocateWholeExactly(lots(), budgetCents: 50)
        #expect(greedy == WholeAllocation(lots: ["a", "b"], totalYield: 160, unusedBudgetCents: 20)); #expect(exact == WholeAllocation(lots: ["b", "c"], totalYield: 220, unusedBudgetCents: 0)); #expect(try optimiser.greedyShortfall(lots(), budgetCents: 50) == 60)
        #expect(Ratio(exact.totalYield, over: 1) <= (try optimiser.allocateDivisible(lots(), budgetCents: 50).totalYield))
    }
}
@Suite("Part 4 - The exchange certificate") struct YieldPart4Tests {
    @Test func returnsExecutableExchange() throws {
        let optimiser = YieldOptimiser()
        #expect(try optimiser.certificate(for: ["a": 10, "b": 20, "c": 20], lots: lots(), budgetCents: 50) == .alreadyOptimal)
        #expect(try optimiser.certificate(for: ["b": 20, "c": 30], lots: lots(), budgetCents: 50) == .improve(reduce: "c", increase: "a", amountCents: 10, gain: Ratio(20, over: 1)))
    }
}
