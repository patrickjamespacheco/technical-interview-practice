import Testing
@testable import Problem26FirmwareBundleBudgetPlanner

private func makeFreshPlanner() -> BundlePlanner {
    BundlePlanner()
}

private func makeModules(_ specs: [(String, Int, Int)]) -> [FeatureModule] {
    specs.map { FeatureModule(id: $0.0, sizeBytes: $0.1, value: $0.2) }
}

/// The worked bundle: fourteen bytes of unique feature modules worth twenty-nine.
private let workedModules = makeModules([
    ("telemetry-v3", 4, 9),
    ("ota-resume", 3, 6),
    ("ble-pairing", 5, 11),
    ("crash-dump", 2, 3),
])

@Suite("Part 1 - Exact fits and even A/B splits")
struct BundlePart1Tests {
    @Test("a budget some subset fills to the byte is reported as fillable")
    func exactFitsAreFound() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 7))
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 14))
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 2))
    }

    @Test("a budget no subset reaches exactly is reported as unfillable")
    func inexactBudgetsAreRejected() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 13) == false)
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 1) == false)
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 15) == false)
    }

    @Test("an empty slot is filled exactly by shipping nothing")
    func zeroBudgetIsAlwaysFillable() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.canFillExactly(modules: workedModules, budgetBytes: 0))
        #expect(try planner.canFillExactly(modules: [], budgetBytes: 0))
        #expect(try planner.canFillExactly(modules: [], budgetBytes: 3) == false)
    }

    @Test("two modules of the same size are two separate modules")
    func duplicateSizesWithDistinctIDs() throws {
        let planner = makeFreshPlanner()
        let twins = makeModules([("dup-a", 3, 1), ("dup-b", 3, 1)])
        #expect(try planner.canFillExactly(modules: twins, budgetBytes: 6))
        #expect(try planner.canFillExactly(modules: twins, budgetBytes: 3))
        #expect(try planner.canFillExactly(modules: twins, budgetBytes: 9) == false)
    }

    @Test("the worked bundle splits evenly across the two slots")
    func workedBundleSplitsEvenly() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.canSplitEvenly(modules: workedModules))
    }

    @Test("an odd total can never split evenly")
    func oddTotalCannotSplit() throws {
        let planner = makeFreshPlanner()
        let odd = makeModules([("odd-a", 4, 1), ("odd-b", 3, 1)])
        #expect(try planner.canSplitEvenly(modules: odd) == false)
    }

    @Test("an even total is not enough on its own to split evenly")
    func evenTotalStillNeedsASubset() throws {
        let planner = makeFreshPlanner()
        let stubborn = makeModules([("even-a", 4, 1), ("even-b", 3, 1), ("even-c", 5, 1)])
        #expect(try planner.canSplitEvenly(modules: stubborn) == false)
        #expect(try planner.canSplitEvenly(modules: []))
    }

    @Test("a malformed module or budget is a typed failure")
    func malformedInputsFail() {
        let planner = makeFreshPlanner()
        #expect(throws: BundleError.negativeBudget) {
            try planner.canFillExactly(modules: workedModules, budgetBytes: -1)
        }
        #expect(throws: BundleError.nonPositiveModuleSize("weightless")) {
            try planner.canFillExactly(modules: makeModules([("weightless", 0, 4)]), budgetBytes: 3)
        }
        #expect(throws: BundleError.negativeModuleValue("worthless")) {
            try planner.canSplitEvenly(modules: makeModules([("worthless", 2, -1)]))
        }
    }
}

@Suite("Part 2 - Maximise shipped value and report the choice")
struct BundlePart2Tests {
    @Test("the worked bundle ships two modules for seventeen at eight bytes")
    func workedBundleSelection() throws {
        let planner = makeFreshPlanner()
        let selection = try planner.bestSelection(modules: workedModules, budgetBytes: 8)
        try #require(selection.moduleIDs.count == 2)
        #expect(selection.moduleIDs == ["ota-resume", "ble-pairing"])
        #expect(selection.totalValue == 17)
        #expect(selection.totalSizeBytes == 8)
    }

    @Test("the densest module first is not the most valuable bundle")
    func densityGreedyLoses() throws {
        let planner = makeFreshPlanner()
        let modules = makeModules([("dense", 6, 12), ("steady-a", 5, 9), ("steady-b", 5, 9)])
        #expect(try planner.bestValue(modules: modules, budgetBytes: 10) == 18)
        let selection = try planner.bestSelection(modules: modules, budgetBytes: 10)
        try #require(selection.moduleIDs.count == 2)
        #expect(selection.moduleIDs == ["steady-a", "steady-b"])
    }

    @Test("each module ships at most once even when it would fit many times")
    func modulesShipAtMostOnce() throws {
        let planner = makeFreshPlanner()
        let single = makeModules([("tiny-jackpot", 1, 5)])
        #expect(try planner.bestValue(modules: single, budgetBytes: 4) == 5)
        let selection = try planner.bestSelection(modules: single, budgetBytes: 4)
        try #require(selection.moduleIDs.count == 1)
        #expect(selection.moduleIDs == ["tiny-jackpot"])
        #expect(selection.totalSizeBytes == 1)
    }

    @Test("an empty budget and an oversized module both ship nothing")
    func nothingFitsCases() throws {
        let planner = makeFreshPlanner()
        let empty = try planner.bestSelection(modules: workedModules, budgetBytes: 0)
        #expect(empty.totalValue == 0)
        #expect(empty.moduleIDs.isEmpty)
        #expect(empty.totalSizeBytes == 0)

        let oversized = try planner.bestSelection(modules: makeModules([("bulky", 9, 40)]), budgetBytes: 5)
        #expect(oversized.totalValue == 0)
        #expect(oversized.moduleIDs.isEmpty)
    }

    @Test("the reported selection agrees with the reported value on every fixture")
    func selectionAgreesWithValue() throws {
        let planner = makeFreshPlanner()
        let fixtures: [([FeatureModule], Int)] = [
            (workedModules, 8),
            (workedModules, 14),
            (workedModules, 6),
            (makeModules([("dense", 6, 12), ("steady-a", 5, 9), ("steady-b", 5, 9)]), 10),
        ]
        for (modules, budget) in fixtures {
            let selection = try planner.bestSelection(modules: modules, budgetBytes: budget)
            #expect(selection.totalValue == (try planner.bestValue(modules: modules, budgetBytes: budget)))
            #expect(selection.totalSizeBytes <= budget)
            #expect(Set(selection.moduleIDs).count == selection.moduleIDs.count)

            let chosen = modules.filter { selection.moduleIDs.contains($0.id) }
            #expect(chosen.reduce(0) { $0 + $1.value } == selection.totalValue)
            #expect(chosen.reduce(0) { $0 + $1.sizeBytes } == selection.totalSizeBytes)
        }
    }

    @Test("the whole bundle ships when the budget covers it")
    func generousBudgetShipsEverything() throws {
        let planner = makeFreshPlanner()
        let selection = try planner.bestSelection(modules: workedModules, budgetBytes: 20)
        try #require(selection.moduleIDs.count == 4)
        #expect(selection.moduleIDs == ["telemetry-v3", "ota-resume", "ble-pairing", "crash-dump"])
        #expect(selection.totalValue == 29)
        #expect(selection.totalSizeBytes == 14)
    }

    @Test("a negative budget is a typed failure")
    func negativeBudgetFails() {
        let planner = makeFreshPlanner()
        #expect(throws: BundleError.negativeBudget) {
            try planner.bestSelection(modules: workedModules, budgetBytes: -3)
        }
        #expect(throws: BundleError.negativeBudget) {
            try planner.bestValue(modules: workedModules, budgetBytes: -3)
        }
    }
}

@Suite("Part 3 - Count skew-balanced A/B assignments")
struct BundlePart3Tests {
    @Test("the worked bundle has two perfectly balanced assignments")
    func workedBundleBalancedAssignments() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: 0) == 2)
    }

    @Test("a balanced assignment exists exactly when the bundle splits evenly")
    func balancedCountAgreesWithTheSplitCheck() throws {
        let planner = makeFreshPlanner()
        let fixtures: [[FeatureModule]] = [
            workedModules,
            makeModules([("odd-a", 4, 1), ("odd-b", 3, 1)]),
            makeModules([("even-a", 4, 1), ("even-b", 3, 1), ("even-c", 5, 1)]),
            makeModules([("pair-a", 2, 1), ("pair-b", 2, 1)]),
        ]
        for modules in fixtures {
            let balanced = try planner.assignmentCount(modules: modules, targetSkewBytes: 0) > 0
            #expect(balanced == (try planner.canSplitEvenly(modules: modules)))
        }
    }

    @Test("a skew of the wrong parity has no assignment at all")
    func wrongParitySkewCountsNothing() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: 1) == 0)
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: -3) == 0)
    }

    @Test("a negative skew mirrors the positive one")
    func negativeSkewMirrors() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: 4) == 2)
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: -4) == 2)
    }

    @Test("a skew larger than the bundle has no assignment")
    func impossibleSkewCountsNothing() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: 20) == 0)
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: -20) == 0)
    }

    @Test("piling every module into one slot is exactly one assignment")
    func maximumSkewIsOneAssignment() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.assignmentCount(modules: workedModules, targetSkewBytes: 14) == 1)
        #expect(try planner.assignmentCount(modules: [], targetSkewBytes: 0) == 1)
    }

    @Test("a hand-counted bundle reports every assignment, not just the distinct sizes")
    func handCountedAssignments() throws {
        let planner = makeFreshPlanner()
        let modules = makeModules([("bit-a", 1, 1), ("bit-b", 1, 1), ("pair", 2, 1)])
        #expect(try planner.assignmentCount(modules: modules, targetSkewBytes: 0) == 2)
        #expect(try planner.assignmentCount(modules: modules, targetSkewBytes: 2) == 2)
        #expect(try planner.assignmentCount(modules: modules, targetSkewBytes: 4) == 1)
    }

    @Test("a malformed module is a typed failure")
    func malformedModulesFail() {
        let planner = makeFreshPlanner()
        #expect(throws: BundleError.nonPositiveModuleSize("weightless")) {
            try planner.assignmentCount(modules: makeModules([("weightless", 0, 1)]), targetSkewBytes: 0)
        }
    }
}

@Suite("Part 4 - Pad with repeatable parity blocks")
struct BundlePart4Tests {
    @Test("the largest block first does not pad the slot in the fewest blocks")
    func greedyLargestBlockLoses() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.fewestParityBlocks(remainingBytes: 6, blockSizes: [4, 3]) == 2)
        #expect(try planner.fewestParityBlocks(remainingBytes: 11, blockSizes: [1, 5, 6]) == 2)
    }

    @Test("one block size repeats as often as the padding needs it")
    func blocksRepeatFreely() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.fewestParityBlocks(remainingBytes: 9, blockSizes: [3]) == 3)
        #expect(try planner.fewestParityBlocks(remainingBytes: 7, blockSizes: [2, 5]) == 2)
    }

    @Test("a slot that is already full needs no padding at all")
    func nothingToPad() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.fewestParityBlocks(remainingBytes: 0, blockSizes: [3]) == 0)
        #expect(try planner.parityBlockCombinationCount(remainingBytes: 0, blockSizes: [3]) == 1)
        #expect(try planner.parityBlockOrderedSequenceCount(remainingBytes: 0, blockSizes: [3]) == 1)
    }

    @Test("padding that cannot land exactly on the boundary is a typed failure")
    func cannotPadExactlyFails() {
        let planner = makeFreshPlanner()
        #expect(throws: BundleError.cannotPadExactly) {
            try planner.fewestParityBlocks(remainingBytes: 7, blockSizes: [4])
        }
        #expect(throws: BundleError.cannotPadExactly) {
            try planner.fewestParityBlocks(remainingBytes: 3, blockSizes: [6])
        }
    }

    @Test("an unfillable padding counts zero ways rather than failing")
    func unfillablePaddingCountsZero() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.parityBlockCombinationCount(remainingBytes: 7, blockSizes: [4]) == 0)
        #expect(try planner.parityBlockOrderedSequenceCount(remainingBytes: 7, blockSizes: [4]) == 0)
    }

    @Test("the same padding is one multiset and two ordered sequences")
    func combinationsAndSequencesDifferOnTheSameInput() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.parityBlockCombinationCount(remainingBytes: 5, blockSizes: [2, 3]) == 1)
        #expect(try planner.parityBlockOrderedSequenceCount(remainingBytes: 5, blockSizes: [2, 3]) == 2)

        #expect(try planner.parityBlockCombinationCount(remainingBytes: 6, blockSizes: [1, 2]) == 4)
        #expect(try planner.parityBlockOrderedSequenceCount(remainingBytes: 6, blockSizes: [1, 2]) == 13)

        #expect(try planner.parityBlockCombinationCount(remainingBytes: 8, blockSizes: [2, 3, 5]) == 3)
        #expect(try planner.parityBlockOrderedSequenceCount(remainingBytes: 8, blockSizes: [2, 3, 5]) == 6)
    }

    @Test("the block catalogue's order does not change either count")
    func blockOrderDoesNotMatter() throws {
        let planner = makeFreshPlanner()
        #expect(
            try planner.parityBlockCombinationCount(remainingBytes: 8, blockSizes: [5, 2, 3])
                == (try planner.parityBlockCombinationCount(remainingBytes: 8, blockSizes: [2, 3, 5]))
        )
        #expect(
            try planner.parityBlockOrderedSequenceCount(remainingBytes: 8, blockSizes: [5, 2, 3])
                == (try planner.parityBlockOrderedSequenceCount(remainingBytes: 8, blockSizes: [2, 3, 5]))
        )
    }

    @Test("a malformed block catalogue or padding target is a typed failure")
    func malformedPaddingInputsFail() {
        let planner = makeFreshPlanner()
        #expect(throws: BundleError.emptyBlockCatalogue) {
            try planner.fewestParityBlocks(remainingBytes: 4, blockSizes: [])
        }
        #expect(throws: BundleError.emptyBlockCatalogue) {
            try planner.parityBlockCombinationCount(remainingBytes: 4, blockSizes: [])
        }
        #expect(throws: BundleError.nonPositiveBlockSize(0)) {
            try planner.parityBlockOrderedSequenceCount(remainingBytes: 4, blockSizes: [2, 0])
        }
        #expect(throws: BundleError.negativeBudget) {
            try planner.fewestParityBlocks(remainingBytes: -2, blockSizes: [2])
        }
    }

    @Test("planners are stateless: a second planner agrees and the caller's modules are untouched")
    func plannersAreIndependent() throws {
        let busy = makeFreshPlanner()
        let fresh = makeFreshPlanner()
        let modules = workedModules

        for _ in 0..<5 {
            _ = try busy.canSplitEvenly(modules: modules)
            _ = try busy.bestSelection(modules: modules, budgetBytes: 8)
            _ = try busy.assignmentCount(modules: modules, targetSkewBytes: 0)
            _ = try busy.parityBlockOrderedSequenceCount(remainingBytes: 8, blockSizes: [2, 3, 5])
        }

        #expect(try fresh.canFillExactly(modules: modules, budgetBytes: 7))
        #expect(try fresh.bestValue(modules: modules, budgetBytes: 8) == 17)
        #expect(try fresh.assignmentCount(modules: modules, targetSkewBytes: 0) == 2)
        #expect(try fresh.fewestParityBlocks(remainingBytes: 6, blockSizes: [4, 3]) == 2)
        #expect(modules == workedModules)
        #expect(try busy.bestValue(modules: modules, budgetBytes: 8) == 17)
    }
}
