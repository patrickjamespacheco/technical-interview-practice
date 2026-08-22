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

    /// What a proposed working order actually achieves.
    ///
    /// The trace is deliberately richer than a verdict. Part 2 needs the
    /// finishing hour to notice an overrun, Part 3's answer is checked by
    /// replaying it, and a compliance lead needs the missed list to escalate.
    /// A method returning only whether the order works would force all three
    /// to simulate the backlog again.
    public func replay(_ order: [Filing]) throws(SequencingError) -> ScheduleTrace {
        try validate(order)

        var lodged: [String] = []
        var missed: [String] = []
        var clock = 0

        for filing in order {
            // The work happens either way. A filing lodged late was still
            // reviewed, and pretending otherwise makes every later hour wrong.
            clock += filing.reviewHours
            if clock <= filing.deadlineHour {
                lodged.append(filing.id)
            } else {
                missed.append(filing.id)
            }
        }

        return ScheduleTrace(lodged: lodged, missed: missed, finishHour: clock)
    }

    /// The backlog in statutory deadline order, earliest first, ties by id.
    ///
    /// This is the only sort key in the file. Shortest-first is the reflex and
    /// it is the wrong key: a short filing with a distant deadline can always
    /// be deferred, while a long filing with a near one cannot.
    public func orderedByDeadline(_ filings: [Filing]) throws(SequencingError) -> [Filing] {
        try validate(filings)
        return filings.sorted { left, right in
            left.deadlineHour == right.deadlineHour
                ? left.id < right.id
                : left.deadlineHour < right.deadlineHour
        }
    }

    // MARK: Part 2 - Maximum filings lodged

    /// The largest number of filings that can be lodged on time.
    ///
    /// A projection of the same walk Part 3 reads, so there is one sequencing
    /// routine in the file rather than two that can disagree.
    public func maximumLodged(_ filings: [Filing]) throws(SequencingError) -> Int {
        try sequence(filings).count
    }

    // MARK: Part 3 - Report the selection

    /// The filings that get lodged, in the order the reviewer works them.
    public func selectedFilings(_ filings: [Filing]) throws(SequencingError) -> [String] {
        try sequence(filings).map(\.id)
    }

    // MARK: Part 4 - Least elapsed time under a settling gap

    /// The fewest elapsed hours, idle included, in which the whole backlog can
    /// be lodged when two filings of one statutory type must be `settlingGap`
    /// hours apart.
    ///
    /// A different kind of greedy, and worth naming as such: nothing is
    /// revoked and there is no exchange to argue. The busiest type sets a
    /// skeleton of `maxCount - 1` blocks of `gap + 1` hours, plus one hour for
    /// each type tied at that count. Every other filing fits into the idle
    /// hours the skeleton already contains.
    ///
    /// The skeleton is not the whole answer. With enough distinct types there
    /// is no idle time at all and the schedule is simply as long as the
    /// backlog, which the skeleton underestimates. The answer is the larger of
    /// the two, and that clamp is the whole trap.
    public func leastElapsedHours(
        _ filings: [Filing],
        settlingGap: Int
    ) throws(SequencingError) -> Int {
        try validate(filings)
        guard settlingGap >= 0 else { throw .negativeSettlingGap(settlingGap) }
        guard settlingGap <= Self.maximumSettlingGap else {
            throw .settlingGapOutOfRange(settlingGap)
        }

        var perType: [String: Int] = [:]
        for filing in filings {
            perType[filing.statutoryType, default: 0] += 1
        }
        guard let busiest = perType.values.max() else { return 0 }
        let tiedAtBusiest = perType.values.filter { $0 == busiest }.count

        let skeleton = (busiest - 1) * (settlingGap + 1) + tiedAtBusiest
        return max(filings.count, skeleton)
    }

    // MARK: The one sequencing routine

    /// Deadline order, take everything, and drop the longest filing taken so
    /// far whenever the clock overruns the deadline in hand.
    ///
    /// The exchange argument, which is the reason this is correct: dropping
    /// the longest keeps the count the same, because one filing came in as one
    /// went out, and leaves the clock no higher than it stood before the new
    /// filing arrived. No later decision is ever made worse, so a greedy that
    /// revokes an earlier choice is still safe. Skipping the current filing
    /// instead is a different and worse algorithm: it leaves a longer filing
    /// in place and a higher clock, for the same count.
    private func sequence(_ filings: [Filing]) throws(SequencingError) -> [Filing] {
        let ordered = try orderedByDeadline(filings)

        var taken = MaxHeap<TakenFiling>()
        var clock = 0

        for filing in ordered {
            clock += filing.reviewHours
            taken.insert(TakenFiling(reviewHours: filing.reviewHours, id: filing.id))

            if clock > filing.deadlineHour, let longest = taken.popMax() {
                clock -= longest.reviewHours
            }
        }

        var keptIDs = Set<String>()
        keptIDs.reserveCapacity(taken.count)
        while let survivor = taken.popMax() {
            keptIDs.insert(survivor.id)
        }

        // Deadline order restricted to the survivors, because that is the
        // order the reviewer actually works them in.
        return ordered.filter { keptIDs.contains($0.id) }
    }

    /// A filing currently accepted, ordered by review hours so the heap always
    /// offers the one worth giving back.
    private struct TakenFiling: Comparable, Sendable {
        let reviewHours: Int
        let id: String

        static func < (lhs: TakenFiling, rhs: TakenFiling) -> Bool {
            lhs.reviewHours == rhs.reviewHours ? lhs.id < rhs.id : lhs.reviewHours < rhs.reviewHours
        }
    }

    // MARK: Shared validation

    /// The precondition every part rests on. The hour ceiling is not
    /// decoration: an unguarded running clock over a full backlog is the one
    /// place this file could overflow, and Swift traps on that rather than
    /// returning a wrong number.
    private func validate(_ filings: [Filing]) throws(SequencingError) {
        guard filings.count <= Self.maximumFilingCount else {
            throw .tooManyFilings(filings.count)
        }
        var seen = Set<String>()
        seen.reserveCapacity(filings.count)
        for filing in filings {
            guard filing.reviewHours > 0 else {
                throw .nonPositiveReviewHours(id: filing.id)
            }
            guard filing.deadlineHour > 0 else {
                throw .nonPositiveDeadline(id: filing.id)
            }
            guard filing.reviewHours <= Self.maximumHour,
                  filing.deadlineHour <= Self.maximumHour else {
                throw .hoursOutOfRange(id: filing.id)
            }
            guard seen.insert(filing.id).inserted else {
                throw .duplicateFilingID(filing.id)
            }
        }
    }
}
