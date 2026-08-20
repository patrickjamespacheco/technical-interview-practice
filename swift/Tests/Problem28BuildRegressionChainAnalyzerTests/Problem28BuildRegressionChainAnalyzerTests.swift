import Testing
@testable import Problem28BuildRegressionChainAnalyzer

/// The worked history. Its scores dip twice, so the longest improving chain
/// skips builds rather than running consecutively.
private let workedScores = [10, 9, 12, 11, 14]

/// A history whose tails array is provably not one of its own chains.
private let tailsAreNotAChainScores = [2, 6, 8, 3, 4, 5, 1]

/// A deterministic pseudo-random history, large enough that a quadratic scan and
/// a log-linear one have plenty of room to disagree. The generator is a plain
/// linear congruential step so the fixture is identical on every machine.
private let pseudoRandomScores: [Int] = {
    var state = 20_240_917
    return (0..<200).map { _ in
        state = (state &* 1_103_515_245 &+ 12_345) & 0x7FFF_FFFF
        return state % 500
    }
}()

private func makeAnalyzer() -> ChainAnalyzer {
    ChainAnalyzer()
}

private func makeBuilds(_ scores: [Int], prefix: String) -> [BuildResult] {
    scores.enumerated().map { BuildResult(id: "\(prefix)-\($0.offset)", score: $0.element) }
}

/// Whether `candidate` appears in `values` in order, which is what the tails
/// array is widely and wrongly assumed to satisfy.
private func isSubsequence(_ candidate: [Int], of values: [Int]) -> Bool {
    var cursor = 0
    for value in values where cursor < candidate.count && value == candidate[cursor] {
        cursor += 1
    }
    return cursor == candidate.count
}

@Suite("Part 1 - Longest improving chain length")
struct ChainPart1Tests {
    @Test("the worked history improves three times, skipping two builds")
    func workedHistory() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChainLength(makeBuilds(workedScores, prefix: "worked1")) == 3)
    }

    @Test("a history that only ever improves is entirely one chain")
    func strictlyImprovingHistory() {
        let analyzer = makeAnalyzer()
        let builds = makeBuilds([1, 2, 3, 4, 5, 6], prefix: "rising1")
        #expect(analyzer.longestImprovingChainLength(builds) == builds.count)
    }

    @Test("a history that only ever regresses has no chain longer than one build")
    func strictlyRegressingHistory() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChainLength(makeBuilds([9, 7, 5, 3], prefix: "falling1")) == 1)
    }

    @Test("equal scores do not improve on each other")
    func equalScoresDoNotChain() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChainLength(makeBuilds([4, 4, 4, 4], prefix: "flat1")) == 1)
    }

    @Test("an empty history has no chain at all")
    func emptyHistory() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChainLength([]) == 0)
    }

    @Test("a single build is a chain of one")
    func singleBuild() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChainLength([BuildResult(id: "solo1", score: 3)]) == 1)
    }
}

@Suite("Part 2 - Name the builds in the chain")
struct ChainPart2Tests {
    @Test("the worked history names the three builds that improve")
    func workedChain() throws {
        let analyzer = makeAnalyzer()
        let builds = makeBuilds(workedScores, prefix: "worked2")
        let chain = analyzer.longestImprovingChain(builds)
        try #require(chain.count == 3)
        #expect(chain == ["worked2-0", "worked2-2", "worked2-4"])
    }

    @Test("the reported builds are in input order and their scores strictly improve")
    func chainIsWellFormed() throws {
        let analyzer = makeAnalyzer()
        let builds = makeBuilds(tailsAreNotAChainScores, prefix: "wellformed2")
        let chain = analyzer.longestImprovingChain(builds)
        try #require(chain.count == 4)

        let positions = chain.compactMap { id in builds.firstIndex { $0.id == id } }
        try #require(positions.count == chain.count)
        #expect(positions == positions.sorted())

        let scores = positions.map { builds[$0].score }
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("the chain length agrees with Part 1 on every fixture")
    func chainLengthAgreesWithPart1() {
        let analyzer = makeAnalyzer()
        let fixtures = [
            workedScores,
            tailsAreNotAChainScores,
            [1, 2, 3, 4],
            [4, 3, 2, 1],
            [7, 7, 7],
            [],
            pseudoRandomScores,
        ]
        for (offset, scores) in fixtures.enumerated() {
            let builds = makeBuilds(scores, prefix: "agree2-\(offset)")
            #expect(analyzer.longestImprovingChain(builds).count == analyzer.longestImprovingChainLength(builds))
        }
    }

    @Test("equally good predecessors resolve to the earliest build")
    func earliestPredecessorWinsTies() throws {
        let analyzer = makeAnalyzer()
        // Both of the first two builds can precede the third, and both are the
        // start of a chain of one, so the tie is real.
        let builds = makeBuilds([10, 9, 12], prefix: "tie2")
        let chain = analyzer.longestImprovingChain(builds)
        try #require(chain.count == 2)
        #expect(chain == ["tie2-0", "tie2-2"])
    }

    @Test("an empty history names no builds")
    func emptyHistoryNamesNothing() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.longestImprovingChain([]).isEmpty)
    }
}

@Suite("Part 3 - Log-linear chain length")
struct ChainPart3Tests {
    @Test("the fast length agrees with the quadratic one on every fixture")
    func fastAgreesWithQuadratic() {
        let analyzer = makeAnalyzer()
        let fixtures = [
            workedScores,
            tailsAreNotAChainScores,
            [1, 2, 3, 4, 5],
            [5, 4, 3, 2, 1],
            [6, 6, 6, 6],
            [],
            [42],
            [1, 3, 2, 4, 3, 5],
            [100, 1, 2, 3],
            pseudoRandomScores,
        ]
        for (offset, scores) in fixtures.enumerated() {
            let builds = makeBuilds(scores, prefix: "fast3-\(offset)")
            #expect(analyzer.longestImprovingChainLengthFast(builds) == analyzer.longestImprovingChainLength(builds))
        }
    }

    @Test("the worked history leaves an exact tails array behind")
    func workedTails() throws {
        let analyzer = makeAnalyzer()
        let tails = analyzer.improvingChainTails(makeBuilds(workedScores, prefix: "tails3"))
        try #require(tails.count == 3)
        #expect(tails == [9, 11, 14])
    }

    @Test("the tails array is sorted and as long as the answer")
    func tailsAreSortedAndCounted() {
        let analyzer = makeAnalyzer()
        for (offset, scores) in [workedScores, tailsAreNotAChainScores, pseudoRandomScores].enumerated() {
            let builds = makeBuilds(scores, prefix: "sorted3-\(offset)")
            let tails = analyzer.improvingChainTails(builds)
            #expect(tails == tails.sorted())
            #expect(tails.count == analyzer.longestImprovingChainLengthFast(builds))
        }
    }

    @Test("the tails array is not itself a chain from the history")
    func tailsAreNotAChain() throws {
        let analyzer = makeAnalyzer()
        let builds = makeBuilds(tailsAreNotAChainScores, prefix: "nota3")
        let tails = analyzer.improvingChainTails(builds)
        try #require(tails.count == 4)
        #expect(tails == [1, 3, 4, 5])
        #expect(isSubsequence(tails, of: tailsAreNotAChainScores) == false)
        // The real chain has the same length and different values, which is the
        // whole point of keeping the two methods apart.
        #expect(analyzer.longestImprovingChain(builds) == ["nota3-0", "nota3-3", "nota3-4", "nota3-5"])
    }

    @Test("an empty history leaves an empty tails array")
    func emptyTails() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.improvingChainTails([]).isEmpty)
        #expect(analyzer.longestImprovingChainLengthFast([]) == 0)
    }
}

@Suite("Part 4 - Nested envelopes and peak-shaped trains")
struct ChainPart4Tests {
    @Test("the worked envelopes nest two deep")
    func workedEnvelopes() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.deepestEnvelopeNesting([
            ResourceEnvelope(cpuMillicores: 500, memoryMebibytes: 512),
            ResourceEnvelope(cpuMillicores: 250, memoryMebibytes: 256),
            ResourceEnvelope(cpuMillicores: 500, memoryMebibytes: 256),
        ]) == 2)
    }

    @Test("envelopes sharing a CPU limit never nest inside each other")
    func equalCPULimitsCannotChain() {
        let analyzer = makeAnalyzer()
        // An ascending secondary sort reports three here, which is the signature
        // failure of this part: none of these fits inside another.
        #expect(analyzer.deepestEnvelopeNesting([
            ResourceEnvelope(cpuMillicores: 600, memoryMebibytes: 4),
            ResourceEnvelope(cpuMillicores: 600, memoryMebibytes: 7),
            ResourceEnvelope(cpuMillicores: 600, memoryMebibytes: 9),
        ]) == 1)
    }

    @Test("identical envelopes nest one deep")
    func identicalEnvelopes() {
        let analyzer = makeAnalyzer()
        let envelope = ResourceEnvelope(cpuMillicores: 1000, memoryMebibytes: 2048)
        #expect(analyzer.deepestEnvelopeNesting([envelope, envelope, envelope]) == 1)
    }

    @Test("an envelope smaller in one dimension only does not nest")
    func oneDimensionIsNotEnough() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.deepestEnvelopeNesting([
            ResourceEnvelope(cpuMillicores: 250, memoryMebibytes: 4096),
            ResourceEnvelope(cpuMillicores: 500, memoryMebibytes: 2048),
        ]) == 1)
    }

    @Test("a fully nested run reports its full depth, and no envelopes report none")
    func fullyNestedAndEmpty() {
        let analyzer = makeAnalyzer()
        #expect(analyzer.deepestEnvelopeNesting([
            ResourceEnvelope(cpuMillicores: 400, memoryMebibytes: 1024),
            ResourceEnvelope(cpuMillicores: 100, memoryMebibytes: 256),
            ResourceEnvelope(cpuMillicores: 300, memoryMebibytes: 768),
            ResourceEnvelope(cpuMillicores: 200, memoryMebibytes: 512),
        ]) == 4)
        #expect(analyzer.deepestEnvelopeNesting([]) == 0)
    }

    @Test("the worked history drops two builds to become peak shaped")
    func workedPeakShape() throws {
        let analyzer = makeAnalyzer()
        #expect(try analyzer.minimumRemovalsForPeakShape(makeBuilds(workedScores, prefix: "peak4")) == 2)
    }

    @Test("a history already shaped like a peak drops nothing")
    func alreadyPeakShaped() throws {
        let analyzer = makeAnalyzer()
        #expect(try analyzer.minimumRemovalsForPeakShape(makeBuilds([1, 3, 5, 4, 2], prefix: "already4")) == 0)
    }

    @Test("a history with no descent has no valid peak")
    func noDescentHasNoPeak() {
        let analyzer = makeAnalyzer()
        #expect(throws: ChainError.noValidPeak) {
            try analyzer.minimumRemovalsForPeakShape(makeBuilds([1, 2, 3, 4], prefix: "rising4"))
        }
        #expect(throws: ChainError.noValidPeak) {
            try analyzer.minimumRemovalsForPeakShape(makeBuilds([4, 3, 2, 1], prefix: "falling4"))
        }
        #expect(throws: ChainError.noValidPeak) {
            try analyzer.minimumRemovalsForPeakShape(makeBuilds([5, 5, 5], prefix: "flat4"))
        }
    }

    @Test("an empty history is a typed failure rather than a peak of nothing")
    func emptyHistoryFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: ChainError.emptyHistory) {
            try analyzer.minimumRemovalsForPeakShape([])
        }
    }

    @Test("a peak in the middle keeps the longest rise and the longest fall around it")
    func peakInTheMiddle() throws {
        let analyzer = makeAnalyzer()
        // Rising to 9 at the centre and falling away, with one build on each side
        // that has to go.
        #expect(try analyzer.minimumRemovalsForPeakShape(makeBuilds([2, 1, 4, 9, 3, 8, 1], prefix: "middle4")) == 2)
    }

    @Test("analyzers are independent and never mutate the history they are given")
    func analyzersAreIndependentAndNonMutating() throws {
        let busy = makeAnalyzer()
        let fresh = makeAnalyzer()

        var builds = makeBuilds(workedScores, prefix: "iso4")
        let originalBuilds = builds
        var envelopes = [
            ResourceEnvelope(cpuMillicores: 500, memoryMebibytes: 512),
            ResourceEnvelope(cpuMillicores: 250, memoryMebibytes: 256),
            ResourceEnvelope(cpuMillicores: 500, memoryMebibytes: 256),
        ]
        let originalEnvelopes = envelopes

        for _ in 0..<20 {
            _ = busy.longestImprovingChain(builds)
            _ = busy.improvingChainTails(makeBuilds(pseudoRandomScores, prefix: "iso4-busy"))
            _ = busy.deepestEnvelopeNesting(envelopes)
            _ = try busy.minimumRemovalsForPeakShape(builds)
        }

        // A second analyzer still reports the documented answers, which is what a
        // table cached in static storage would break.
        #expect(fresh.longestImprovingChainLength(builds) == 3)
        #expect(fresh.longestImprovingChain(builds) == ["iso4-0", "iso4-2", "iso4-4"])
        #expect(fresh.improvingChainTails(builds) == [9, 11, 14])
        #expect(fresh.deepestEnvelopeNesting(envelopes) == 2)
        #expect(try fresh.minimumRemovalsForPeakShape(builds) == 2)

        // The caller's inputs are untouched.
        #expect(builds == originalBuilds)
        #expect(envelopes == originalEnvelopes)
        builds.removeLast()
        envelopes.removeLast()
        #expect(fresh.longestImprovingChainLength(originalBuilds) == 3)
        #expect(fresh.deepestEnvelopeNesting(originalEnvelopes) == 2)
    }
}
