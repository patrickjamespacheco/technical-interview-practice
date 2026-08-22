// Problem 71: Allocation Yield Optimiser
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A treasury team allocates a cash budget across lots with known sizes and
// expected yields. Ratio order is safe when lots are divisible and can fail
// when minimum ticket sizes make them all-or-nothing. This problem makes that
// boundary measurable and turns the exchange argument into a returned value.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
/*
# Example
let optimiser = YieldOptimiser()
let lots = [Lot(id: "a", sizeCents: 10, yieldCents: 60),
            Lot(id: "b", sizeCents: 20, yieldCents: 100),
            Lot(id: "c", sizeCents: 30, yieldCents: 120)]
try optimiser.orderedByYieldRatio(lots).map(\.id) // -> ["a", "b", "c"]
try optimiser.greedyShortfall(lots, budgetCents: 50) // -> 60
try optimiser.allocateDivisible(lots, budgetCents: 50).totalYield // -> 240/1
*/
// PART 1 - Ratio ordering  (~9 min)
// Validate the lots and order them by exact yield per cent, ties by id. Compare
// ratios with integer cross-products, never floating point.
//
// PART 2 - Fractional allocation  (~12 min)
// Take whole lots in ratio order, then the affordable fraction of the next.
// Divisibility makes the exchange argument safe: money moved from a lower ratio
// lot to a higher ratio lot always improves yield.
//
// PART 3 - All or nothing, and the shortfall  (~14 min)
// Apply the same rule to whole lots, then find the exact best subset under the
// documented ceiling and report the loss. The ratio proof breaks because a
// partial exchange is forbidden; use exhaustive subset search, not greedy twice.
//
// PART 4 - The exchange certificate  (~10 min)
// For a divisible allocation return either optimality or the concrete amount to
// move from a lower-ratio lot to a higher-ratio one, with its exact gain.

public struct Ratio: Equatable, Comparable, Sendable {
    public let numerator: Int; public let denominator: Int
    public init(_ numerator: Int, over denominator: Int) { precondition(numerator >= 0 && denominator > 0); var a = numerator, b = denominator; while b != 0 { (a, b) = (b, a % b) }; let d = max(1, a); self.numerator = numerator / d; self.denominator = denominator / d }
    public static func < (lhs: Ratio, rhs: Ratio) -> Bool { lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator }
}
public struct Lot: Equatable, Sendable { public let id: String; public let sizeCents: Int; public let yieldCents: Int; public init(id: String, sizeCents: Int, yieldCents: Int) { self.id = id; self.sizeCents = sizeCents; self.yieldCents = yieldCents } }
public struct DivisibleAllocation: Equatable, Sendable {
    public let wholeLots: [String]; public let partialLot: (id: String, fraction: Ratio)?; public let totalYield: Ratio
    public init(wholeLots: [String], partialLot: (id: String, fraction: Ratio)?, totalYield: Ratio) { self.wholeLots = wholeLots; self.partialLot = partialLot; self.totalYield = totalYield }
    public static func == (lhs: Self, rhs: Self) -> Bool { false }
}
public struct WholeAllocation: Equatable, Sendable { public let lots: [String]; public let totalYield: Int; public let unusedBudgetCents: Int; public init(lots: [String], totalYield: Int, unusedBudgetCents: Int) { self.lots = lots; self.totalYield = totalYield; self.unusedBudgetCents = unusedBudgetCents } }
public enum ExchangeCertificate: Equatable, Sendable { case alreadyOptimal; case improve(reduce: String, increase: String, amountCents: Int, gain: Ratio) }
public enum AllocationError: Error, Equatable, Sendable { case nonPositiveSize(id: String); case negativeYield(id: String); case duplicateLotID(String); case negativeBudget(Int); case tooManyLotsForExactSearch(Int); case tooManyLots(Int); case allocationExceedsBudget(Int); case unknownLotInAllocation(String); case notImplemented }
public struct YieldOptimiser: Sendable {
    public static let maximumExactSearchLotCount = 20; public static let maximumLotCount = 100_000
    public init() {}
    public func orderedByYieldRatio(_ lots: [Lot]) throws(AllocationError) -> [Lot] { throw .notImplemented }
    public func allocateDivisible(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> DivisibleAllocation { throw .notImplemented }
    public func allocateWholeByRatio(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> WholeAllocation { throw .notImplemented }
    public func allocateWholeExactly(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> WholeAllocation { throw .notImplemented }
    public func greedyShortfall(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> Int { throw .notImplemented }
    public func certificate(for allocation: [String: Int], lots: [Lot], budgetCents: Int) throws(AllocationError) -> ExchangeCertificate { throw .notImplemented }
}
