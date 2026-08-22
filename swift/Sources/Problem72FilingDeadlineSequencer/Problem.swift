// Problem 72: Filing Deadline Sequencer
// Swift 6, macOS 14+ | Staff | approximately 45 minutes
//
// A compliance team has a backlog of regulatory filings. Each needs a known
// number of review hours and must be lodged by a statutory deadline, measured
// in hours from the start of the quarter. One reviewer works the backlog, so
// only one filing is in progress at a time and work never pauses. The team
// wants to know how many filings it can actually get lodged on time, which
// ones, and separately how long it takes to clear the whole backlog under a
// rule that has nothing to do with deadlines: two filings of the same statutory
// type cannot be lodged back to back, because the registry needs a settling gap
// between them.
//
// This problem exists to put two different kinds of greedy proof side by side.
// The first three parts are an exchange argument, and the twist is that the
// greedy choice can be taken back: a filing accepted earlier may be dropped
// later, and the reason that is safe is the subtlest claim in the file. The
// last part is a greedy whose correctness comes from a counting bound instead,
// where nothing is ever revoked and the whole answer is an arithmetic
// expression. "Greedy" names both, and they are not the same idea.
//
// You choose the internal data structures; the public interface is the
// contract. Store all mutable state in instance properties initialized by init.
// Never use mutable global or static state. Immutable static constants are
// fine. A MaxHeap is provided below because the standard library has none and
// building one is not this problem's lesson.
//
/*
# Example
let sequencer = FilingSequencer()
let backlog = [
    Filing(id: "f1", statutoryType: "tax",    reviewHours: 100,  deadlineHour: 200),
    Filing(id: "f2", statutoryType: "tax",    reviewHours: 200,  deadlineHour: 1300),
    Filing(id: "f3", statutoryType: "labour", reviewHours: 1000, deadlineHour: 1250),
    Filing(id: "f4", statutoryType: "labour", reviewHours: 2000, deadlineHour: 3200),
]

try sequencer.orderedByDeadline(backlog).map(\.id)   // -> ["f1", "f3", "f2", "f4"]
try sequencer.replay(backlog)
// -> ScheduleTrace(lodged: ["f1", "f2"], missed: ["f3", "f4"], finishHour: 3300)
try sequencer.maximumLodged(backlog)                 // -> 3
try sequencer.selectedFilings(backlog)               // -> ["f1", "f3", "f2"]

try sequencer.leastElapsedHours(
      [Filing(id: "a", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
       Filing(id: "b", statutoryType: "tax", reviewHours: 1, deadlineHour: 99),
       Filing(id: "c", statutoryType: "vat", reviewHours: 1, deadlineHour: 99)],
      settlingGap: 2)                                // -> 4
*/
//
// PART 1 - Replay a proposed order  (~10 min)
// Given a proposed working order, report which filings land on time, which
// miss, and the hour the reviewer finishes.
// The reviewer starts at hour zero and never idles, so each filing finishes at
// the running total of review hours before it plus its own. A filing is lodged
// when that finishing hour is at or before its deadline, and missed otherwise.
// A missed filing still consumes its review hours: the work was done, it was
// simply done too late, and a replay that skips missed filings is not a replay.
// Return the trace rather than a bare verdict. Every later part reads something
// different off it, and a method that answered only "does this order work"
// would force each of them to simulate the backlog again.
// Also report the backlog ordered by statutory deadline, earliest first, with
// ties broken by id so the order is reproducible.
// A filing with a non-positive review count or deadline is a fault, and so is a
// repeated id, a backlog beyond the supported size, or an hour figure beyond
// the supported range. Each is a typed failure naming what broke.
//
// PART 2 - Maximum filings lodged  (~14 min)
// Report the largest number of filings that can be lodged on time, choosing
// both which to work and in what order.
// The reflex is shortest-first, and it is wrong: a short filing with a distant
// deadline can always be deferred, while a long filing with a near one cannot.
// Deadline order is the key, and the argument for it is the point of this part.
// Walk the backlog in deadline order taking everything. When the running clock
// passes the current filing's deadline, do not skip that filing. Drop the
// longest filing taken so far, which may well be one accepted several steps
// ago. State why that is safe before you write it: the count is unchanged,
// because one filing came in and one went out, and the clock is now no higher
// than it was before this filing arrived, so no later choice is ever made
// worse. That is the exchange argument, and it is what separates this from the
// version that skips.
// This part and the next need the same walk, so put it in one private helper
// and let each read what it needs off the result. There must be exactly one
// sequencing routine in this file.
//
// PART 3 - Report the selection  (~9 min)
// Report the ids of the filings that get lodged, in the order the reviewer
// works them.
// Nothing new is computed here; this is the same walk read differently, which
// is why the helper exists. The order is deadline order restricted to the
// filings that survived, because that is the order the reviewer actually works
// them in.
// Check yourself with the first part: replaying this selection must lodge every
// one of them and miss none, and the count must agree with the previous part.
// A selection that looks plausible but does not actually fit is exactly what
// this check catches.
//
// PART 4 - Least elapsed time under a settling gap  (~12 min)
// A different rule and a different objective. Lodging a filing with the
// registry takes one hour whatever its review effort, and two filings of the
// same statutory type must be at least `settlingGap` hours apart. Deadlines do
// not apply. Report the fewest elapsed hours, including any idle, in which the
// whole backlog can be lodged.
// Nothing is revoked here and there is no exchange to argue. The busiest
// statutory type sets a skeleton: lodge it, wait out the gap, lodge it again,
// and every other filing slots into the idle hours that skeleton leaves. That
// gives one arithmetic expression from the largest type count and the number of
// types tied at it.
// The expression is wrong on its own, and that is the trap. When the backlog
// holds many distinct types there is no idle time at all and the answer is
// simply the number of filings, which can exceed what the skeleton predicts.
// The final answer is the larger of the two. A backlog with many types is the
// fixture that separates the two versions.
// A negative settling gap is a caller's bug, and a gap beyond the supported
// range is refused rather than overflowed.

public struct Filing: Equatable, Sendable {
    public let id: String
    public let statutoryType: String
    public let reviewHours: Int
    public let deadlineHour: Int

    public init(id: String, statutoryType: String, reviewHours: Int, deadlineHour: Int) {
        self.id = id
        self.statutoryType = statutoryType
        self.reviewHours = reviewHours
        self.deadlineHour = deadlineHour
    }
}

public struct ScheduleTrace: Equatable, Sendable {
    public let lodged: [String]
    public let missed: [String]
    public let finishHour: Int

    public init(lodged: [String], missed: [String], finishHour: Int) {
        self.lodged = lodged
        self.missed = missed
        self.finishHour = finishHour
    }
}

public enum SequencingError: Error, Equatable, Sendable {
    case nonPositiveReviewHours(id: String)
    case nonPositiveDeadline(id: String)
    case hoursOutOfRange(id: String)
    case duplicateFilingID(String)
    case tooManyFilings(Int)
    case negativeSettlingGap(Int)
    case settlingGapOutOfRange(Int)
    case notImplemented
}

/// A binary max-heap, provided because the standard library has none and
/// building one is not what this problem is about. Use it, or do not; the
/// public interface is what the tests read.
public struct MaxHeap<Element: Comparable>: Sendable where Element: Sendable {
    private var storage: [Element] = []

    public init() {}

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    /// The largest element, without removing it.
    public var maximum: Element? { storage.first }

    public mutating func insert(_ element: Element) {
        storage.append(element)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[parent] < storage[child] else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    public mutating func popMax() -> Element? {
        guard let largest = storage.first else { return nil }
        storage.swapAt(0, storage.count - 1)
        storage.removeLast()

        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var swap = parent
            if left < storage.count, storage[swap] < storage[left] { swap = left }
            if right < storage.count, storage[swap] < storage[right] { swap = right }
            guard swap != parent else { break }
            storage.swapAt(parent, swap)
            parent = swap
        }
        return largest
    }
}

public struct FilingSequencer: Sendable {
    /// The backlog is bounded, and so is any single hour figure, so that the
    /// running clock and the settling-gap arithmetic cannot overflow.
    public static let maximumFilingCount = 100_000
    public static let maximumHour = 1_000_000_000
    public static let maximumSettlingGap = 1_000_000

    public init() {}

    // MARK: Part 1 - Replay a proposed order
    public func replay(_ order: [Filing]) throws(SequencingError) -> ScheduleTrace {
        throw .notImplemented
    }

    public func orderedByDeadline(_ filings: [Filing]) throws(SequencingError) -> [Filing] {
        throw .notImplemented
    }

    // MARK: Part 2 - Maximum filings lodged
    public func maximumLodged(_ filings: [Filing]) throws(SequencingError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - Report the selection
    public func selectedFilings(_ filings: [Filing]) throws(SequencingError) -> [String] {
        throw .notImplemented
    }

    // MARK: Part 4 - Least elapsed time under a settling gap
    public func leastElapsedHours(
        _ filings: [Filing],
        settlingGap: Int
    ) throws(SequencingError) -> Int {
        throw .notImplemented
    }
}
