import Testing
@testable import Problem72FilingDeadlineSequencer

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// The worked backlog. Taken in deadline order it overruns on the last filing,
/// and what gets given back is not that filing.
private let f1 = Filing(id: "f1", statutoryType: "tax", reviewHours: 100, deadlineHour: 200)
private let backlog = [
    f1,
    Filing(id: "f2", statutoryType: "tax", reviewHours: 200, deadlineHour: 1300),
    Filing(id: "f3", statutoryType: "labour", reviewHours: 1000, deadlineHour: 1250),
    Filing(id: "f4", statutoryType: "labour", reviewHours: 2000, deadlineHour: 3200),
]

/// The filing given back here is the very first one, several steps after it was
/// accepted. A sequencer that skips the filing in hand instead lodges two.
private let regretBacklog = [
    Filing(id: "r1", statutoryType: "tax", reviewHours: 100, deadlineHour: 100),
    Filing(id: "r2", statutoryType: "tax", reviewHours: 50, deadlineHour: 160),
    Filing(id: "r3", statutoryType: "vat", reviewHours: 50, deadlineHour: 180),
    Filing(id: "r4", statutoryType: "vat", reviewHours: 50, deadlineHour: 190),
]

/// Shortest-first works the one-hour filing first and then misses the long one
/// by a single hour. Deadline order lodges both.
private let shortestFirstTrap = [
    Filing(id: "h1", statutoryType: "vat", reviewHours: 1, deadlineHour: 1000),
    Filing(id: "h2", statutoryType: "vat", reviewHours: 900, deadlineHour: 900),
]

/// A filing that cannot be lodged on time however it is ordered.
private let hopeless = [
    Filing(id: "x1", statutoryType: "tax", reviewHours: 50, deadlineHour: 10)
]

/// Everything fits with room to spare, so nothing is ever given back.
private let comfortable = [
    Filing(id: "e1", statutoryType: "tax", reviewHours: 1, deadlineHour: 100),
    Filing(id: "e2", statutoryType: "vat", reviewHours: 2, deadlineHour: 200),
    Filing(id: "e3", statutoryType: "duty", reviewHours: 3, deadlineHour: 300),
]

private let backlogs: [[Filing]] = [
    backlog, regretBacklog, shortestFirstTrap, hopeless, comfortable, [f1], [],
]

/// One statutory type appears three times and three others once each. The
/// skeleton the busiest type dictates is shorter than the backlog itself.
private let manyTypes = [
    Filing(id: "c1", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
    Filing(id: "c2", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
    Filing(id: "c3", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
    Filing(id: "c4", statutoryType: "vat", reviewHours: 1, deadlineHour: 99),
    Filing(id: "c5", statutoryType: "duty", reviewHours: 1, deadlineHour: 99),
    Filing(id: "c6", statutoryType: "levy", reviewHours: 1, deadlineHour: 99),
]

/// Two types tied at the top, which is the term a skeleton built from the
/// busiest count alone leaves out.
private let t1 = Filing(id: "t1", statutoryType: "tax", reviewHours: 1, deadlineHour: 99)
private let t2 = Filing(id: "t2", statutoryType: "tax", reviewHours: 1, deadlineHour: 99)
private let t3 = Filing(id: "t3", statutoryType: "vat", reviewHours: 1, deadlineHour: 99)
private let t4 = Filing(id: "t4", statutoryType: "vat", reviewHours: 1, deadlineHour: 99)
private let tiedTypes = [t1, t2, t3, t4]

/// One type only, so the whole schedule is settling gaps.
private let oneTypeOnly = [
    Filing(id: "p1", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
    Filing(id: "p2", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
]

private let lodgementBacklogs: [[Filing]] = [
    manyTypes, tiedTypes, oneTypeOnly, comfortable, backlog, [f1], [],
]

private func makeSequencer() -> FilingSequencer {
    FilingSequencer()
}

/// The largest schedulable subset, found by enumerating every subset and
/// testing feasibility directly. Written here so it cannot share the
/// sequencer's bugs, and only usable on the small fixtures.
private func bruteForceMaximumLodged(_ filings: [Filing]) -> Int {
    precondition(filings.count <= 12, "exhaustive search is for small fixtures only")
    var best = 0
    for mask in 0..<(1 << filings.count) {
        var chosen: [Filing] = []
        for index in filings.indices where mask & (1 << index) != 0 {
            chosen.append(filings[index])
        }
        chosen.sort { $0.deadlineHour == $1.deadlineHour ? $0.id < $1.id : $0.deadlineHour < $1.deadlineHour }
        var clock = 0
        var feasible = true
        for filing in chosen {
            clock += filing.reviewHours
            if clock > filing.deadlineHour {
                feasible = false
                break
            }
        }
        if feasible {
            best = max(best, chosen.count)
        }
    }
    return best
}

/// The elapsed hours a tick-by-tick simulation needs: at every hour lodge the
/// type with the most left that is out of its settling gap, and idle when
/// none is. Written independently of the arithmetic the sequencer uses.
private func simulateLodgementHours(_ filings: [Filing], settlingGap: Int) -> Int {
    var remaining: [String: Int] = [:]
    for filing in filings {
        remaining[filing.statutoryType, default: 0] += 1
    }
    var readyAt: [String: Int] = [:]
    var outstanding = filings.count
    var hour = 0

    while outstanding > 0 {
        let ready = remaining
            .filter { $0.value > 0 && (readyAt[$0.key] ?? 0) <= hour }
            .max { left, right in
                left.value == right.value ? left.key > right.key : left.value < right.value
            }
        if let choice = ready {
            remaining[choice.key] = choice.value - 1
            readyAt[choice.key] = hour + settlingGap + 1
            outstanding -= 1
        }
        hour += 1
    }
    return hour
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Replay a proposed order")
struct FilingSequencerPart1Tests {
    @Test("the worked backlog orders by statutory deadline")
    func workedBacklogOrdering() throws {
        let sequencer = makeSequencer()
        let ordered = try sequencer.orderedByDeadline(backlog)

        try #require(ordered.count == 4)
        #expect(ordered.map(\.id) == ["f1", "f3", "f2", "f4"])
    }

    @Test("filings sharing a deadline order by id")
    func tiesOrderByID() throws {
        let sequencer = makeSequencer()
        let ordered = try sequencer.orderedByDeadline([t4, t1, t3])

        try #require(ordered.count == 3)
        #expect(ordered.map(\.id) == ["t1", "t3", "t4"])
    }

    @Test("replaying the backlog as given lodges two of its four filings")
    func replayTheBacklogAsGiven() throws {
        let sequencer = makeSequencer()
        let trace = try sequencer.replay(backlog)

        #expect(trace == ScheduleTrace(lodged: ["f1", "f2"], missed: ["f3", "f4"], finishHour: 3300))
    }

    @Test("a missed filing still consumes its review hours")
    func missedFilingsStillCost() throws {
        let sequencer = makeSequencer()
        let trace = try sequencer.replay(hopeless)

        // The work was done, it was simply done too late. A replay that skips
        // missed filings reports a finishing hour of zero here.
        #expect(trace == ScheduleTrace(lodged: [], missed: ["x1"], finishHour: 50))
    }

    @Test("shortest-first misses a filing that deadline order lodges")
    func shortestFirstMissesOne() throws {
        let sequencer = makeSequencer()
        let byShortest = shortestFirstTrap.sorted { $0.reviewHours < $1.reviewHours }
        let byDeadline = try sequencer.orderedByDeadline(shortestFirstTrap)

        #expect(try sequencer.replay(byShortest).missed == ["h2"])
        #expect(try sequencer.replay(byDeadline).missed == [])
    }

    @Test("a replay accounts for every filing exactly once")
    func replayAccountsForEverything() throws {
        let sequencer = makeSequencer()
        for order in backlogs {
            let trace = try sequencer.replay(order)
            #expect(trace.lodged.count + trace.missed.count == order.count)
            #expect(Set(trace.lodged).union(Set(trace.missed)) == Set(order.map(\.id)))
            #expect(trace.finishHour == order.reduce(0) { $0 + $1.reviewHours })
        }
    }

    @Test("an empty backlog replays to an empty trace rather than failing")
    func emptyBacklogReplays() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.replay([]) == ScheduleTrace(lodged: [], missed: [], finishHour: 0))
        #expect(try sequencer.orderedByDeadline([]) == [])
    }

    @Test("a non-positive review count or deadline is a typed failure naming it")
    func invalidFilingFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.nonPositiveReviewHours(id: "z1")) {
            try sequencer.replay([Filing(id: "z1", statutoryType: "tax", reviewHours: 0, deadlineHour: 10)])
        }
        #expect(throws: SequencingError.nonPositiveDeadline(id: "z2")) {
            try sequencer.orderedByDeadline([Filing(id: "z2", statutoryType: "tax", reviewHours: 5, deadlineHour: 0)])
        }
    }

    @Test("an hour figure beyond the supported range is refused, not overflowed")
    func outOfRangeHoursFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.hoursOutOfRange(id: "z3")) {
            try sequencer.replay([
                Filing(
                    id: "z3",
                    statutoryType: "tax",
                    reviewHours: FilingSequencer.maximumHour + 1,
                    deadlineHour: 10
                )
            ])
        }
        #expect(throws: SequencingError.hoursOutOfRange(id: "z4")) {
            try sequencer.orderedByDeadline([
                Filing(
                    id: "z4",
                    statutoryType: "tax",
                    reviewHours: 5,
                    deadlineHour: FilingSequencer.maximumHour + 1
                )
            ])
        }
    }

    @Test("a repeated filing id is a typed failure naming it")
    func duplicateFilingFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.duplicateFilingID("f1")) {
            try sequencer.orderedByDeadline(backlog + [
                Filing(id: "f1", statutoryType: "vat", reviewHours: 1, deadlineHour: 10)
            ])
        }
    }

    @Test("a backlog larger than the supported filing count is a typed failure")
    func tooManyFilingsFails() {
        let sequencer = makeSequencer()
        let oversized = (0...FilingSequencer.maximumFilingCount).map {
            Filing(id: "over-\($0)", statutoryType: "tax", reviewHours: 1, deadlineHour: $0 + 1)
        }

        #expect(throws: SequencingError.tooManyFilings(FilingSequencer.maximumFilingCount + 1)) {
            try sequencer.replay(oversized)
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Maximum filings lodged")
struct FilingSequencerPart2Tests {
    @Test("the worked backlog lodges three of its four filings")
    func workedBacklogCount() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.maximumLodged(backlog) == 3)
    }

    @Test("giving back an earlier filing lodges one more than skipping does")
    func regretBeatsSkipping() throws {
        let sequencer = makeSequencer()

        // The overrun happens on the fourth filing, and the right move is to
        // give back the hundred-hour filing accepted first. A sequencer that
        // skips the filing in hand lodges two here.
        #expect(try sequencer.maximumLodged(regretBacklog) == 3)
    }

    @Test("deadline order lodges both filings where shortest-first lodges one")
    func deadlineOrderBeatsShortestFirst() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.maximumLodged(shortestFirstTrap) == 2)
    }

    @Test("a filing that can never be lodged on time counts for nothing")
    func hopelessFilingCountsForNothing() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.maximumLodged(hopeless) == 0)
        #expect(try sequencer.maximumLodged([]) == 0)
    }

    @Test("a comfortable backlog lodges everything")
    func comfortableBacklogLodgesEverything() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.maximumLodged(comfortable) == 3)
    }

    @Test("the sequencer matches an exhaustive search over every subset")
    func matchesExhaustiveSearch() throws {
        let sequencer = makeSequencer()
        for filings in backlogs {
            #expect(try sequencer.maximumLodged(filings) == bruteForceMaximumLodged(filings))
        }
    }

    @Test("a malformed backlog is a typed failure here too")
    func malformedBacklogFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.nonPositiveReviewHours(id: "z5")) {
            try sequencer.maximumLodged([Filing(id: "z5", statutoryType: "tax", reviewHours: -1, deadlineHour: 10)])
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Report the selection")
struct FilingSequencerPart3Tests {
    @Test("the worked backlog names the three filings it lodges")
    func workedBacklogSelection() throws {
        let sequencer = makeSequencer()
        let selected = try sequencer.selectedFilings(backlog)

        try #require(selected.count == 3)
        #expect(selected == ["f1", "f3", "f2"])
    }

    @Test("the selection drops the filing given back, not the one in hand")
    func regretSelection() throws {
        let sequencer = makeSequencer()
        let selected = try sequencer.selectedFilings(regretBacklog)

        // r1 was accepted first and handed back later; every filing that
        // arrived after it survives.
        try #require(selected.count == 3)
        #expect(selected == ["r2", "r3", "r4"])
    }

    @Test("the selection comes back in the order the reviewer works it")
    func selectionIsInWorkingOrder() throws {
        let sequencer = makeSequencer()
        let selected = try sequencer.selectedFilings(shortestFirstTrap)

        try #require(selected.count == 2)
        #expect(selected == ["h2", "h1"])
    }

    @Test("an empty or hopeless backlog selects nothing rather than failing")
    func nothingToSelect() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.selectedFilings([]) == [])
        #expect(try sequencer.selectedFilings(hopeless) == [])
    }

    @Test("the count is the size of the selection, not a separate answer")
    func countAgreesWithSelection() throws {
        let sequencer = makeSequencer()
        for filings in backlogs {
            #expect(try sequencer.maximumLodged(filings) == sequencer.selectedFilings(filings).count)
        }
    }

    @Test("replaying the selection lodges every filing in it and misses none")
    func replayingTheSelectionMissesNothing() throws {
        let sequencer = makeSequencer()
        for filings in backlogs {
            let selected = try sequencer.selectedFilings(filings)
            let byID = Dictionary(uniqueKeysWithValues: filings.map { ($0.id, $0) })
            var order: [Filing] = []
            for id in selected {
                order.append(try #require(byID[id]))
            }

            // A plausible-looking selection that does not actually fit is
            // exactly what this catches, and no other assertion here would.
            let trace = try sequencer.replay(order)
            #expect(trace.missed == [])
            #expect(trace.lodged == selected)
        }
    }

    @Test("every selected filing is one that was in the backlog")
    func selectionIsASubsetOfTheBacklog() throws {
        let sequencer = makeSequencer()
        for filings in backlogs {
            let selected = try sequencer.selectedFilings(filings)
            #expect(Set(selected).isSubset(of: Set(filings.map(\.id))))
            #expect(Set(selected).count == selected.count)
        }
    }

    @Test("a malformed backlog is a typed failure here too")
    func malformedBacklogFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.duplicateFilingID("e1")) {
            try sequencer.selectedFilings(comfortable + [
                Filing(id: "e1", statutoryType: "tax", reviewHours: 1, deadlineHour: 5)
            ])
        }
    }
}

// ── Part 4 ───────────────────────────────────────────────────────────────────

@Suite("Part 4 - Least elapsed time under a settling gap")
struct FilingSequencerPart4Tests {
    @Test("the worked lodgement example takes four hours")
    func workedLodgementExample() throws {
        let sequencer = makeSequencer()
        let unitBacklog = [
            Filing(id: "a", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
            Filing(id: "b", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
            Filing(id: "c", statutoryType: "vat", reviewHours: 1, deadlineHour: 99),
        ]

        #expect(try sequencer.leastElapsedHours(unitBacklog, settlingGap: 2) == 4)
    }

    @Test("many distinct types leave no idle hours at all")
    func manyTypesLeaveNoIdleTime() throws {
        let sequencer = makeSequencer()

        // The busiest type appears three times, so a skeleton of blocks
        // predicts five hours. There are six filings and no hour is ever idle,
        // so the answer is six. This is the case the clamp exists for.
        #expect(try sequencer.leastElapsedHours(manyTypes, settlingGap: 1) == 6)
    }

    @Test("a wide settling gap forces idle hours the backlog cannot fill")
    func wideGapForcesIdling() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.leastElapsedHours(manyTypes, settlingGap: 3) == 9)
        #expect(try sequencer.leastElapsedHours(oneTypeOnly, settlingGap: 5) == 7)
    }

    @Test("types tied at the busiest count each add an hour")
    func tiedTypesEachAddAnHour() throws {
        let sequencer = makeSequencer()

        // Dropping the tie term reports four here and six at a gap of four.
        #expect(try sequencer.leastElapsedHours(tiedTypes, settlingGap: 2) == 5)
        #expect(try sequencer.leastElapsedHours(tiedTypes, settlingGap: 4) == 7)
    }

    @Test("no settling gap means the backlog takes one hour per filing")
    func noGapMeansNoIdling() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.leastElapsedHours(manyTypes, settlingGap: 0) == 6)
        #expect(try sequencer.leastElapsedHours(tiedTypes, settlingGap: 0) == 4)
    }

    @Test("an empty backlog takes no time rather than failing")
    func emptyBacklogTakesNoTime() throws {
        let sequencer = makeSequencer()

        #expect(try sequencer.leastElapsedHours([], settlingGap: 3) == 0)
    }

    @Test("the arithmetic matches an hour-by-hour simulation on every fixture")
    func arithmeticMatchesSimulation() throws {
        let sequencer = makeSequencer()
        for filings in lodgementBacklogs {
            for gap in 0...5 {
                // The two parts optimise different quantities, so nothing here
                // can be checked against the deadline sweep. An independently
                // written simulation of this objective is the honest check.
                #expect(
                    try sequencer.leastElapsedHours(filings, settlingGap: gap)
                        == simulateLodgementHours(filings, settlingGap: gap)
                )
            }
        }
    }

    @Test("a negative settling gap is a typed failure")
    func negativeGapFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.negativeSettlingGap(-1)) {
            try sequencer.leastElapsedHours(manyTypes, settlingGap: -1)
        }
    }

    @Test("a settling gap beyond the supported range is refused, not overflowed")
    func outOfRangeGapFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.settlingGapOutOfRange(FilingSequencer.maximumSettlingGap + 1)) {
            try sequencer.leastElapsedHours(manyTypes, settlingGap: FilingSequencer.maximumSettlingGap + 1)
        }
    }

    @Test("a malformed backlog is a typed failure here too")
    func malformedBacklogFails() {
        let sequencer = makeSequencer()

        #expect(throws: SequencingError.nonPositiveDeadline(id: "z6")) {
            try sequencer.leastElapsedHours(
                [Filing(id: "z6", statutoryType: "tax", reviewHours: 1, deadlineHour: -5)],
                settlingGap: 1
            )
        }
    }

    @Test("sequencers are independent and never mutate the backlog they are given")
    func sequencersAreIndependentAndNonMutating() throws {
        let busy = makeSequencer()
        let fresh = makeSequencer()

        var filings = backlog
        let original = filings

        for _ in 0..<5 {
            _ = try busy.selectedFilings(filings)
            _ = try busy.replay(regretBacklog)
            _ = try busy.leastElapsedHours(manyTypes, settlingGap: 2)
        }

        // A second sequencer still reports the documented answers, which is
        // what a selection cached in static storage would break.
        #expect(try fresh.selectedFilings(backlog) == ["f1", "f3", "f2"])
        #expect(try fresh.leastElapsedHours(tiedTypes, settlingGap: 2) == 5)

        // The busy sequencer answers two different backlogs independently.
        #expect(try busy.maximumLodged(regretBacklog) == 3)
        #expect(try busy.maximumLodged(hopeless) == 0)
        #expect(try busy.maximumLodged(regretBacklog) == 3)

        // The caller's backlog is untouched, and a caller emptying its own
        // copy changes nothing about a later call.
        #expect(filings == original)
        filings.removeAll()
        #expect(try fresh.maximumLodged(original) == 3)
    }
}
