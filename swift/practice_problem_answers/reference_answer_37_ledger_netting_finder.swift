public struct LedgerEntry: Equatable, Sendable {
    public let id: String
    public let amountMinor: Int

    public init(id: String, amountMinor: Int) {
        self.id = id
        self.amountMinor = amountMinor
    }
}

public struct EntrySet: Equatable, Sendable {
    public let entryIDs: [String]
    public let total: Int

    public init(entryIDs: [String], total: Int) {
        self.entryIDs = entryIDs
        self.total = total
    }
}

public struct PairScan: Equatable, Sendable {
    public let exactMatches: [EntrySet]
    public let nearest: EntrySet?

    public init(exactMatches: [EntrySet], nearest: EntrySet?) {
        self.exactMatches = exactMatches
        self.nearest = nearest
    }
}

public enum NettingError: Error, Equatable, Sendable {
    case unsortedLedger(index: Int)
    case nonPositiveGroupSize(Int)
    case groupSizeExceedsLedger(Int)
    case groupSizeExceedsSupportedMaximum(k: Int, maximum: Int)
    case amountRangeUnsupported(maxAbsoluteAmount: Int)
    case notImplemented
}

public struct NettingFinder: Sendable {
    /// The largest group this finder will assemble. Sums of up to this many
    /// amounts are what the range guard below is sized against.
    public static let maxGroupSize = 8

    /// The ceiling on a single entry's magnitude. It is a machine limit rather
    /// than an accounting one: Swift traps on `Int` overflow in debug and in
    /// release alike, so a sum that does not fit ends the process instead of
    /// returning a wrong number. Bounding a single amount here is what makes
    /// every sum of up to `maxGroupSize` amounts safe without a check inside
    /// the sweep.
    public static let maxAbsoluteAmount = Int.max / (maxGroupSize + 1)

    private let ledger: [LedgerEntry]

    public init(ledger: [LedgerEntry]) throws(NettingError) {
        for (index, entry) in ledger.enumerated() {
            guard entry.amountMinor.magnitude <= UInt(Self.maxAbsoluteAmount) else {
                throw .amountRangeUnsupported(maxAbsoluteAmount: Self.maxAbsoluteAmount)
            }
            guard index > 0 else { continue }
            let previous = ledger[index - 1]
            let ordered = previous.amountMinor < entry.amountMinor
                || (previous.amountMinor == entry.amountMinor && previous.id <= entry.id)
            guard ordered else { throw .unsortedLedger(index: index) }
        }
        self.ledger = ledger
    }

    /// The day-file as read, for a caller that wants to check what it handed in.
    public var entries: [LedgerEntry] { ledger }

    // MARK: Part 1 - Scan one range for pairs

    /// Every pair inside `range` whose amounts net to `target`, plus the pair
    /// that came closest whether or not any of them landed.
    ///
    /// Two cursors converge from the ends of the range. Sortedness is what
    /// makes that legal: when the running sum is under the target the only way
    /// to raise it is to give up the smallest amount still in play, and when it
    /// is over, the only way to lower it is to give up the largest.
    ///
    /// The nearest pair rides along rather than being computed by a second
    /// sweep, because the callers in later parts need it. A method that
    /// returned only the exact matches would force each of them to re-run this
    /// whole sweep with a different accumulator, which is the same algorithm
    /// written twice.
    ///
    /// Two sets naming the same amounts are one explanation for a reconciler,
    /// so a repeated amount is consumed once: after a hit, both cursors step
    /// past every entry carrying the amount they just used, and every reported
    /// set names the earliest entries carrying its amounts.
    public func scanPairs(summingTo target: Int, in range: Range<Int>) -> PairScan {
        var lo = max(range.lowerBound, 0)
        var hi = min(range.upperBound, ledger.count) - 1

        var exactMatches: [EntrySet] = []
        var nearest: EntrySet?

        while lo < hi {
            let sum = ledger[lo].amountMinor + ledger[hi].amountMinor

            if isCloser(sum, than: nearest, to: target) {
                nearest = set(at: [lo, earliestWitness(of: hi, after: lo)], total: sum)
            }

            if sum == target {
                exactMatches.append(set(at: [lo, earliestWitness(of: hi, after: lo)], total: sum))

                let lowAmount = ledger[lo].amountMinor
                let highAmount = ledger[hi].amountMinor
                while lo < hi, ledger[lo].amountMinor == lowAmount { lo += 1 }
                while lo < hi, ledger[hi].amountMinor == highAmount { hi -= 1 }
            } else if sum < target {
                lo += 1
            } else {
                hi -= 1
            }
        }

        return PairScan(exactMatches: exactMatches, nearest: nearest)
    }

    // MARK: Part 2 - Triples

    /// Every distinct set of three entries netting to `target`.
    ///
    /// The sweep from Part 1 becomes the inner loop. Fixing the first entry
    /// turns the question into a pair question over the suffix after it, which
    /// is the whole reduction, and the range argument is what lets that suffix
    /// be handed down without copying the file.
    ///
    /// Duplicate suppression happens in two places and both are needed. The
    /// outer loop skips an amount equal to the one it just used, because that
    /// entry would ask the same question of a shorter suffix and get back a
    /// subset of the same answers. The inner skips live in Part 1.
    public func triples(summingTo target: Int) -> [EntrySet] {
        var results: [EntrySet] = []
        guard ledger.count >= 3 else { return results }

        for index in 0...(ledger.count - 3) {
            if index > 0, ledger[index].amountMinor == ledger[index - 1].amountMinor { continue }

            let scan = scanPairs(
                summingTo: residual(of: target, minus: ledger[index].amountMinor),
                in: (index + 1)..<ledger.count
            )
            for pair in scan.exactMatches {
                results.append(prepending(index, to: pair))
            }
        }

        return results
    }

    // MARK: Part 3 - Nearest triple when nothing nets exactly

    /// The set of three entries whose total comes closest to `target`.
    ///
    /// This is the same outer enumeration as Part 2 reading the other half of
    /// what Part 1 already returns. Nothing about the sweep is rewritten, which
    /// is exactly what the richer return type bought.
    ///
    /// Ties resolve to the lower total, and then to the entries that appear
    /// earlier in the file, so two runs over one day-file cannot disagree.
    public func closestTriple(to target: Int) -> EntrySet? {
        guard ledger.count >= 3 else { return nil }

        var best: EntrySet?
        for index in 0...(ledger.count - 3) {
            if index > 0, ledger[index].amountMinor == ledger[index - 1].amountMinor { continue }

            let scan = scanPairs(
                summingTo: residual(of: target, minus: ledger[index].amountMinor),
                in: (index + 1)..<ledger.count
            )
            guard let pair = scan.nearest else { continue }

            let candidate = prepending(index, to: pair)
            if isCloser(candidate.total, than: best, to: target) {
                best = candidate
            }
        }

        return best
    }

    // MARK: Part 4 - The general k-entry reduction

    /// Every distinct set of exactly `k` entries netting to `target`.
    ///
    /// The reduction is the point: a k-sum is a (k - 1)-sum over each suffix,
    /// and the recursion bottoms out in exactly one call to the Part 1 sweep
    /// when two entries are left to place. There is one sweep in this file and
    /// four questions asked of it.
    public func groups(ofSize k: Int, summingTo target: Int) throws(NettingError) -> [EntrySet] {
        guard k > 0 else { throw .nonPositiveGroupSize(k) }
        guard k <= Self.maxGroupSize else {
            throw .groupSizeExceedsSupportedMaximum(k: k, maximum: Self.maxGroupSize)
        }
        guard k <= ledger.count else { throw .groupSizeExceedsLedger(k) }

        return reduce(k: k, summingTo: target, from: 0)
    }

    // MARK: The reduction, and the pieces every part shares

    private func reduce(k: Int, summingTo target: Int, from start: Int) -> [EntrySet] {
        if k == 2 {
            return scanPairs(summingTo: target, in: start..<ledger.count).exactMatches
        }
        if k == 1 {
            guard let index = (start..<ledger.count).first(where: { ledger[$0].amountMinor == target })
            else { return [] }
            return [set(at: [index], total: target)]
        }

        var results: [EntrySet] = []
        var index = start
        while index <= ledger.count - k {
            defer { index += 1 }
            if index > start, ledger[index].amountMinor == ledger[index - 1].amountMinor { continue }

            let deeper = reduce(
                k: k - 1,
                summingTo: residual(of: target, minus: ledger[index].amountMinor),
                from: index + 1
            )
            for group in deeper {
                results.append(prepending(index, to: group))
            }
        }

        return results
    }

    private func set(at indices: [Int], total: Int) -> EntrySet {
        EntrySet(entryIDs: indices.map { ledger[$0].id }, total: total)
    }

    private func prepending(_ index: Int, to group: EntrySet) -> EntrySet {
        EntrySet(
            entryIDs: [ledger[index].id] + group.entryIDs,
            total: ledger[index].amountMinor + group.total
        )
    }

    /// The target the rest of a group has to reach once one entry is fixed.
    ///
    /// A caller may pass any `Int` as a target, and the entry amounts are
    /// bounded but the target is not, so this subtraction is the one place in
    /// the file where overflow is reachable. Saturating is the right answer
    /// rather than trapping or wrapping: a residual that does not fit in an
    /// `Int` is one no bounded group of amounts can ever reach, and the
    /// saturated value behaves exactly like the unreachable target it stands
    /// for, including for the nearest-miss question.
    private func residual(of target: Int, minus amount: Int) -> Int {
        let (value, overflowed) = target.subtractingReportingOverflow(amount)
        guard overflowed else { return value }
        return amount < 0 ? Int.max : Int.min
    }

    /// How far a total sits from the target, saturating rather than trapping
    /// for the same reason the residual does.
    private func distance(_ total: Int, to target: Int) -> Int {
        let (value, overflowed) = total.subtractingReportingOverflow(target)
        guard !overflowed, value != Int.min else { return Int.max }
        return value < 0 ? -value : value
    }

    /// The earliest entry after `lo` carrying the same amount as `index`.
    ///
    /// A hit can only land on a block boundary, because advancing a cursor
    /// inside a run of equal amounts leaves the sum unchanged. So the low
    /// cursor is already on the first entry carrying its amount while the high
    /// cursor is on the last entry carrying its own, and naming the first of
    /// both is what makes a reported set the earliest witness rather than
    /// whichever entry the sweep happened to stop on.
    private func earliestWitness(of index: Int, after lo: Int) -> Int {
        let amount = ledger[index].amountMinor
        var witness = index
        while witness - 1 > lo, ledger[witness - 1].amountMinor == amount {
            witness -= 1
        }
        return witness
    }

    /// The nearest-miss ordering, stated once so Parts 1 and 3 cannot drift:
    /// closer wins, then the lower total, then the entries that appear earlier
    /// in the file, which the sweep and the outer enumeration both reach first.
    private func isCloser(_ total: Int, than current: EntrySet?, to target: Int) -> Bool {
        guard let current else { return true }

        let candidate = distance(total, to: target)
        let incumbent = distance(current.total, to: target)
        if candidate != incumbent { return candidate < incumbent }
        return total < current.total
    }
}
