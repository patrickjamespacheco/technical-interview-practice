// Problem 32: Storage Arbitrage Scheduler
// Swift 6, macOS 14+ | Staff | approximately 45 minutes
//
// A grid-connected battery buys energy at the interval price and sells it back
// later. The pack holds exactly one charge at a time, so it must discharge
// before it can charge again. Warranty terms cap how many full cycles it may
// run over the scheduling horizon. And after a discharge the pack needs one
// settling interval before it may charge again.
//
// Every part is the same idea: at the end of each interval the pack is in one
// of a small number of states, and each state's best value comes from the
// previous interval's states. What changes between the parts is how wide that
// state is. Say what your states are, out loud, before writing any transition -
// naming them is most of the work, and every bug in this problem is a state
// that was needed and not named.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let scheduler = ArbitrageScheduler()
let prices = [7, 1, 5, 3, 6, 4]
try scheduler.bestProfitSingleCycle(prices: prices)            // -> 5
try scheduler.bestProfitUnlimited(prices: prices)              // -> 7
try scheduler.bestProfit(prices: prices, cycleCap: 1)          // -> 5
try scheduler.bestProfit(prices: prices, cycleCap: 2)          // -> 7
try scheduler.bestProfitWithSettling(prices: [1, 2, 3, 0, 2])  // -> 3
*/
//
// PART 1 - One charge and one discharge  (~9 min)
// Report the best profit from charging once and discharging once, in that
// order, in a single pass. Carry the cheapest interval seen so far and ask each
// interval what it would make if the pack discharged there.
// Subtracting the smallest price from the largest is wrong whenever the
// cheapest interval comes after the dearest, and a fixture exists to catch it.
// Notice, and say, that this is the largest contiguous run of the
// interval-to-interval price differences. If you have written that fold before,
// you have already written this.
// A negative price is a broken feed rather than an opportunity: it is a typed
// failure, and it names the interval.
//
// PART 2 - Unlimited cycles  (~11 min)
// Report the best profit with no limit on cycles. Two states now: at the end of
// an interval the pack is either holding a charge or flat.
// Compute both from the previous interval's pair and assign them together.
// Updating one from the other's new value quietly permits charging and
// discharging in the same interval; here that happens to cost nothing, and in
// the two parts that follow it is simply wrong, which is why the habit matters
// more than this part's answer does.
// Seeding the holding state at nothing earned claims the pack can hold a charge
// for free.
//
// PART 3 - A hard cycle cap  (~14 min)
// Report the best profit when at most cycleCap full cycles are allowed. The
// same two states, one copy of each per cycle count, so say what entry t of
// each row means before writing the loop.
// Seed the holding row at a value no plan can reach, and choose that value so
// adding a price to it is still a number: the smallest Int is not such a value.
// A cycle needs two intervals, so once the cap is at least half the horizon it
// stops binding. Detect that and hand the work to the part you already wrote,
// which is what stops a cap of a billion sizing an array to a billion.
// A negative cap is a typed failure.
//
// PART 4 - A settling interval after each discharge  (~11 min)
// Report the best profit when the pack needs one settling interval after every
// discharge before it may charge again. The two-state machine cannot express
// this: whether the pack may charge now depends on whether the previous
// interval was a discharge, and neither state records that.
// So grow the machine rather than special-casing the code. Discharged-this-
// interval becomes its own state, charging is reachable only from flat, and the
// answer is the better of the two states that leave the pack empty - a plan
// ending with a charge still held has paid for energy it never sold.

public enum ScheduleError: Error, Equatable, Sendable {
    case negativeCycleCap
    case negativePrice(index: Int)
    case notImplemented
}

public struct ArbitrageScheduler: Sendable {
    public init() {}

    // MARK: Part 1 - One charge and one discharge
    public func bestProfitSingleCycle(prices: [Int]) throws(ScheduleError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 2 - Unlimited cycles
    public func bestProfitUnlimited(prices: [Int]) throws(ScheduleError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - A hard cycle cap
    public func bestProfit(prices: [Int], cycleCap: Int) throws(ScheduleError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 4 - A settling interval after each discharge
    public func bestProfitWithSettling(prices: [Int]) throws(ScheduleError) -> Int {
        throw .notImplemented
    }
}
