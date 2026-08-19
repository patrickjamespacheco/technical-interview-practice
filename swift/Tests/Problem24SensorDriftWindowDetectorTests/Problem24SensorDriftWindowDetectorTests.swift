import Testing
@testable import Problem24SensorDriftWindowDetector

// Module-level fixtures are immutable `let`; Swift's value semantics mean every
// test that passes one to a detector gets its own copy.
private let mixedSeries = [-2, 3, -1, 4, -6, 2]
private let allNegativeSeries = [-8, -3, -5]
private let leadingNegativeSeries = [-5, 4, -1, 3]
private let circularWrapSeries = [5, -3, 5]

private func makeFreshDetector() -> DriftDetector {
    DriftDetector()
}

@Suite("Part 1 - Worst contiguous drift total")
struct DriftPart1Tests {
    @Test("a mixed series reports its worst contiguous total")
    func mixedSeriesTotal() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstTotal(deltas: mixedSeries) == 6)
    }

    @Test("an all-negative series reports its least-bad single interval, never zero")
    func allNegativeSeriesTotal() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstTotal(deltas: allNegativeSeries) == -3)
    }

    @Test("a single interval is a legal window")
    func singleIntervalTotal() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstTotal(deltas: [7]) == 7)
        #expect(try detector.worstTotal(deltas: [-7]) == -7)
    }

    @Test("a leading negative interval does not anchor the window")
    func leadingNegativeTotal() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstTotal(deltas: leadingNegativeSeries) == 6)
    }

    @Test("an empty series is a typed failure")
    func emptySeriesFails() {
        let detector = makeFreshDetector()
        #expect(throws: DriftError.emptySeries) {
            try detector.worstTotal(deltas: [])
        }
    }
}

@Suite("Part 2 - Report the window bounds")
struct DriftPart2Tests {
    @Test("the worst window of a mixed series carries its bounds")
    func mixedSeriesWindow() throws {
        let detector = makeFreshDetector()
        let window = try detector.worstWindow(deltas: mixedSeries)
        #expect(window == DriftWindow(startIndex: 1, endIndex: 3, total: 6))
    }

    @Test("an all-negative series reports the least-bad interval's own bounds")
    func allNegativeWindow() throws {
        let detector = makeFreshDetector()
        let window = try detector.worstWindow(deltas: allNegativeSeries)
        #expect(window == DriftWindow(startIndex: 1, endIndex: 1, total: -3))
    }

    @Test("a leading negative interval is excluded from the reported bounds")
    func leadingNegativeWindow() throws {
        let detector = makeFreshDetector()
        let window = try detector.worstWindow(deltas: leadingNegativeSeries)
        #expect(window == DriftWindow(startIndex: 1, endIndex: 3, total: 6))
    }

    @Test("equal totals resolve to the earliest start")
    func tiesPreferTheEarliestStart() throws {
        let detector = makeFreshDetector()
        let window = try detector.worstWindow(deltas: [0, 5])
        #expect(window == DriftWindow(startIndex: 0, endIndex: 1, total: 5))
    }

    @Test("equal totals from the same start resolve to the shortest window")
    func tiesPreferTheShortestWindow() throws {
        let detector = makeFreshDetector()
        let window = try detector.worstWindow(deltas: [3, 0])
        #expect(window == DriftWindow(startIndex: 0, endIndex: 0, total: 3))
    }

    @Test("the window's total is the total Part 1 reports")
    func windowAgreesWithTotal() throws {
        let detector = makeFreshDetector()
        for series in [mixedSeries, allNegativeSeries, leadingNegativeSeries, circularWrapSeries, [7]] {
            #expect(try detector.worstWindow(deltas: series).total == detector.worstTotal(deltas: series))
        }
    }

    @Test("an empty series is a typed failure")
    func emptySeriesFails() {
        let detector = makeFreshDetector()
        #expect(throws: DriftError.emptySeries) {
            try detector.worstWindow(deltas: [])
        }
    }
}

@Suite("Part 3 - Circular duty cycles")
struct DriftPart3Tests {
    @Test("a wrapping window beats every interior window")
    func wrappingWindowWins() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstCircularTotal(deltas: circularWrapSeries) == 10)
    }

    @Test("an interior window wins when wrapping cannot beat it")
    func interiorWindowWins() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstCircularTotal(deltas: [-1, 5, -1]) == 5)
    }

    @Test("an all-negative cycle reports its least-bad interval, never the empty wrap")
    func allNegativeCycle() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstCircularTotal(deltas: [-3, -2, -5]) == -2)
    }

    @Test("a single interval cycle reports that interval")
    func singleIntervalCycle() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstCircularTotal(deltas: [4]) == 4)
        #expect(try detector.worstCircularTotal(deltas: [-4]) == -4)
    }

    @Test("a cycle whose intervals are all positive wraps to the whole series")
    func allPositiveCycle() throws {
        let detector = makeFreshDetector()
        #expect(try detector.worstCircularTotal(deltas: [2, 3, 4]) == 9)
    }

    @Test("an empty series is a typed failure")
    func emptySeriesFails() {
        let detector = makeFreshDetector()
        #expect(throws: DriftError.emptySeries) {
            try detector.worstCircularTotal(deltas: [])
        }
    }
}

@Suite("Part 4 - Largest drift magnitude in either direction")
struct DriftPart4Tests {
    @Test("a negative stretch outscores every positive one")
    func negativeStretchWins() throws {
        let detector = makeFreshDetector()
        #expect(try detector.largestDriftMagnitude(deltas: [-4, -7, 1]) == 11)
    }

    @Test("magnitude agrees with Part 1 when the positive direction dominates")
    func agreesWithWorstTotal() throws {
        let detector = makeFreshDetector()
        let series = [3, -1, 4]
        #expect(try detector.largestDriftMagnitude(deltas: series) == detector.worstTotal(deltas: series))
    }

    @Test("a symmetric series scores the same in either direction")
    func symmetricSeries() throws {
        let detector = makeFreshDetector()
        #expect(try detector.largestDriftMagnitude(deltas: [4, -4]) == 4)
        #expect(try detector.largestDriftMagnitude(deltas: mixedSeries) == 6)
    }

    @Test("a single negative interval scores its magnitude")
    func singleNegativeInterval() throws {
        let detector = makeFreshDetector()
        #expect(try detector.largestDriftMagnitude(deltas: [-5]) == 5)
    }

    @Test("an empty series is a typed failure")
    func emptySeriesFails() {
        let detector = makeFreshDetector()
        #expect(throws: DriftError.emptySeries) {
            try detector.largestDriftMagnitude(deltas: [])
        }
    }

    @Test("detectors are stateless: a second detector agrees and the caller's series is untouched")
    func detectorsAreIndependent() throws {
        let busy = makeFreshDetector()
        let fresh = makeFreshDetector()
        var series = mixedSeries

        for _ in 0..<5 {
            _ = try busy.worstWindow(deltas: series)
            _ = try busy.worstCircularTotal(deltas: series)
            _ = try busy.largestDriftMagnitude(deltas: series)
        }

        #expect(try fresh.worstWindow(deltas: series) == DriftWindow(startIndex: 1, endIndex: 3, total: 6))
        #expect(try fresh.worstCircularTotal(deltas: series) == 6)
        #expect(series == mixedSeries)

        series.append(9)
        #expect(try fresh.worstTotal(deltas: series) == 11)
        #expect(try busy.worstTotal(deltas: mixedSeries) == 6)
    }
}
