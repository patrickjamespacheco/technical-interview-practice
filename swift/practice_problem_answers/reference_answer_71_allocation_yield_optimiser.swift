public struct Ratio: Equatable, Comparable, Sendable {
    public let numerator: Int
    public let denominator: Int
    public init(_ numerator: Int, over denominator: Int) {
        precondition(numerator >= 0 && denominator > 0)
        let divisor = Self.gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }
    public static func < (lhs: Ratio, rhs: Ratio) -> Bool { lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator }
    private static func gcd(_ a: Int, _ b: Int) -> Int { var x = a; var y = b; while y != 0 { (x, y) = (y, x % y) }; return max(1, x) }
}

public struct Lot: Equatable, Sendable {
    public let id: String; public let sizeCents: Int; public let yieldCents: Int
    public init(id: String, sizeCents: Int, yieldCents: Int) { self.id = id; self.sizeCents = sizeCents; self.yieldCents = yieldCents }
}
public struct DivisibleAllocation: Equatable, Sendable {
    public let wholeLots: [String]; public let partialLot: (id: String, fraction: Ratio)?; public let totalYield: Ratio
    public init(wholeLots: [String], partialLot: (id: String, fraction: Ratio)?, totalYield: Ratio) { self.wholeLots = wholeLots; self.partialLot = partialLot; self.totalYield = totalYield }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wholeLots == rhs.wholeLots && lhs.partialLot?.id == rhs.partialLot?.id && lhs.partialLot?.fraction == rhs.partialLot?.fraction && lhs.totalYield == rhs.totalYield }
}
public struct WholeAllocation: Equatable, Sendable {
    public let lots: [String]; public let totalYield: Int; public let unusedBudgetCents: Int
    public init(lots: [String], totalYield: Int, unusedBudgetCents: Int) { self.lots = lots; self.totalYield = totalYield; self.unusedBudgetCents = unusedBudgetCents }
}
public enum ExchangeCertificate: Equatable, Sendable { case alreadyOptimal; case improve(reduce: String, increase: String, amountCents: Int, gain: Ratio) }
public enum AllocationError: Error, Equatable, Sendable {
    case nonPositiveSize(id: String); case negativeYield(id: String); case duplicateLotID(String)
    case negativeBudget(Int); case tooManyLotsForExactSearch(Int); case tooManyLots(Int)
    case allocationExceedsBudget(Int); case unknownLotInAllocation(String); case notImplemented
}

public struct YieldOptimiser: Sendable {
    public static let maximumExactSearchLotCount = 20
    public static let maximumLotCount = 100_000
    public init() {}

    public func orderedByYieldRatio(_ lots: [Lot]) throws(AllocationError) -> [Lot] {
        try validate(lots)
        return lots.sorted { left, right in
            let l = left.yieldCents * right.sizeCents, r = right.yieldCents * left.sizeCents
            return l == r ? left.id < right.id : l > r
        }
    }

    public func allocateDivisible(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> DivisibleAllocation {
        guard budgetCents >= 0 else { throw .negativeBudget(budgetCents) }
        let ordered = try orderedByYieldRatio(lots)
        var remaining = budgetCents, whole: [String] = [], partial: (id: String, fraction: Ratio)?
        var numerator = 0, denominator = 1
        for lot in ordered where remaining > 0 {
            if lot.sizeCents <= remaining { whole.append(lot.id); remaining -= lot.sizeCents; numerator += lot.yieldCents * denominator }
            else { partial = (lot.id, Ratio(remaining, over: lot.sizeCents)); numerator = numerator * lot.sizeCents + lot.yieldCents * remaining * denominator; denominator *= lot.sizeCents; break }
        }
        return DivisibleAllocation(wholeLots: whole, partialLot: partial, totalYield: Ratio(numerator, over: denominator))
    }

    public func allocateWholeByRatio(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> WholeAllocation {
        guard budgetCents >= 0 else { throw .negativeBudget(budgetCents) }
        var remaining = budgetCents, picked: [String] = [], total = 0
        for lot in try orderedByYieldRatio(lots) where lot.sizeCents <= remaining { picked.append(lot.id); remaining -= lot.sizeCents; total += lot.yieldCents }
        return WholeAllocation(lots: picked, totalYield: total, unusedBudgetCents: remaining)
    }

    public func allocateWholeExactly(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> WholeAllocation {
        guard budgetCents >= 0 else { throw .negativeBudget(budgetCents) }
        try validate(lots)
        guard lots.count <= Self.maximumExactSearchLotCount else { throw .tooManyLotsForExactSearch(lots.count) }
        var bestYield = -1, bestSize = 0, bestIDs: [String] = []
        for mask in 0..<(1 << lots.count) {
            var size = 0, value = 0, ids: [String] = []
            for index in lots.indices where mask & (1 << index) != 0 { size += lots[index].sizeCents; value += lots[index].yieldCents; ids.append(lots[index].id) }
            ids.sort()
            if size <= budgetCents && (value > bestYield || (value == bestYield && ids.lexicographicallyPrecedes(bestIDs))) { bestYield = value; bestSize = size; bestIDs = ids }
        }
        return WholeAllocation(lots: bestIDs, totalYield: max(0, bestYield), unusedBudgetCents: budgetCents - bestSize)
    }

    public func greedyShortfall(_ lots: [Lot], budgetCents: Int) throws(AllocationError) -> Int {
        try allocateWholeExactly(lots, budgetCents: budgetCents).totalYield - allocateWholeByRatio(lots, budgetCents: budgetCents).totalYield
    }

    public func certificate(for allocation: [String: Int], lots: [Lot], budgetCents: Int) throws(AllocationError) -> ExchangeCertificate {
        guard budgetCents >= 0 else { throw .negativeBudget(budgetCents) }
        let ordered = try orderedByYieldRatio(lots), byID = Dictionary(uniqueKeysWithValues: lots.map { ($0.id, $0) })
        var spent = 0
        for (id, amount) in allocation { guard let lot = byID[id] else { throw .unknownLotInAllocation(id) }; guard amount >= 0 && amount <= lot.sizeCents else { throw .allocationExceedsBudget(amount) }; spent += amount }
        guard spent <= budgetCents else { throw .allocationExceedsBudget(spent) }
        for high in ordered {
            let room = high.sizeCents - (allocation[high.id] ?? 0)
            guard room > 0 else { continue }
            for low in ordered.reversed() where (allocation[low.id] ?? 0) > 0 {
                let highCross = high.yieldCents * low.sizeCents, lowCross = low.yieldCents * high.sizeCents
                guard highCross > lowCross else { continue }
                let amount = min(room, allocation[low.id] ?? 0)
                let gainNumerator = amount * (highCross - lowCross)
                return .improve(reduce: low.id, increase: high.id, amountCents: amount, gain: Ratio(gainNumerator, over: high.sizeCents * low.sizeCents))
            }
        }
        return .alreadyOptimal
    }

    private func validate(_ lots: [Lot]) throws(AllocationError) {
        guard lots.count <= Self.maximumLotCount else { throw .tooManyLots(lots.count) }
        var ids = Set<String>()
        for lot in lots { guard lot.sizeCents > 0 else { throw .nonPositiveSize(id: lot.id) }; guard lot.yieldCents >= 0 else { throw .negativeYield(id: lot.id) }; guard ids.insert(lot.id).inserted else { throw .duplicateLotID(lot.id) } }
    }
}
