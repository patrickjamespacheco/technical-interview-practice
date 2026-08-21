import Testing
@testable import Problem36DispatchWindowMatcher

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// The worked roster: a driver's legal hours, a vehicle's maintenance-free
/// windows, and a dock's booking slots, all in minutes since the epoch.
private let driver = [Window(8, 12), Window(14, 18)]
private let vehicle = [Window(9, 10), Window(11, 16), Window(17, 20)]
private let dock = [Window(9, 15)]

/// Two windows that meet at an instant. Half-open, so they share nothing, but
/// their union is one continuous span.
private let touching = [Window(0, 5), Window(5, 10)]

/// One long window containing two short ones, so every intersection comes from
/// the same left index.
private let outer = [Window(0, 100)]
private let inner = [Window(10, 20), Window(30, 40)]

/// A window that ends before the worked roster begins, so it intersects
/// nothing there.
private let early = [Window(0, 4)]

private let rosters: [[Window]] = [driver, vehicle, dock, touching, outer, inner, early, []]

private func makeMatcher() -> DispatchMatcher {
    DispatchMatcher()
}

private func totalDuration(_ windows: [Window]) -> Int {
    windows.reduce(0) { $0 + $1.duration }
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Intersect two sorted window lists")
struct DispatchMatcherPart1Tests {
    @Test("the worked roster's driver and vehicle share four spans")
    func workedRosterOverlaps() throws {
        let matcher = makeMatcher()
        let found = try matcher.overlaps(driver, vehicle)

        // A sweep that advances on starts rather than ends drops the second of
        // these four and still terminates.
        try #require(found.count == 4)
        #expect(found.map(\.window) == [Window(9, 10), Window(11, 12), Window(14, 16), Window(17, 18)])
    }

    @Test("each overlap names the index in each list that contributed it")
    func overlapsCarryTheirIndices() throws {
        let matcher = makeMatcher()
        let found = try matcher.overlaps(driver, vehicle)

        try #require(found.count == 4)
        #expect(found[0] == Overlap(window: Window(9, 10), leftIndex: 0, rightIndex: 0))
        #expect(found[1] == Overlap(window: Window(11, 12), leftIndex: 0, rightIndex: 1))
        #expect(found[2] == Overlap(window: Window(14, 16), leftIndex: 1, rightIndex: 1))
        #expect(found[3] == Overlap(window: Window(17, 18), leftIndex: 1, rightIndex: 2))
    }

    @Test("one containing window intersects every window inside it")
    func containedWindows() throws {
        let matcher = makeMatcher()
        let found = try matcher.overlaps(outer, inner)

        try #require(found.count == 2)
        #expect(found.map(\.window) == [Window(10, 20), Window(30, 40)])
        #expect(found.allSatisfy { $0.leftIndex == 0 })
    }

    @Test("windows that merely touch do not overlap")
    func touchingWindowsDoNotOverlap() throws {
        let matcher = makeMatcher()
        let found = try matcher.overlaps(touching, [Window(5, 6)])

        // The first window of the pair ends exactly where the probe begins.
        // An implementation that emits an overlap whenever the low bound is at
        // or below the high bound reports a zero-length span here as well.
        try #require(found.count == 1)
        #expect(found[0] == Overlap(window: Window(5, 6), leftIndex: 1, rightIndex: 0))
    }

    @Test("lists that share nothing, and empty lists, produce no overlaps")
    func noOverlaps() throws {
        let matcher = makeMatcher()

        #expect(try matcher.overlaps(driver, early) == [])
        #expect(try matcher.overlaps(driver, []) == [])
        #expect(try matcher.overlaps([], vehicle) == [])
        #expect(try matcher.overlaps([], []) == [])
    }

    @Test("every emitted overlap is real and lies inside both contributing windows")
    func overlapsAreRealAndAttributed() throws {
        let matcher = makeMatcher()
        for left in rosters {
            for right in rosters {
                for overlap in try matcher.overlaps(left, right) {
                    #expect(overlap.window.duration > 0)
                    try #require(left.indices.contains(overlap.leftIndex))
                    try #require(right.indices.contains(overlap.rightIndex))
                    let l = left[overlap.leftIndex]
                    let r = right[overlap.rightIndex]
                    #expect(overlap.window.start == max(l.start, r.start))
                    #expect(overlap.window.end == min(l.end, r.end))
                }
            }
        }
    }

    @Test("the sweep agrees with comparing every pair of windows")
    func sweepAgreesWithEveryPair() throws {
        let matcher = makeMatcher()
        for left in rosters {
            for right in rosters {
                var expected: [Window] = []
                for l in left {
                    for r in right {
                        let lo = max(l.start, r.start)
                        let hi = min(l.end, r.end)
                        if lo < hi { expected.append(Window(lo, hi)) }
                    }
                }
                expected.sort()
                #expect(try matcher.overlaps(left, right).map(\.window) == expected)
            }
        }
    }

    @Test("an empty or inverted window is a typed failure naming its bounds")
    func invalidWindowFails() {
        let matcher = makeMatcher()

        #expect(throws: WindowError.emptyOrInvertedWindow(start: 5, end: 5)) {
            try matcher.overlaps([Window(5, 5)], vehicle)
        }
        #expect(throws: WindowError.emptyOrInvertedWindow(start: 9, end: 3)) {
            try matcher.overlaps(driver, [Window(9, 3)])
        }
    }

    @Test("an out-of-order or self-overlapping list is a typed failure naming the index")
    func malformedListFails() {
        let matcher = makeMatcher()

        #expect(throws: WindowError.unsortedInput(index: 1)) {
            try matcher.overlaps([Window(10, 12), Window(2, 4)], vehicle)
        }
        #expect(throws: WindowError.overlappingInput(index: 2)) {
            try matcher.overlaps(driver, [Window(0, 3), Window(4, 9), Window(8, 11)])
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Common availability across k resources")
struct DispatchMatcherPart2Tests {
    @Test("the worked roster's three resources are free together for three spans")
    func workedRosterCommonAvailability() throws {
        let matcher = makeMatcher()
        let common = try matcher.commonAvailability(of: [driver, vehicle, dock])

        try #require(common.count == 3)
        #expect(common == [Window(9, 10), Window(11, 12), Window(14, 15)])
    }

    @Test("a roster of one resource returns that resource's own windows")
    func singleResourceRoster() throws {
        let matcher = makeMatcher()

        #expect(try matcher.commonAvailability(of: [vehicle]) == vehicle)
        #expect(try matcher.commonAvailability(of: [[]]) == [])
    }

    @Test("one resource free at none of the shared spans empties the answer")
    func oneResourceEmptiesTheRoster() throws {
        let matcher = makeMatcher()

        #expect(try matcher.commonAvailability(of: [driver, vehicle, dock, early]) == [])
        #expect(try matcher.commonAvailability(of: [outer, inner, touching]) == [])
    }

    @Test("the fold agrees with intersecting the roster pairwise by hand")
    func foldAgreesWithPairwiseIntersection() throws {
        let matcher = makeMatcher()
        for first in rosters {
            for second in rosters {
                for third in rosters {
                    let pair = try matcher.overlaps(first, second).map(\.window)
                    let expected = try matcher.overlaps(pair, third).map(\.window)
                    #expect(try matcher.commonAvailability(of: [first, second, third]) == expected)
                }
            }
        }
    }

    @Test("common availability never exceeds any single resource's own availability")
    func commonAvailabilityIsBounded() throws {
        let matcher = makeMatcher()
        for first in rosters {
            for second in rosters {
                let common = try matcher.commonAvailability(of: [first, second])
                #expect(totalDuration(common) <= totalDuration(first))
                #expect(totalDuration(common) <= totalDuration(second))
            }
        }
    }

    @Test("an empty roster is a typed failure rather than an empty answer")
    func emptyRosterFails() {
        let matcher = makeMatcher()

        #expect(throws: WindowError.noResources) {
            try matcher.commonAvailability(of: [])
        }
    }

    @Test("a malformed list is a failure even when an earlier fold already emptied")
    func malformedListLaterInTheRosterStillFails() {
        let matcher = makeMatcher()

        // The running intersection is empty after the second resource, so a
        // validation carried along by the fold would never look at the third.
        #expect(throws: WindowError.unsortedInput(index: 1)) {
            try matcher.commonAvailability(of: [driver, early, [Window(10, 12), Window(2, 4)]])
        }
        #expect(throws: WindowError.emptyOrInvertedWindow(start: 7, end: 7)) {
            try matcher.commonAvailability(of: [driver, early, [Window(7, 7)]])
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Coalesced union and its gaps")
struct DispatchMatcherPart3Tests {
    @Test("the worked roster's driver and vehicle cover one continuous span between them")
    func workedRosterUnion() throws {
        let matcher = makeMatcher()
        let union = try matcher.coalescedUnion(driver, vehicle)

        try #require(union.count == 1)
        #expect(union[0] == Window(8, 20))
    }

    @Test("windows that merely touch coalesce into one span")
    func touchingWindowsCoalesce() throws {
        let matcher = makeMatcher()

        #expect(try matcher.coalescedUnion(touching, []) == [Window(0, 10)])
        #expect(try matcher.coalescedUnion(inner, [Window(20, 30)]) == [Window(10, 40)])
    }

    @Test("spans that share nothing stay apart and stay in order")
    func disjointSpansStayApart() throws {
        let matcher = makeMatcher()

        #expect(try matcher.coalescedUnion(driver, early) == [Window(0, 4), Window(8, 12), Window(14, 18)])
        #expect(try matcher.coalescedUnion([], []) == [])
        #expect(try matcher.coalescedUnion([], inner) == inner)
    }

    @Test("the union is itself sorted and internally disjoint on every roster pair")
    func unionIsWellFormed() throws {
        let matcher = makeMatcher()
        for left in rosters {
            for right in rosters {
                let union = try matcher.coalescedUnion(left, right)
                for index in union.indices where index > 0 {
                    // Strictly after, not merely at or after: touching spans
                    // were supposed to have been coalesced.
                    #expect(union[index].start > union[index - 1].end)
                }
                #expect(union.allSatisfy { $0.duration > 0 })
            }
        }
    }

    @Test("both inputs together cover exactly the union plus the intersection")
    func durationIdentityHolds() throws {
        let matcher = makeMatcher()
        for left in rosters {
            for right in rosters {
                let union = try matcher.coalescedUnion(left, right)
                let shared = try matcher.overlaps(left, right).map(\.window)
                #expect(
                    totalDuration(left) + totalDuration(right)
                        == totalDuration(union) + totalDuration(shared)
                )
            }
        }
    }

    @Test("the gaps of a coalesced span are what the horizon leaves over")
    func gapsOfACoalescedSpan() throws {
        let matcher = makeMatcher()

        #expect(try matcher.gaps(in: [Window(8, 20)], within: Window(8, 22)) == [Window(20, 22)])
        #expect(try matcher.gaps(in: inner, within: Window(0, 50))
            == [Window(0, 10), Window(20, 30), Window(40, 50)])
    }

    @Test("windows are clipped to the horizon rather than reported outside it")
    func gapsClipToTheHorizon() throws {
        let matcher = makeMatcher()

        #expect(try matcher.gaps(in: inner, within: Window(12, 35)) == [Window(20, 30)])
        #expect(try matcher.gaps(in: outer, within: Window(0, 100)) == [])
        #expect(try matcher.gaps(in: outer, within: Window(20, 30)) == [])
    }

    @Test("a horizon covered by nothing is one whole gap")
    func gapsOfNothing() throws {
        let matcher = makeMatcher()

        #expect(try matcher.gaps(in: [], within: Window(3, 9)) == [Window(3, 9)])
        #expect(try matcher.gaps(in: early, within: Window(8, 22)) == [Window(8, 22)])
    }

    @Test("the gaps and the coalesced union partition the horizon exactly")
    func gapsPartitionTheHorizon() throws {
        let matcher = makeMatcher()
        let horizon = Window(0, 120)
        for left in rosters {
            for right in rosters {
                let union = try matcher.coalescedUnion(left, right)
                let gaps = try matcher.gaps(in: union, within: horizon)
                let covered = union.reduce(0) { running, window in
                    running + max(0, min(window.end, horizon.end) - max(window.start, horizon.start))
                }
                #expect(covered + totalDuration(gaps) == horizon.duration)
                #expect(gaps.allSatisfy { $0.duration > 0 })
            }
        }
    }

    @Test("an empty or inverted horizon is a typed failure naming its bounds")
    func invalidHorizonFails() {
        let matcher = makeMatcher()

        #expect(throws: WindowError.emptyOrInvertedWindow(start: 9, end: 9)) {
            try matcher.gaps(in: inner, within: Window(9, 9))
        }
        #expect(throws: WindowError.emptyOrInvertedWindow(start: 40, end: 10)) {
            try matcher.gaps(in: inner, within: Window(40, 10))
        }
    }

    @Test("a malformed list is a typed failure in both of this part's methods")
    func malformedListFails() {
        let matcher = makeMatcher()

        #expect(throws: WindowError.overlappingInput(index: 1)) {
            try matcher.coalescedUnion([Window(0, 9), Window(4, 12)], vehicle)
        }
        #expect(throws: WindowError.unsortedInput(index: 1)) {
            try matcher.gaps(in: [Window(10, 12), Window(2, 4)], within: Window(0, 50))
        }
    }

    @Test("matchers are independent and never mutate the lists they are given")
    func matchersAreIndependentAndNonMutating() throws {
        let busy = makeMatcher()
        let fresh = makeMatcher()

        var roster = driver
        let original = roster

        for _ in 0..<5 {
            _ = try busy.overlaps(roster, vehicle)
            _ = try busy.commonAvailability(of: [outer, inner])
            _ = try busy.coalescedUnion(touching, inner)
            _ = try busy.gaps(in: inner, within: Window(0, 50))
        }

        // A second matcher still reports the documented answers, which is what
        // a result table cached in static storage would break.
        #expect(try fresh.overlaps(driver, vehicle).map(\.window)
            == [Window(9, 10), Window(11, 12), Window(14, 16), Window(17, 18)])
        #expect(try fresh.commonAvailability(of: [driver, vehicle, dock])
            == [Window(9, 10), Window(11, 12), Window(14, 15)])
        #expect(try fresh.coalescedUnion(driver, vehicle) == [Window(8, 20)])

        // The busy matcher answers two different rosters independently.
        #expect(try busy.coalescedUnion(driver, vehicle) == [Window(8, 20)])
        #expect(try busy.coalescedUnion(touching, []) == [Window(0, 10)])
        #expect(try busy.coalescedUnion(driver, vehicle) == [Window(8, 20)])

        // The caller's list is untouched, and a caller emptying its own copy
        // changes nothing about a later call.
        #expect(roster == original)
        roster.removeAll()
        #expect(try fresh.overlaps(original, vehicle).count == 4)
    }
}
