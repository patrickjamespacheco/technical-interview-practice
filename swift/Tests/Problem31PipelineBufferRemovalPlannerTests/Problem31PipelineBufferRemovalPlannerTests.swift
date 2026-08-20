import Testing
@testable import Problem31PipelineBufferRemovalPlanner

private func chain(_ specs: [(String, Int, String)]) -> [PipelineBuffer] {
    specs.map { PipelineBuffer(id: $0.0, width: $0.1, stageType: $0.2) }
}

/// The worked chain. Widths three, one, five, eight.
private let workedChain = chain([
    ("buf-a", 3, "parse"),
    ("buf-b", 1, "map"),
    ("buf-c", 5, "parse"),
    ("buf-d", 8, "sink"),
])

/// A chain whose best order is not sorted by width in either direction, so a
/// planner that retires the narrowest buffer first reports far too little.
private let nonMonotoneChain = chain([
    ("buf-p", 2, "parse"),
    ("buf-q", 9, "map"),
    ("buf-r", 3, "parse"),
    ("buf-s", 7, "map"),
    ("buf-t", 4, "sink"),
])

/// Every buffer the same stage type and the same width, which makes the run
/// collapse hand-computable.
private let uniformChain = chain([
    ("u-1", 5, "parse"),
    ("u-2", 5, "parse"),
    ("u-3", 5, "parse"),
    ("u-4", 5, "parse"),
])

/// Two wide parse buffers with a narrow map buffer between them. Retiring each
/// where it stands is worth far less than clearing the map buffer first so the
/// two parse buffers collapse as one run.
private let deferralChain = chain([
    ("d-1", 10, "parse"),
    ("d-2", 1, "map"),
    ("d-3", 10, "parse"),
])

/// No stage type repeats, so no run can ever be longer than one buffer.
private let distinctTypeChain = chain([
    ("x-1", 4, "parse"),
    ("x-2", 7, "map"),
    ("x-3", 2, "sink"),
])

/// Every chain short enough for the permutation baseline to reach.
private let shortChains: [[PipelineBuffer]] = [
    workedChain,
    nonMonotoneChain,
    uniformChain,
    deferralChain,
    distinctTypeChain,
    chain([("t-1", 3, "parse"), ("t-2", 4, "map")]),
    chain([("s-1", 7, "parse")]),
    chain([("w-1", 6, "parse"), ("w-2", 2, "map"), ("w-3", 8, "parse"),
           ("w-4", 1, "sink"), ("w-5", 9, "map"), ("w-6", 3, "parse")]),
    chain([("v-1", 1, "parse"), ("v-2", 5, "parse"), ("v-3", 1, "map"),
           ("v-4", 5, "map"), ("v-5", 2, "sink")]),
]

private func makePlanner() -> BufferRemovalPlanner {
    BufferRemovalPlanner()
}

private func longChain(_ length: Int) -> [PipelineBuffer] {
    (0..<length).map {
        PipelineBuffer(id: "long-\($0)", width: 1 + $0 % 5, stageType: "parse")
    }
}

/// Replays a concrete retirement order and adds up what it actually saves,
/// with a sentinel width of one standing in at each end of the chain.
private func replay(_ order: [String], over buffers: [PipelineBuffer]) -> Int? {
    var remaining = buffers
    var total = 0
    for id in order {
        guard let position = remaining.firstIndex(where: { $0.id == id }) else { return nil }
        let leftWidth = position > 0 ? remaining[position - 1].width : 1
        let rightWidth = position < remaining.count - 1 ? remaining[position + 1].width : 1
        total += leftWidth * remaining[position].width * rightWidth
        remaining.remove(at: position)
    }
    return remaining.isEmpty ? total : nil
}

/// An exhaustive search over the run-collapse objective, written out here so the
/// quartic planner is checked against something that cannot share its bugs. At
/// every step it removes any contiguous group of buffers of one stage type and
/// takes the square of the group size scaled by the width of the buffer the
/// group is reconciled at, which is its rightmost member.
private func exhaustiveRunCollapse(_ buffers: [(width: Int, stageType: String)]) -> Int {
    if buffers.isEmpty { return 0 }
    var best = 0
    for start in buffers.indices {
        var end = start
        while end < buffers.count && buffers[end].stageType == buffers[start].stageType {
            let size = end - start + 1
            var rest = buffers
            rest.removeSubrange(start...end)
            best = max(best, size * size * buffers[end].width + exhaustiveRunCollapse(rest))
            end += 1
        }
    }
    return best
}

@Suite("Part 1 - Exhaustive saving for a short chain")
struct RemovalPart1Tests {
    @Test("an empty chain saves nothing")
    func emptyChain() throws {
        let planner = makePlanner()
        #expect(try planner.bestSavingExhaustive([]) == 0)
    }

    @Test("a single buffer saves its own width, both neighbours being the chain ends")
    func singleBuffer() throws {
        let planner = makePlanner()
        #expect(try planner.bestSavingExhaustive(chain([("only", 7, "parse")])) == 7)
    }

    @Test("two buffers are hand-computable and the order matters")
    func twoBuffers() throws {
        let planner = makePlanner()
        // Retire the three first: one times three times four is twelve, then the
        // eight is alone and saves four. Retiring the four first saves fifteen.
        #expect(try planner.bestSavingExhaustive(chain([("t-1", 3, "parse"), ("t-2", 4, "map")])) == 16)
    }

    @Test("the worked chain saves one hundred and sixty-seven")
    func workedChainBaseline() throws {
        let planner = makePlanner()
        #expect(try planner.bestSavingExhaustive(workedChain) == 167)
    }

    @Test("a chain one longer than the baseline supports is refused")
    func exhaustiveCeiling() {
        let planner = makePlanner()
        let overLength = BufferRemovalPlanner.maximumExhaustiveChainLength + 1
        #expect(throws: RemovalError.chainTooLong(overLength)) {
            try planner.bestSavingExhaustive(longChain(overLength))
        }
    }

    @Test("a width of zero or less is a typed failure naming the buffer")
    func nonPositiveWidthFails() {
        let planner = makePlanner()
        #expect(throws: RemovalError.nonPositiveWidth("buf-zero")) {
            try planner.bestSavingExhaustive(chain([("buf-ok", 2, "parse"), ("buf-zero", 0, "map")]))
        }
    }

    @Test("a width beyond the documented maximum is refused rather than overflowed")
    func widthCeiling() {
        let planner = makePlanner()
        let tooWide = BufferRemovalPlanner.maximumBufferWidth + 1
        #expect(throws: RemovalError.widthTooLarge("buf-wide")) {
            try planner.bestSavingExhaustive(chain([("buf-wide", tooWide, "parse")]))
        }
    }

    @Test("two buffers with the same identifier are a typed failure")
    func duplicateIDFails() {
        let planner = makePlanner()
        #expect(throws: RemovalError.duplicateBufferID("buf-same")) {
            try planner.bestSavingExhaustive(chain([("buf-same", 2, "parse"), ("buf-same", 3, "map")]))
        }
    }
}

@Suite("Part 2 - Best saving by interval decomposition")
struct RemovalPart2Tests {
    @Test("the interval planner agrees with the exhaustive baseline on every short chain")
    func agreesWithBaseline() throws {
        let planner = makePlanner()
        for fixture in shortChains {
            #expect(try planner.bestSaving(fixture) == planner.bestSavingExhaustive(fixture))
        }
    }

    @Test("the worked chain saves one hundred and sixty-seven")
    func workedChainValue() throws {
        let planner = makePlanner()
        // A table filled row by row rather than by increasing interval length
        // reads entries it has not written yet and reports sixty-three here.
        #expect(try planner.bestSaving(workedChain) == 167)
    }

    @Test("the non-monotone chain saves five hundred and twenty-five")
    func nonMonotoneValue() throws {
        let planner = makePlanner()
        // Retiring the narrowest buffer first reaches three hundred and seven,
        // and a row-major fill reaches one hundred and thirteen.
        #expect(try planner.bestSaving(nonMonotoneChain) == 525)
    }

    @Test("an empty chain and a single buffer need no decomposition")
    func degenerateChains() throws {
        let planner = makePlanner()
        #expect(try planner.bestSaving([]) == 0)
        #expect(try planner.bestSaving(chain([("only", 7, "parse")])) == 7)
    }

    @Test("a chain longer than the planner supports is refused")
    func plannableCeiling() {
        let planner = makePlanner()
        let overLength = BufferRemovalPlanner.maximumPlannableChainLength + 1
        #expect(throws: RemovalError.chainTooLong(overLength)) {
            try planner.bestSaving(longChain(overLength))
        }
    }

    @Test("a chain at the documented maximum is planned rather than refused")
    func atPlannableCeiling() throws {
        let planner = makePlanner()
        let saving = try planner.bestSaving(longChain(BufferRemovalPlanner.maximumPlannableChainLength))
        #expect(saving > 0)
    }
}

@Suite("Part 3 - Report the retirement order")
struct RemovalPart3Tests {
    @Test("the worked chain's order is the documented one")
    func workedOrder() throws {
        let planner = makePlanner()
        let order = try planner.retirementOrder(workedChain)
        try #require(order.count == workedChain.count)
        #expect(order == ["buf-b", "buf-c", "buf-a", "buf-d"])
    }

    @Test("the order retires every buffer exactly once")
    func orderIsAPermutation() throws {
        let planner = makePlanner()
        for fixture in shortChains {
            let order = try planner.retirementOrder(fixture)
            #expect(order.count == fixture.count)
            #expect(Set(order) == Set(fixture.map(\.id)))
        }
    }

    @Test("replaying the reported order reproduces the reported saving")
    func replayReproducesTheSaving() throws {
        let planner = makePlanner()
        for fixture in shortChains {
            let order = try planner.retirementOrder(fixture)
            let replayed = replay(order, over: fixture)
            #expect(replayed == (try planner.bestSaving(fixture)))
        }
    }

    @Test("the best order is not sorted by width in either direction")
    func orderIsNotMonotone() throws {
        let planner = makePlanner()
        let order = try planner.retirementOrder(nonMonotoneChain)
        try #require(order.count == 5)
        let widths = order.compactMap { id in nonMonotoneChain.first { $0.id == id }?.width }
        try #require(widths.count == 5)
        #expect(widths != widths.sorted())
        #expect(widths != widths.sorted(by: >))
        #expect(replay(order, over: nonMonotoneChain) == 525)
    }

    @Test("an empty chain has nothing to retire")
    func emptyOrder() throws {
        let planner = makePlanner()
        #expect(try planner.retirementOrder([]).isEmpty)
    }

    @Test("a chain longer than the planner supports is refused")
    func orderCeiling() {
        let planner = makePlanner()
        let overLength = BufferRemovalPlanner.maximumPlannableChainLength + 1
        #expect(throws: RemovalError.chainTooLong(overLength)) {
            try planner.retirementOrder(longChain(overLength))
        }
    }
}

@Suite("Part 4 - Collapse runs of one stage type")
struct RemovalPart4Tests {
    @Test("the quartic planner agrees with an exhaustive search on every short chain")
    func agreesWithExhaustiveSearch() throws {
        let planner = makePlanner()
        for fixture in shortChains where fixture.count <= 6 {
            let expected = exhaustiveRunCollapse(fixture.map { ($0.width, $0.stageType) })
            #expect(try planner.bestSavingWithRunCollapse(fixture) == expected)
        }
    }

    @Test("a chain of one stage type collapses as a single run")
    func wholeChainIsOneRun() throws {
        let planner = makePlanner()
        // Four buffers retired together save four squared, scaled by the width
        // of the buffer the run is reconciled at.
        #expect(try planner.bestSavingWithRunCollapse(uniformChain) == 80)
    }

    @Test("a chain with no repeated stage type saves the sum of its widths")
    func noRunsToCollapse() throws {
        let planner = makePlanner()
        // Every run has length one, so every buffer saves one squared times its
        // own width and nothing can be grouped.
        #expect(try planner.bestSavingWithRunCollapse(distinctTypeChain) == 13)
        #expect(distinctTypeChain.reduce(0) { $0 + $1.width } == 13)
    }

    @Test("deferring a buffer to join a later run of its own type strictly wins")
    func deferralBeatsCollapsingInPlace() throws {
        let planner = makePlanner()
        // Retiring each buffer where it stands saves ten, one and ten. Clearing
        // the map buffer first lets the two parse buffers retire as one run of
        // two, which is four times a width of ten.
        #expect(try planner.bestSavingWithRunCollapse(deferralChain) == 41)
        #expect(deferralChain.reduce(0) { $0 + $1.width } == 21)
    }

    @Test("the worked chain collapses to twenty-nine")
    func workedChainCollapse() throws {
        let planner = makePlanner()
        #expect(try planner.bestSavingWithRunCollapse(workedChain) == 29)
    }

    @Test("an empty chain and a single buffer need no run")
    func degenerateChains() throws {
        let planner = makePlanner()
        #expect(try planner.bestSavingWithRunCollapse([]) == 0)
        #expect(try planner.bestSavingWithRunCollapse(chain([("only", 7, "parse")])) == 7)
    }

    @Test("a chain longer than the planner supports is refused")
    func collapseCeiling() {
        let planner = makePlanner()
        let overLength = BufferRemovalPlanner.maximumPlannableChainLength + 1
        #expect(throws: RemovalError.chainTooLong(overLength)) {
            try planner.bestSavingWithRunCollapse(longChain(overLength))
        }
    }

    @Test("a chain at the documented maximum is planned without trapping")
    func atCollapseCeiling() throws {
        let planner = makePlanner()
        let saving = try planner.bestSavingWithRunCollapse(
            longChain(BufferRemovalPlanner.maximumPlannableChainLength)
        )
        #expect(saving > 0)
    }

    @Test("planners are independent and never mutate the chain they are given")
    func plannersAreIndependentAndNonMutating() throws {
        let busy = makePlanner()
        let fresh = makePlanner()

        var subject = workedChain
        let original = subject

        for _ in 0..<3 {
            _ = try busy.bestSaving(nonMonotoneChain)
            _ = try busy.retirementOrder(nonMonotoneChain)
            _ = try busy.bestSavingWithRunCollapse(uniformChain)
            _ = try busy.bestSavingExhaustive(subject)
        }

        // A second planner still reports the documented answers, which is what a
        // table cached in static storage would break.
        #expect(try fresh.bestSaving(workedChain) == 167)
        #expect(try fresh.retirementOrder(workedChain) == ["buf-b", "buf-c", "buf-a", "buf-d"])
        #expect(try fresh.bestSavingWithRunCollapse(workedChain) == 29)
        #expect(try busy.bestSaving(uniformChain) == fresh.bestSaving(uniformChain))

        // The caller's chain is untouched, and a caller mutating its own copy
        // changes nothing about a later call.
        #expect(subject == original)
        subject.removeLast()
        #expect(try fresh.bestSaving(original) == 167)
    }
}
