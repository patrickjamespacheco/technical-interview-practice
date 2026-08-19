/// One feature module in the over-the-air bundle. Each module is unique and
/// ships at most once.
public struct FeatureModule: Equatable, Sendable {
    public let id: String
    public let sizeBytes: Int
    public let value: Int

    public init(id: String, sizeBytes: Int, value: Int) {
        self.id = id
        self.sizeBytes = sizeBytes
        self.value = value
    }
}

/// The modules a plan ships, reported alongside what they cost and what they buy.
public struct BundleSelection: Equatable, Sendable {
    public let totalValue: Int
    public let totalSizeBytes: Int
    public let moduleIDs: [String]

    public init(totalValue: Int, totalSizeBytes: Int, moduleIDs: [String]) {
        self.totalValue = totalValue
        self.totalSizeBytes = totalSizeBytes
        self.moduleIDs = moduleIDs
    }
}

public enum BundleError: Error, Equatable, Sendable {
    case negativeBudget
    case nonPositiveModuleSize(String)
    case negativeModuleValue(String)
    case nonPositiveBlockSize(Int)
    case emptyBlockCatalogue
    case cannotPadExactly
    case notImplemented
}

public struct BundlePlanner: Sendable {
    public init() {}

    // MARK: Part 1 - Exact fits and even A/B splits

    /// Whether some subset of the modules fills the budget to the byte.
    ///
    /// The shared scan does the work: one entry means "some subset of the
    /// modules seen so far sums to exactly this many bytes", and the answer is
    /// the entry at the budget.
    public func canFillExactly(modules: [FeatureModule], budgetBytes: Int) throws(BundleError) -> Bool {
        try validate(modules)
        guard budgetBytes >= 0 else { throw .negativeBudget }
        return reachableSums(modules, upTo: budgetBytes)[budgetBytes]
    }

    /// Whether the modules divide into two slots of equal size.
    ///
    /// An odd total can never halve, and that early exit matters: without it the
    /// integer division silently rounds and asks the wrong question. Otherwise
    /// this is exactly the Part 1 question asked at half the total.
    public func canSplitEvenly(modules: [FeatureModule]) throws(BundleError) -> Bool {
        try validate(modules)
        let total = modules.reduce(0) { $0 + $1.sizeBytes }
        guard total % 2 == 0 else { return false }
        return try canFillExactly(modules: modules, budgetBytes: total / 2)
    }

    // MARK: Part 2 - Maximise shipped value and report the choice

    /// The most valuable set of modules that fits the budget, and which modules
    /// those are.
    ///
    /// This keeps the full two-dimensional table on purpose. Collapsing it to a
    /// single row would still produce the right value and would destroy the
    /// backtrack, because with one row there is nothing left to walk. Ties
    /// resolve to not taking the later module, so the reported set is stable.
    public func bestSelection(modules: [FeatureModule], budgetBytes: Int) throws(BundleError) -> BundleSelection {
        try validate(modules)
        guard budgetBytes >= 0 else { throw .negativeBudget }

        // best[i][w] is the most value obtainable from the first i modules
        // within w bytes. Row 0 is "no modules", which is worth nothing at every
        // budget, and that is what makes this an at-most rather than an
        // exactly-fill table.
        var best = Array(
            repeating: Array(repeating: 0, count: budgetBytes + 1),
            count: modules.count + 1
        )
        for index in modules.indices {
            let module = modules[index]
            for budget in 0...budgetBytes {
                var candidate = best[index][budget]
                if module.sizeBytes <= budget {
                    candidate = max(candidate, module.value + best[index][budget - module.sizeBytes])
                }
                best[index + 1][budget] = candidate
            }
        }

        // A module was taken exactly when including it changed the answer, so
        // the walk back reads the decisions the table already made.
        var chosen: [String] = []
        var totalSize = 0
        var remaining = budgetBytes
        var index = modules.count
        while index > 0 {
            if best[index][remaining] != best[index - 1][remaining] {
                let module = modules[index - 1]
                chosen.append(module.id)
                totalSize += module.sizeBytes
                remaining -= module.sizeBytes
            }
            index -= 1
        }

        return BundleSelection(
            totalValue: best[modules.count][budgetBytes],
            totalSizeBytes: totalSize,
            moduleIDs: chosen.reversed()
        )
    }

    /// The value alone. The selection is the primitive and this is its projection,
    /// so the two can never disagree about what the best bundle is worth.
    public func bestValue(modules: [FeatureModule], budgetBytes: Int) throws(BundleError) -> Int {
        try bestSelection(modules: modules, budgetBytes: budgetBytes).totalValue
    }

    // MARK: Part 3 - Count skew-balanced A/B assignments

    /// How many ways the modules assign to slot A and slot B so that slot A ends
    /// up exactly `targetSkewBytes` larger than slot B.
    ///
    /// Every module goes somewhere, so naming slot A names the assignment. If
    /// slot A holds `a` bytes out of a total of `t`, the skew is `a - (t - a)`,
    /// which pins slot A at half of the total plus the skew. That has to be a
    /// whole number inside the total, and when it is not there is no assignment
    /// at all rather than an error. What is left is Part 1's scan with counts in
    /// place of flags: the same table, a different semiring.
    public func assignmentCount(modules: [FeatureModule], targetSkewBytes: Int) throws(BundleError) -> Int {
        try validate(modules)
        let total = modules.reduce(0) { $0 + $1.sizeBytes }
        let doubledSlotA = total + targetSkewBytes
        guard doubledSlotA >= 0, doubledSlotA % 2 == 0 else { return 0 }
        let slotA = doubledSlotA / 2
        guard slotA <= total else { return 0 }
        return countingSums(modules, upTo: slotA)[slotA]
    }

    // MARK: Part 4 - Pad with repeatable parity blocks

    /// The fewest parity blocks that pad the slot to exactly full.
    ///
    /// The sentinel is one more than the remaining bytes rather than the largest
    /// representable integer, so incrementing it can never overflow and it can
    /// never be mistaken for a real answer.
    public func fewestParityBlocks(remainingBytes: Int, blockSizes: [Int]) throws(BundleError) -> Int {
        let sizes = try validated(blockSizes, remainingBytes: remainingBytes)
        let unreachable = remainingBytes + 1
        var fewest = Array(repeating: unreachable, count: remainingBytes + 1)
        fewest[0] = 0

        for size in sizes where size <= remainingBytes {
            // Ascending, so a block already placed at `total - size` is visible
            // again at `total`. That is what lets one block size repeat.
            for total in size...remainingBytes {
                fewest[total] = min(fewest[total], fewest[total - size] + 1)
            }
        }

        guard fewest[remainingBytes] < unreachable else { throw .cannotPadExactly }
        return fewest[remainingBytes]
    }

    /// How many distinct multisets of parity blocks pad the slot exactly.
    ///
    /// The block loop is on the outside, so every multiset is reached in one
    /// fixed block order and is counted once.
    public func parityBlockCombinationCount(remainingBytes: Int, blockSizes: [Int]) throws(BundleError) -> Int {
        let sizes = try validated(blockSizes, remainingBytes: remainingBytes)
        var ways = Array(repeating: 0, count: remainingBytes + 1)
        ways[0] = 1

        for size in sizes where size <= remainingBytes {
            for total in size...remainingBytes {
                ways[total] += ways[total - size]
            }
        }

        return ways[remainingBytes]
    }

    /// How many ordered sequences of parity blocks pad the slot exactly.
    ///
    /// Nothing changes but the nesting. With the total on the outside, every
    /// block size gets a turn at being the last one written, so two blocks
    /// written in the other order are a second sequence. Padding five bytes from
    /// blocks of two and three is one multiset and two sequences, and the only
    /// difference between the two methods is which loop is inside the other.
    public func parityBlockOrderedSequenceCount(remainingBytes: Int, blockSizes: [Int]) throws(BundleError) -> Int {
        let sizes = try validated(blockSizes, remainingBytes: remainingBytes)
        var ways = Array(repeating: 0, count: remainingBytes + 1)
        ways[0] = 1

        guard remainingBytes >= 1 else { return ways[remainingBytes] }
        for total in 1...remainingBytes {
            for size in sizes where size <= total {
                ways[total] += ways[total - size]
            }
        }

        return ways[remainingBytes]
    }

    // MARK: Shared machinery

    private func validate(_ modules: [FeatureModule]) throws(BundleError) {
        for module in modules {
            guard module.sizeBytes > 0 else { throw .nonPositiveModuleSize(module.id) }
            guard module.value >= 0 else { throw .negativeModuleValue(module.id) }
        }
    }

    private func validated(_ blockSizes: [Int], remainingBytes: Int) throws(BundleError) -> [Int] {
        guard remainingBytes >= 0 else { throw .negativeBudget }
        guard !blockSizes.isEmpty else { throw .emptyBlockCatalogue }
        for size in blockSizes where size <= 0 { throw .nonPositiveBlockSize(size) }
        return blockSizes
    }

    /// Which byte totals up to `limit` some subset of the modules reaches exactly.
    ///
    /// The budget loop runs descending, and that single choice is what makes each
    /// module ship at most once: a descending pass only ever reads entries this
    /// module has not touched yet. Run it ascending and each module becomes
    /// reusable, which is the Part 4 recurrence wearing this method's name.
    private func reachableSums(_ modules: [FeatureModule], upTo limit: Int) -> [Bool] {
        var reachable = Array(repeating: false, count: limit + 1)
        reachable[0] = true
        for module in modules where module.sizeBytes <= limit {
            for total in stride(from: limit, through: module.sizeBytes, by: -1) {
                reachable[total] = reachable[total] || reachable[total - module.sizeBytes]
            }
        }
        return reachable
    }

    /// The same descending scan, counting subsets instead of flagging them.
    /// Combining with `||` answers whether a total is reachable; combining with
    /// `+` answers in how many ways.
    private func countingSums(_ modules: [FeatureModule], upTo limit: Int) -> [Int] {
        var ways = Array(repeating: 0, count: limit + 1)
        ways[0] = 1
        for module in modules where module.sizeBytes <= limit {
            for total in stride(from: limit, through: module.sizeBytes, by: -1) {
                ways[total] += ways[total - module.sizeBytes]
            }
        }
        return ways
    }
}
