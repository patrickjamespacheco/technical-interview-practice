import Testing
@testable import Problem32StorageArbitrageScheduler

/// The worked price curve. Its cheapest interval comes after its dearest, which
/// is what a scheduler that simply subtracts the minimum from the maximum gets
/// wrong.
private let workedCurve = [7, 1, 5, 3, 6, 4]

/// The settling curve. Selling into the third interval and settling through the
/// fourth leaves nothing to sell in the fifth, so the best plan takes the
/// smaller first trade instead.
private let settlingCurve = [1, 2, 3, 0, 2]

/// A curve with three separate rises, so a cap of one, a cap of two and no cap
/// at all are three different answers.
private let threeRiseCurve = [2, 8, 1, 9, 4, 10, 3]

private let priceCurves: [[Int]] = [
    workedCurve,
    settlingCurve,
    threeRiseCurve,
    [1, 2, 3, 4, 5],
    [9, 7, 5, 3, 1],
    [4, 4, 4, 4],
    [3, 2, 6, 5, 0, 3],
    [5],
    [],
]

private func makeScheduler() -> ArbitrageScheduler {
    ArbitrageScheduler()
}

@Suite("Part 1 - One charge and one discharge")
struct ArbitragePart1Tests {
    @Test("the worked curve makes five on one cycle")
    func workedCurveSingleCycle() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitSingleCycle(prices: workedCurve) == 5)
    }

    @Test("the cheapest and the dearest interval in the wrong order make no trade")
    func cheapestAfterDearest() throws {
        let scheduler = makeScheduler()
        // Charging at one and discharging at five makes four. Subtracting the
        // minimum from the maximum without regard to order would claim six.
        #expect(try scheduler.bestProfitSingleCycle(prices: [7, 1, 5]) == 4)
    }

    @Test("a falling curve is better left alone than traded badly")
    func fallingCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitSingleCycle(prices: [9, 7, 5, 3, 1]) == 0)
    }

    @Test("one interval and no intervals both leave nothing to do")
    func degenerateCurves() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitSingleCycle(prices: [5]) == 0)
        #expect(try scheduler.bestProfitSingleCycle(prices: []) == 0)
    }

    @Test("a flat curve earns nothing")
    func flatCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitSingleCycle(prices: [4, 4, 4, 4]) == 0)
    }

    @Test("a negative price is a typed failure naming the interval")
    func negativePriceFails() {
        let scheduler = makeScheduler()
        #expect(throws: ScheduleError.negativePrice(index: 2)) {
            try scheduler.bestProfitSingleCycle(prices: [4, 5, -1, 6])
        }
    }
}

@Suite("Part 2 - Unlimited cycles")
struct ArbitragePart2Tests {
    @Test("the worked curve makes seven with no limit on cycles")
    func workedCurveUnlimited() throws {
        let scheduler = makeScheduler()
        // One to five and three to six, which is four plus three.
        #expect(try scheduler.bestProfitUnlimited(prices: workedCurve) == 7)
    }

    @Test("a rising curve is one trade however many are allowed")
    func risingCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitUnlimited(prices: [1, 2, 3, 4, 5]) == 4)
    }

    @Test("a falling curve still earns nothing")
    func fallingCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitUnlimited(prices: [9, 7, 5, 3, 1]) == 0)
    }

    @Test("a flat curve earns nothing however many cycles are allowed")
    func flatCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitUnlimited(prices: [4, 4, 4, 4]) == 0)
    }

    @Test("no limit is never worse than one cycle")
    func neverWorseThanOneCycle() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            #expect(
                try scheduler.bestProfitUnlimited(prices: curve)
                    >= scheduler.bestProfitSingleCycle(prices: curve)
            )
        }
    }

    @Test("a negative price is a typed failure naming the interval")
    func negativePriceFails() {
        let scheduler = makeScheduler()
        #expect(throws: ScheduleError.negativePrice(index: 0)) {
            try scheduler.bestProfitUnlimited(prices: [-3, 5])
        }
    }
}

@Suite("Part 3 - A hard cycle cap")
struct ArbitragePart3Tests {
    @Test("a cap of no cycles at all earns nothing")
    func zeroCap() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            #expect(try scheduler.bestProfit(prices: curve, cycleCap: 0) == 0)
        }
    }

    @Test("a cap of one cycle reproduces the single-cycle scheduler on every curve")
    func capOfOneMatchesPartOne() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            #expect(
                try scheduler.bestProfit(prices: curve, cycleCap: 1)
                    == scheduler.bestProfitSingleCycle(prices: curve)
            )
        }
    }

    @Test("a cap that cannot bind reproduces the unlimited scheduler on every curve")
    func looseCapMatchesPartTwo() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            #expect(
                try scheduler.bestProfit(prices: curve, cycleCap: curve.count)
                    == scheduler.bestProfitUnlimited(prices: curve)
            )
        }
    }

    @Test("a cap of two sits strictly between one cycle and no limit")
    func capOfTwoIsStrictlyBetween() throws {
        let scheduler = makeScheduler()
        // Nine on the best single rise, fifteen on the best two, twenty on all
        // three.
        #expect(try scheduler.bestProfitSingleCycle(prices: threeRiseCurve) == 9)
        #expect(try scheduler.bestProfit(prices: threeRiseCurve, cycleCap: 2) == 15)
        #expect(try scheduler.bestProfitUnlimited(prices: threeRiseCurve) == 20)
        #expect(try scheduler.bestProfit(prices: threeRiseCurve, cycleCap: 3) == 20)
    }

    @Test("an absurd cap answers immediately rather than sizing an array to it")
    func absurdCapShortCircuits() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfit(prices: workedCurve, cycleCap: 1_000_000_000) == 7)
        #expect(try scheduler.bestProfit(prices: threeRiseCurve, cycleCap: 1_000_000_000) == 20)
    }

    @Test("raising the cap never lowers the profit")
    func profitIsMonotoneInTheCap() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            for cap in 0..<4 {
                #expect(
                    try scheduler.bestProfit(prices: curve, cycleCap: cap)
                        <= scheduler.bestProfit(prices: curve, cycleCap: cap + 1)
                )
            }
        }
    }

    @Test("a negative cap is a typed failure")
    func negativeCapFails() {
        let scheduler = makeScheduler()
        #expect(throws: ScheduleError.negativeCycleCap) {
            try scheduler.bestProfit(prices: workedCurve, cycleCap: -1)
        }
    }

    @Test("a negative price is a typed failure naming the interval")
    func negativePriceFails() {
        let scheduler = makeScheduler()
        #expect(throws: ScheduleError.negativePrice(index: 3)) {
            try scheduler.bestProfit(prices: [4, 5, 6, -2], cycleCap: 2)
        }
    }
}

@Suite("Part 4 - A settling interval after each discharge")
struct ArbitragePart4Tests {
    @Test("the settling curve makes three, not four")
    func settlingCurveValue() throws {
        let scheduler = makeScheduler()
        // Without settling the pack would take one to three and nought to two
        // for four. Settling occupies the fourth interval, so the better plan is
        // one to two, settle, then nought to two.
        #expect(try scheduler.bestProfitUnlimited(prices: settlingCurve) == 4)
        #expect(try scheduler.bestProfitWithSettling(prices: settlingCurve) == 3)
    }

    @Test("a rising curve is one trade, so settling never binds")
    func risingCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitWithSettling(prices: [1, 2, 3, 4, 5]) == 4)
    }

    @Test("settling strictly reduces what a busy curve can earn")
    func settlingCostsOnABusyCurve() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitUnlimited(prices: threeRiseCurve) == 20)
        #expect(try scheduler.bestProfitWithSettling(prices: threeRiseCurve) == 12)
    }

    @Test("a flat curve and a falling curve earn nothing")
    func nothingToEarn() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitWithSettling(prices: [4, 4, 4, 4]) == 0)
        #expect(try scheduler.bestProfitWithSettling(prices: [9, 7, 5, 3, 1]) == 0)
    }

    @Test("one interval and no intervals leave nothing to do")
    func degenerateCurves() throws {
        let scheduler = makeScheduler()
        #expect(try scheduler.bestProfitWithSettling(prices: [5]) == 0)
        #expect(try scheduler.bestProfitWithSettling(prices: []) == 0)
    }

    @Test("settling is never better than no limit and never worse than one cycle")
    func settlingSitsBetween() throws {
        let scheduler = makeScheduler()
        for curve in priceCurves {
            let settling = try scheduler.bestProfitWithSettling(prices: curve)
            #expect(settling <= (try scheduler.bestProfitUnlimited(prices: curve)))
            #expect(settling >= (try scheduler.bestProfitSingleCycle(prices: curve)))
        }
    }

    @Test("a negative price is a typed failure naming the interval")
    func negativePriceFails() {
        let scheduler = makeScheduler()
        #expect(throws: ScheduleError.negativePrice(index: 1)) {
            try scheduler.bestProfitWithSettling(prices: [4, -5, 6])
        }
    }

    @Test("schedulers are independent and never mutate the curve they are given")
    func schedulersAreIndependentAndNonMutating() throws {
        let busy = makeScheduler()
        let fresh = makeScheduler()

        var curve = workedCurve
        let original = curve

        for _ in 0..<5 {
            _ = try busy.bestProfitUnlimited(prices: threeRiseCurve)
            _ = try busy.bestProfit(prices: threeRiseCurve, cycleCap: 2)
            _ = try busy.bestProfitWithSettling(prices: curve)
        }

        // A second scheduler still reports the documented answers, which is what
        // a table cached in static storage would break.
        #expect(try fresh.bestProfitSingleCycle(prices: workedCurve) == 5)
        #expect(try fresh.bestProfitUnlimited(prices: workedCurve) == 7)
        #expect(try fresh.bestProfitWithSettling(prices: settlingCurve) == 3)

        // Two different caps on one scheduler answer independently, which is
        // what a memo held across calls would break.
        #expect(try busy.bestProfit(prices: threeRiseCurve, cycleCap: 1) == 9)
        #expect(try busy.bestProfit(prices: threeRiseCurve, cycleCap: 2) == 15)
        #expect(try busy.bestProfit(prices: threeRiseCurve, cycleCap: 1) == 9)

        // The caller's curve is untouched, and a caller mutating its own copy
        // changes nothing about a later call.
        #expect(curve == original)
        curve.removeAll()
        #expect(try fresh.bestProfitUnlimited(prices: original) == 7)
    }
}
