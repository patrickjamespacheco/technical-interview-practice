import Testing
@testable import Problem37LedgerNettingFinder

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// Builds a day-file whose ids are ordered alongside its amounts, so a failure
/// message names an entry rather than an offset. Each fixture uses its own
/// prefix, which is what would expose a cache keyed on anything global.
private func dayFile(_ prefix: String, _ amounts: [Int]) -> [LedgerEntry] {
    amounts.enumerated().map { index, amount in
        LedgerEntry(id: "\(prefix)-\(index < 10 ? "0" : "")\(index)", amountMinor: amount)
    }
}

/// The worked day-file, matching the example in the problem.
private let workedAmounts = [-4, -1, -1, 0, 1, 2]
private let worked = [
    LedgerEntry(id: "je-a", amountMinor: -4),
    LedgerEntry(id: "je-b", amountMinor: -1),
    LedgerEntry(id: "je-c", amountMinor: -1),
    LedgerEntry(id: "je-d", amountMinor: 0),
    LedgerEntry(id: "je-e", amountMinor: 1),
    LedgerEntry(id: "je-f", amountMinor: 2),
]

/// A file of nothing but zeros, where every group nets to nothing and every
/// answer is one set however many entries carry it.
private let zeros = dayFile("zero", [0, 0, 0, 0])

/// Symmetric around zero with no repeated amount, so duplicate suppression is
/// out of the way and only the sweep is under test.
private let symmetric = dayFile("sym", [-3, -2, -1, 1, 2, 3])

/// Repeats on both sides of zero, which is where getting the outer skip right
/// and the inner ones wrong shows up.
private let repeated = dayFile("rep", [-1, -1, -1, 2, 2])

/// A duplicate block that the low cursor walks into, which is what separates
/// naming the earliest witness from naming wherever the sweep stopped.
private let trailingZeros = dayFile("tz", [-5, 0, 0, 0])

private let spread = dayFile("spr", [-9, -5, -2, 0, 0, 3, 7, 7, 11])
private let single = dayFile("one", [5])
private let empty: [LedgerEntry] = []

private let dayFiles: [[LedgerEntry]] = [
    worked, zeros, symmetric, repeated, trailingZeros, spread, single, empty,
]

private func makeFinder(_ ledger: [LedgerEntry]) throws -> NettingFinder {
    try NettingFinder(ledger: ledger)
}

/// Every distinct combination of `k` amounts netting to the target, named by
/// the earliest entries carrying them.
///
/// Written from the contract rather than from the sweep: it enumerates index
/// combinations in order and keeps the first witness of each multiset of
/// amounts, so it shares none of the recurrence's machinery and can be red
/// where the sweep is green.
private func bruteForceGroups(_ entries: [LedgerEntry], ofSize k: Int, summingTo target: Int) -> [EntrySet] {
    var seen: Set<[Int]> = []
    var found: [EntrySet] = []
    var combination: [Int] = []

    func walk(from start: Int) {
        if combination.count == k {
            let amounts = combination.map { entries[$0].amountMinor }
            guard amounts.reduce(0, +) == target, seen.insert(amounts).inserted else { return }
            found.append(EntrySet(entryIDs: combination.map { entries[$0].id }, total: target))
            return
        }
        guard start < entries.count else { return }
        for index in start..<entries.count {
            combination.append(index)
            walk(from: index + 1)
            combination.removeLast()
        }
    }

    walk(from: 0)
    return found
}

/// The `k` entries whose total comes closest to the target under the documented
/// tie rule: closest, then the lower total, then the earliest entries.
private func bruteForceClosest(_ entries: [LedgerEntry], ofSize k: Int, to target: Int) -> EntrySet? {
    var best: EntrySet?
    var combination: [Int] = []

    func walk(from start: Int) {
        if combination.count == k {
            let total = combination.reduce(0) { $0 + entries[$1].amountMinor }
            let candidate = EntrySet(entryIDs: combination.map { entries[$0].id }, total: total)
            guard let incumbent = best else { best = candidate; return }
            let candidateDistance = abs(total - target)
            let incumbentDistance = abs(incumbent.total - target)
            if candidateDistance < incumbentDistance
                || (candidateDistance == incumbentDistance && total < incumbent.total) {
                best = candidate
            }
            return
        }
        guard start < entries.count else { return }
        for index in start..<entries.count {
            combination.append(index)
            walk(from: index + 1)
            combination.removeLast()
        }
    }

    walk(from: 0)
    return best
}

/// Small enough that enumerating every combination in a test stays cheap.
private let probeTargets = Array(-12...12)

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Scan one range for pairs")
struct NettingFinderPart1Tests {
    @Test("the worked day-file nets to one two ways")
    func workedFilePairs() throws {
        let finder = try makeFinder(worked)
        let scan = finder.scanPairs(summingTo: 1, in: 0..<worked.count)

        try #require(scan.exactMatches.count == 2)
        #expect(scan.exactMatches[0] == EntrySet(entryIDs: ["je-b", "je-f"], total: 1))
        #expect(scan.exactMatches[1] == EntrySet(entryIDs: ["je-d", "je-e"], total: 1))
    }

    @Test("a repeated amount is one explanation, not two")
    func repeatedAmountsAreOneExplanation() throws {
        let finder = try makeFinder(worked)
        let scan = finder.scanPairs(summingTo: 0, in: 0..<worked.count)

        // Both entries carrying minus one pair with the entry carrying one.
        // That is one way of netting to nothing, not two.
        try #require(scan.exactMatches.count == 1)
        #expect(scan.exactMatches[0] == EntrySet(entryIDs: ["je-b", "je-e"], total: 0))
    }

    @Test("a reported pair names the earliest entries carrying its amounts")
    func pairsNameTheEarliestWitnesses() throws {
        let finder = try makeFinder(trailingZeros)
        let scan = finder.scanPairs(summingTo: 0, in: 0..<trailingZeros.count)

        // The high cursor stops on the last of the three zeros. Reporting it
        // rather than the first names a different entry for the same answer.
        try #require(scan.exactMatches.count == 1)
        #expect(scan.exactMatches[0] == EntrySet(entryIDs: ["tz-01", "tz-02"], total: 0))
    }

    @Test("the scan is confined to the range it is given")
    func scanRespectsItsRange() throws {
        let finder = try makeFinder(worked)

        let suffix = finder.scanPairs(summingTo: 1, in: 2..<worked.count)
        try #require(suffix.exactMatches.count == 2)
        #expect(suffix.exactMatches[0] == EntrySet(entryIDs: ["je-c", "je-f"], total: 1))
        #expect(suffix.exactMatches[1] == EntrySet(entryIDs: ["je-d", "je-e"], total: 1))

        let prefix = finder.scanPairs(summingTo: 1, in: 0..<3)
        #expect(prefix.exactMatches.isEmpty)
    }

    @Test("the nearest pair comes back whether or not anything netted exactly")
    func nearestPair() throws {
        let finder = try makeFinder(worked)

        #expect(finder.scanPairs(summingTo: 7, in: 0..<worked.count).nearest
            == EntrySet(entryIDs: ["je-e", "je-f"], total: 3))
        #expect(finder.scanPairs(summingTo: -20, in: 0..<worked.count).nearest
            == EntrySet(entryIDs: ["je-a", "je-b"], total: -5))
        #expect(finder.scanPairs(summingTo: 1, in: 0..<worked.count).nearest?.total == 1)
    }

    @Test("a range holding fewer than two entries has no pairs and no nearest")
    func rangesTooSmallToHoldAPair() throws {
        let finder = try makeFinder(worked)

        #expect(finder.scanPairs(summingTo: 0, in: 3..<4) == PairScan(exactMatches: [], nearest: nil))
        #expect(finder.scanPairs(summingTo: 0, in: 6..<6) == PairScan(exactMatches: [], nearest: nil))
        #expect(try makeFinder(empty).scanPairs(summingTo: 0, in: 0..<0)
            == PairScan(exactMatches: [], nearest: nil))
        #expect(try makeFinder(single).scanPairs(summingTo: 5, in: 0..<1)
            == PairScan(exactMatches: [], nearest: nil))
    }

    @Test("the sweep agrees with enumerating every pair, on every day-file")
    func sweepAgreesWithEnumeration() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                let scan = finder.scanPairs(summingTo: target, in: 0..<entries.count)
                #expect(scan.exactMatches == bruteForceGroups(entries, ofSize: 2, summingTo: target))
                #expect(scan.nearest == bruteForceClosest(entries, ofSize: 2, to: target))
                #expect(scan.exactMatches.allSatisfy { $0.total == target })
            }
        }
    }

    @Test("an out-of-order day-file is a typed failure naming the index")
    func unsortedLedgerFails() {
        #expect(throws: NettingError.unsortedLedger(index: 2)) {
            try NettingFinder(ledger: dayFile("bad", [-1, 4, 2]))
        }
        #expect(throws: NettingError.unsortedLedger(index: 1)) {
            try NettingFinder(ledger: [
                LedgerEntry(id: "zz", amountMinor: 3),
                LedgerEntry(id: "aa", amountMinor: 3),
            ])
        }
    }

    @Test("an amount too large to sum safely is a typed failure naming the ceiling")
    func outOfRangeAmountFails() throws {
        let ceiling = NettingFinder.maxAbsoluteAmount

        #expect(throws: NettingError.amountRangeUnsupported(maxAbsoluteAmount: ceiling)) {
            try NettingFinder(ledger: [LedgerEntry(id: "huge", amountMinor: ceiling + 1)])
        }
        #expect(throws: NettingError.amountRangeUnsupported(maxAbsoluteAmount: ceiling)) {
            try NettingFinder(ledger: [LedgerEntry(id: "huge", amountMinor: Int.min)])
        }
        // The ceiling itself is supported, and so is a whole file of it.
        let atCeiling = (0..<NettingFinder.maxGroupSize).map {
            LedgerEntry(id: "ceil-\($0)", amountMinor: ceiling)
        }
        #expect(throws: Never.self) { try NettingFinder(ledger: atCeiling) }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Triples")
struct NettingFinderPart2Tests {
    @Test("the worked day-file nets to nothing two ways")
    func workedFileTriples() throws {
        let finder = try makeFinder(worked)
        let found = finder.triples(summingTo: 0)

        try #require(found.count == 2)
        #expect(found[0] == EntrySet(entryIDs: ["je-b", "je-c", "je-f"], total: 0))
        #expect(found[1] == EntrySet(entryIDs: ["je-b", "je-d", "je-e"], total: 0))
    }

    @Test("a file of repeats reports each combination of amounts once")
    func repeatedAmountsReportOnce() throws {
        let finder = try makeFinder(repeated)
        let found = finder.triples(summingTo: 0)

        // Three entries carry minus one and two carry two. There is exactly one
        // way to net to nothing with three of them, however many entries could
        // stand in for each amount.
        try #require(found.count == 1)
        #expect(found[0] == EntrySet(entryIDs: ["rep-00", "rep-01", "rep-03"], total: 0))
    }

    @Test("a file of zeros nets to nothing exactly one way")
    func zerosNetOnce() throws {
        let finder = try makeFinder(zeros)
        let found = finder.triples(summingTo: 0)

        try #require(found.count == 1)
        #expect(found[0] == EntrySet(entryIDs: ["zero-00", "zero-01", "zero-02"], total: 0))
        #expect(finder.triples(summingTo: 1).isEmpty)
    }

    @Test("a file too short to hold three entries reports nothing")
    func filesTooShortForATriple() throws {
        #expect(try makeFinder(empty).triples(summingTo: 0).isEmpty)
        #expect(try makeFinder(single).triples(summingTo: 5).isEmpty)
        #expect(try makeFinder(dayFile("two", [1, 2])).triples(summingTo: 3).isEmpty)
    }

    @Test("every triple reported really nets to the target")
    func triplesNetToTheTarget() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                for set in finder.triples(summingTo: target) {
                    #expect(set.total == target)
                    #expect(set.entryIDs.count == 3)
                    #expect(Set(set.entryIDs).count == 3)
                }
            }
        }
    }

    @Test("the reduction agrees with enumerating every triple, on every day-file")
    func triplesAgreeWithEnumeration() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                #expect(finder.triples(summingTo: target)
                    == bruteForceGroups(entries, ofSize: 3, summingTo: target))
            }
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Nearest triple when nothing nets exactly")
struct NettingFinderPart3Tests {
    @Test("a target nothing reaches comes back with the nearest three entries")
    func nearestWhenNothingNets() throws {
        let finder = try makeFinder(worked)

        // The three largest amounts total three, and nothing gets closer to a
        // hundred than that.
        #expect(finder.closestTriple(to: 100) == EntrySet(entryIDs: ["je-d", "je-e", "je-f"], total: 3))
        #expect(finder.closestTriple(to: -9) == EntrySet(entryIDs: ["je-a", "je-b", "je-c"], total: -6))
    }

    @Test("a target that is reachable comes back exactly")
    func nearestWhenSomethingNets() throws {
        let finder = try makeFinder(worked)
        let closest = try #require(finder.closestTriple(to: 1))

        #expect(closest.total == 1)
        #expect(closest == EntrySet(entryIDs: ["je-b", "je-d", "je-f"], total: 1))
    }

    @Test("a tie between two totals resolves to the lower one")
    func tiesResolveToTheLowerTotal() throws {
        let finder = try makeFinder(symmetric)

        // Nothing nets to five here: the closest totals are four and six, each
        // one away, so the rule has to pick and it picks the lower total.
        let tied = try #require(finder.closestTriple(to: 5))
        #expect(tied.total == 4)
        #expect(tied == EntrySet(entryIDs: ["sym-02", "sym-04", "sym-05"], total: 4))

        // A target that is reachable is still reported exactly.
        #expect(finder.closestTriple(to: 0)?.total == 0)
    }

    @Test("a file too short to hold three entries has no nearest triple")
    func filesTooShortForANearestTriple() throws {
        #expect(try makeFinder(empty).closestTriple(to: 0) == nil)
        #expect(try makeFinder(single).closestTriple(to: 5) == nil)
        #expect(try makeFinder(dayFile("two", [1, 2])).closestTriple(to: 3) == nil)
    }

    @Test("an exact triple, where one exists, is always the nearest one")
    func exactTriplesAreAlwaysNearest() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                let exact = finder.triples(summingTo: target)
                guard !exact.isEmpty else { continue }
                #expect(finder.closestTriple(to: target)?.total == target)
            }
        }
    }

    @Test("the nearest triple agrees with enumerating every triple")
    func nearestAgreesWithEnumeration() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                #expect(finder.closestTriple(to: target)
                    == bruteForceClosest(entries, ofSize: 3, to: target))
            }
        }
    }

    @Test("an unreachable target does not end the process")
    func extremeTargetsSaturateRatherThanTrap() throws {
        let finder = try makeFinder(worked)

        #expect(finder.closestTriple(to: Int.max)?.total == 3)
        #expect(finder.closestTriple(to: Int.min)?.total == -6)
        #expect(finder.scanPairs(summingTo: Int.max, in: 0..<worked.count).nearest?.total == 3)
        #expect(finder.scanPairs(summingTo: Int.min, in: 0..<worked.count).exactMatches.isEmpty)
    }
}

// ── Part 4 ───────────────────────────────────────────────────────────────────

@Suite("Part 4 - The general k-entry reduction")
struct NettingFinderPart4Tests {
    @Test("the worked day-file nets to minus two with four entries")
    func workedFileQuadruples() throws {
        let finder = try makeFinder(worked)
        let found = try finder.groups(ofSize: 4, summingTo: -2)

        try #require(found.count == 1)
        #expect(found[0] == EntrySet(entryIDs: ["je-a", "je-b", "je-e", "je-f"], total: -2))
    }

    @Test("a group of one is a single entry carrying the target")
    func groupsOfOne() throws {
        let finder = try makeFinder(worked)
        let found = try finder.groups(ofSize: 1, summingTo: 2)

        try #require(found.count == 1)
        #expect(found[0] == EntrySet(entryIDs: ["je-f"], total: 2))
        #expect(try finder.groups(ofSize: 1, summingTo: 9).isEmpty)
    }

    @Test("a group the size of the file is the whole file")
    func groupsSpanningTheWholeFile() throws {
        let finder = try makeFinder(worked)
        let found = try finder.groups(ofSize: worked.count, summingTo: workedAmounts.reduce(0, +))

        try #require(found.count == 1)
        #expect(found[0].entryIDs == worked.map(\.id))
    }

    @Test("groups of two are the Part 1 sweep over the whole file")
    func groupsOfTwoAreThePairScan() throws {
        for entries in dayFiles where entries.count >= 2 {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                #expect(try finder.groups(ofSize: 2, summingTo: target)
                    == finder.scanPairs(summingTo: target, in: 0..<entries.count).exactMatches)
            }
        }
    }

    @Test("groups of three are the Part 2 triples")
    func groupsOfThreeAreTheTriples() throws {
        for entries in dayFiles where entries.count >= 3 {
            let finder = try makeFinder(entries)
            for target in probeTargets {
                #expect(try finder.groups(ofSize: 3, summingTo: target)
                    == finder.triples(summingTo: target))
            }
        }
    }

    @Test("the reduction agrees with enumerating every group, for every size")
    func reductionAgreesWithEnumeration() throws {
        for entries in dayFiles {
            let finder = try makeFinder(entries)
            for k in 1...5 where k <= entries.count {
                for target in probeTargets {
                    #expect(try finder.groups(ofSize: k, summingTo: target)
                        == bruteForceGroups(entries, ofSize: k, summingTo: target))
                }
            }
        }
    }

    @Test("an impossible group size is a typed failure rather than an empty answer")
    func invalidGroupSizesFail() throws {
        let finder = try makeFinder(worked)

        #expect(throws: NettingError.nonPositiveGroupSize(0)) {
            try finder.groups(ofSize: 0, summingTo: 0)
        }
        #expect(throws: NettingError.nonPositiveGroupSize(-3)) {
            try finder.groups(ofSize: -3, summingTo: 0)
        }
        #expect(throws: NettingError.groupSizeExceedsLedger(7)) {
            try finder.groups(ofSize: 7, summingTo: 0)
        }
    }

    @Test("a group size above the supported maximum is refused before any arithmetic")
    func groupSizeAboveTheOverflowCeilingFails() throws {
        let ceiling = NettingFinder.maxGroupSize
        let big = (0...ceiling).map { LedgerEntry(id: "big-\($0)", amountMinor: $0) }
        let finder = try makeFinder(big)

        #expect(throws: NettingError.groupSizeExceedsSupportedMaximum(k: ceiling + 1, maximum: ceiling)) {
            try finder.groups(ofSize: ceiling + 1, summingTo: 0)
        }
        // At the ceiling itself, with every amount at its own ceiling, the sum
        // still fits and the answer comes back rather than the process ending.
        let extreme = (0..<ceiling).map {
            LedgerEntry(id: "max-\($0)", amountMinor: NettingFinder.maxAbsoluteAmount)
        }
        let extremeFinder = try makeFinder(extreme)
        let total = NettingFinder.maxAbsoluteAmount * ceiling
        #expect(try extremeFinder.groups(ofSize: ceiling, summingTo: total).count == 1)
    }

    @Test("finders are independent and never mutate the file they are given")
    func findersAreIndependentAndNonMutating() throws {
        var file = worked
        let original = file

        let busy = try makeFinder(file)
        let fresh = try makeFinder(original)
        let other = try makeFinder(spread)

        for _ in 0..<5 {
            _ = busy.triples(summingTo: 0)
            _ = busy.closestTriple(to: 40)
            _ = try busy.groups(ofSize: 4, summingTo: -2)
            _ = other.triples(summingTo: 0)
        }

        // A second finder over the same file still reports the documented
        // answers, which is what a table cached in static storage would break.
        #expect(fresh.triples(summingTo: 0).count == 2)
        #expect(fresh.closestTriple(to: 100) == EntrySet(entryIDs: ["je-d", "je-e", "je-f"], total: 3))
        #expect(try fresh.groups(ofSize: 4, summingTo: -2).count == 1)

        // Two finders over different files answer independently.
        #expect(busy.triples(summingTo: 0).count == 2)
        #expect(other.triples(summingTo: 0)
            == bruteForceGroups(spread, ofSize: 3, summingTo: 0))
        #expect(busy.triples(summingTo: 0).count == 2)

        // The caller's file is untouched, and a caller emptying its own copy
        // changes nothing about a finder already holding it.
        #expect(file == original)
        #expect(busy.entries == original)
        file.removeAll()
        #expect(busy.entries == original)
        #expect(busy.triples(summingTo: 0).count == 2)
    }
}
