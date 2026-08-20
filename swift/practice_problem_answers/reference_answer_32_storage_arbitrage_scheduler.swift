public enum ScheduleError: Error, Equatable, Sendable {
    case negativeCycleCap
    case negativePrice(index: Int)
    case notImplemented
}

public struct ArbitrageScheduler: Sendable {
    public init() {}

    // MARK: Part 1 - One charge and one discharge

    /// The best profit from charging once and discharging once, in that order.
    ///
    /// One pass, carrying the cheapest interval seen so far. Every interval asks
    /// one question: if I discharge here, having charged at the cheapest price I
    /// have already seen, what do I make? The answer is the best of those.
    ///
    /// This is also the largest contiguous run of the interval-to-interval price
    /// differences, which is worth noticing out loud: it is the same fold under
    /// a different name.
    public func bestProfitSingleCycle(prices: [Int]) throws(ScheduleError) -> Int {
        try validate(prices: prices)
        guard let first = prices.first else { return 0 }

        var cheapestSoFar = first
        var best = 0
        for price in prices.dropFirst() {
            best = max(best, price - cheapestSoFar)
            cheapestSoFar = min(cheapestSoFar, price)
        }
        return best
    }

    // MARK: Part 2 - Unlimited cycles

    /// The best profit with no limit on how many times the pack cycles.
    ///
    /// Two states, and naming them is the whole design: at the end of an
    /// interval the pack is either holding a charge or flat. Both are computed
    /// from the previous interval's pair and assigned together, never one from
    /// the other's new value, because updating in place quietly permits charging
    /// and discharging within the same interval.
    ///
    /// The pack starts flat with nothing earned, and charging in the first
    /// interval costs its price.
    public func bestProfitUnlimited(prices: [Int]) throws(ScheduleError) -> Int {
        try validate(prices: prices)
        guard let first = prices.first else { return 0 }

        var holding = -first
        var flat = 0
        for price in prices.dropFirst() {
            let previousHolding = holding
            let previousFlat = flat
            holding = max(previousHolding, previousFlat - price)
            flat = max(previousFlat, previousHolding + price)
        }
        return flat
    }

    // MARK: Part 3 - A hard cycle cap

    /// The best profit when the warranty allows at most `cycleCap` full cycles.
    ///
    /// The same two states, one copy of each per cycle count. Entry t of the
    /// holding row is the best the pack can be worth while holding, having
    /// opened at most t cycles; entry t of the flat row is the same while flat,
    /// having closed at most t.
    ///
    /// A cycle needs two intervals, one to charge and one to discharge, so once
    /// the cap is at least half the horizon it cannot bind any more. Detecting
    /// that and handing the work to the unlimited scheduler is what keeps an
    /// absurd cap from allocating an absurd array, and it is a call into a part
    /// that is already written rather than a special case of this one.
    public func bestProfit(prices: [Int], cycleCap: Int) throws(ScheduleError) -> Int {
        guard cycleCap >= 0 else { throw .negativeCycleCap }
        try validate(prices: prices)
        guard !prices.isEmpty, cycleCap > 0 else { return 0 }
        guard 2 * cycleCap < prices.count else { return try bestProfitUnlimited(prices: prices) }

        var holding = Array(repeating: Self.unreachableProfit, count: cycleCap + 1)
        var flat = Array(repeating: 0, count: cycleCap + 1)
        for price in prices {
            for cycles in 1...cycleCap {
                holding[cycles] = max(holding[cycles], flat[cycles - 1] - price)
                flat[cycles] = max(flat[cycles], holding[cycles] + price)
            }
        }
        return flat[cycleCap]
    }

    // MARK: Part 4 - A settling interval after each discharge

    /// The best profit when the pack needs one settling interval after every
    /// discharge before it may charge again.
    ///
    /// The two-state machine cannot express this, because "may I charge now"
    /// depends on whether the previous interval was a discharge and neither
    /// state records that. So the machine gains a state rather than the code
    /// gaining a special case: discharged-this-interval is now its own state,
    /// and charging is reachable only from flat.
    ///
    /// The answer is the better of the two states that leave the pack empty,
    /// since a plan that ends holding a charge has paid for energy it never sold.
    public func bestProfitWithSettling(prices: [Int]) throws(ScheduleError) -> Int {
        try validate(prices: prices)
        guard let first = prices.first else { return 0 }

        var state = MachineState(holding: -first, settling: 0, flat: 0)
        for price in prices.dropFirst() {
            let previous = state
            state = MachineState(
                holding: max(previous.holding, previous.flat - price),
                settling: previous.holding + price,
                flat: max(previous.flat, previous.settling)
            )
        }
        return max(state.flat, state.settling)
    }

    // MARK: Shared machinery

    /// A profit no plan can reach, used to seed a state the pack cannot be in
    /// yet. Half of the smallest Int rather than the smallest Int, so that
    /// adding a price to it stays a number instead of trapping.
    private static let unreachableProfit = Int.min / 2

    /// The three states of the pack at the end of an interval. Written out as a
    /// type because the state machine is what this problem is about, and naming
    /// the states is most of the work of getting the transitions right.
    private struct MachineState {
        /// Holding a charge bought at some earlier interval.
        var holding: Int
        /// Discharged during this interval, so the next one is the settling one.
        var settling: Int
        /// Empty and free to charge.
        var flat: Int
    }

    /// A price curve has no negative prices. A caller that sends one has a
    /// broken feed rather than an arbitrage opportunity, and the index is
    /// reported because that is what makes the feed debuggable.
    private func validate(prices: [Int]) throws(ScheduleError) {
        for (index, price) in prices.enumerated() where price < 0 {
            throw .negativePrice(index: index)
        }
    }
}
