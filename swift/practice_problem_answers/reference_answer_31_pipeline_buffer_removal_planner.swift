/// One intermediate buffer between two pipeline stages.
///
/// The width is what the scheduler has to reconcile when the buffer is retired,
/// and the stage type is what Part 4's run collapse groups on.
public struct PipelineBuffer: Equatable, Sendable {
    public let id: String
    public let width: Int
    public let stageType: String

    public init(id: String, width: Int, stageType: String) {
        self.id = id
        self.width = width
        self.stageType = stageType
    }
}

public enum RemovalError: Error, Equatable, Sendable {
    case nonPositiveWidth(String)
    case widthTooLarge(String)
    case duplicateBufferID(String)
    case chainTooLong(Int)
    case notImplemented
}

public struct BufferRemovalPlanner: Sendable {
    /// The longest chain the permutation baseline will attempt. Every order of
    /// retirement is tried, so the work grows as the factorial of the length and
    /// nine buffers is already a different order of magnitude from eight.
    public static let maximumExhaustiveChainLength = 8

    /// The longest chain the planners will accept. The run-collapse planner is
    /// quartic in this number, and the ceiling is also what makes the arithmetic
    /// provably safe: see `maximumBufferWidth`.
    public static let maximumPlannableChainLength = 40

    /// The widest buffer accepted. Three widths are multiplied together in a
    /// single term and the terms are summed once per buffer, so this ceiling
    /// keeps the largest reachable total far inside an Int. An Int overflow in
    /// Swift is a trap that ends the process rather than a wrong answer, so the
    /// bound is checked before any arithmetic runs.
    public static let maximumBufferWidth = 1_000

    public init() {}

    // MARK: Part 1 - Exhaustive saving for a short chain

    /// The best total saving, found by trying every order of retirement.
    ///
    /// Deliberately the slow way. It exists so the interval planner in Part 2
    /// has something to be proved equal to, and the suite asserts that equality
    /// on every fixture short enough to reach here. That agreement is the
    /// strongest correctness evidence an interval decomposition can have.
    public func bestSavingExhaustive(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        let widths = try validatedWidths(buffers, limit: Self.maximumExhaustiveChainLength)
        guard !widths.isEmpty else { return 0 }

        var order = Array(0..<widths.count)
        var best = 0
        permute(&order, from: 0) { candidate in
            best = max(best, replaySaving(candidate, widths: widths))
        }
        return best
    }

    // MARK: Part 2 - Best saving by interval decomposition

    /// The best total saving, found by decomposing the chain into intervals.
    ///
    /// A projection of the table `retirementOrder` also walks, so there is one
    /// decomposition in this file and both parts read the same numbers out of it.
    public func bestSaving(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        let widths = try validatedWidths(buffers, limit: Self.maximumPlannableChainLength)
        guard !widths.isEmpty else { return 0 }
        return savingTable(widths).best[0][widths.count + 1]
    }

    // MARK: Part 3 - Report the retirement order

    /// The IDs of the buffers in an order that achieves `bestSaving`.
    ///
    /// The table records, for every interval, which buffer was retired last
    /// inside it. Walking that record emits both sides of an interval before the
    /// buffer that closes it, which is exactly what "retired last" means, and
    /// replaying the result reproduces the saving the table reported.
    public func retirementOrder(_ buffers: [PipelineBuffer]) throws(RemovalError) -> [String] {
        let widths = try validatedWidths(buffers, limit: Self.maximumPlannableChainLength)
        guard !widths.isEmpty else { return [] }

        let table = savingTable(widths)
        var order: [Int] = []
        appendOrder(from: 0, to: widths.count + 1, lastRemoved: table.lastRemoved, into: &order)
        // The table is padded with a sentinel at each end, so a padded index of
        // one is the first real buffer.
        return order.map { buffers[$0 - 1].id }
    }

    // MARK: Part 4 - Collapse runs of one stage type

    /// The best total saving once consecutive buffers of the same stage type may
    /// be retired together, the whole run reconciled once.
    ///
    /// A run of r buffers saves r squared, scaled by the width of the buffer the
    /// scheduler reconciles the run at, which is the rightmost of them.
    ///
    /// Nothing from Part 2 is reused, and that is the lesson rather than an
    /// oversight: the saving now depends on how many same-type buffers were
    /// already folded in from the left, so an interval on its own is no longer
    /// enough state to describe a sub-problem. The state gains a third dimension
    /// and the two-dimensional table cannot express it.
    public func bestSavingWithRunCollapse(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        let widths = try validatedWidths(buffers, limit: Self.maximumPlannableChainLength)
        guard !widths.isEmpty else { return 0 }

        let types = buffers.map(\.stageType)
        // Keyed on the interval and the carried run length, which is the third
        // dimension the interval alone could not carry.
        var memo: [CollapseKey: Int] = [:]
        return collapseSaving(
            from: 0, to: widths.count - 1, carried: 0,
            widths: widths, types: types, memo: &memo
        )
    }

    // MARK: Shared machinery

    /// Checks the chain once, for every part, and hands back the widths in order.
    ///
    /// Every guard fires before any arithmetic. The width ceiling is not
    /// decoration: an unchecked multiply here would trap and take the process
    /// down rather than returning something a caller could inspect.
    private func validatedWidths(
        _ buffers: [PipelineBuffer],
        limit: Int
    ) throws(RemovalError) -> [Int] {
        guard buffers.count <= limit else { throw .chainTooLong(buffers.count) }

        var seen: Set<String> = []
        for buffer in buffers {
            guard buffer.width > 0 else { throw .nonPositiveWidth(buffer.id) }
            guard buffer.width <= Self.maximumBufferWidth else { throw .widthTooLarge(buffer.id) }
            guard seen.insert(buffer.id).inserted else { throw .duplicateBufferID(buffer.id) }
        }
        return buffers.map(\.width)
    }

    /// Every order of retirement, handed one at a time to `body`.
    private func permute(_ order: inout [Int], from start: Int, _ body: ([Int]) -> Void) {
        if start == order.count {
            body(order)
            return
        }
        for position in start..<order.count {
            order.swapAt(start, position)
            permute(&order, from: start + 1, body)
            order.swapAt(start, position)
        }
    }

    /// What one concrete order of retirement actually saves.
    ///
    /// A retired buffer's saving is its own width times the widths of the
    /// buffers still present on either side of it, with a sentinel width of one
    /// standing in at each end of the chain. Shared by the baseline and by the
    /// suite's replay of the reported order.
    private func replaySaving(_ order: [Int], widths: [Int]) -> Int {
        var remaining = Array(0..<widths.count)
        var total = 0
        for index in order {
            guard let position = remaining.firstIndex(of: index) else { continue }
            let leftWidth = position > 0 ? widths[remaining[position - 1]] : 1
            let rightWidth = position < remaining.count - 1 ? widths[remaining[position + 1]] : 1
            total += leftWidth * widths[index] * rightWidth
            remaining.remove(at: position)
        }
        return total
    }

    /// The interval table, plus the record of which buffer closes each interval.
    ///
    /// The widths are padded with a sentinel of one at each end so the two ends
    /// of the chain need no special case at all. An entry spans the buffers
    /// strictly between its two padded bounds, and it asks which of them is
    /// retired **last**: once that buffer is fixed, its neighbours at retirement
    /// time are the interval's own bounds, and the two sides stop interacting.
    ///
    /// Filled by increasing interval length, which is the whole fill order.
    /// A plain row-major sweep reads entries that have not been written yet and
    /// returns a plausible, smaller number rather than failing.
    private func savingTable(_ widths: [Int]) -> (best: [[Int]], lastRemoved: [[Int]]) {
        let padded = [1] + widths + [1]
        let span = padded.count
        var best = Array(repeating: Array(repeating: 0, count: span), count: span)
        var lastRemoved = Array(repeating: Array(repeating: -1, count: span), count: span)

        guard span >= 3 else { return (best, lastRemoved) }
        for length in 2..<span {
            for left in 0...(span - 1 - length) {
                let right = left + length
                for closing in (left + 1)..<right {
                    let candidate = best[left][closing]
                        + padded[left] * padded[closing] * padded[right]
                        + best[closing][right]
                    if candidate > best[left][right] || lastRemoved[left][right] == -1 {
                        best[left][right] = candidate
                        lastRemoved[left][right] = closing
                    }
                }
            }
        }
        return (best, lastRemoved)
    }

    /// Walks the record of closing buffers, emitting both sides of an interval
    /// before the buffer that closes it.
    private func appendOrder(
        from left: Int,
        to right: Int,
        lastRemoved: [[Int]],
        into order: inout [Int]
    ) {
        guard right - left >= 2 else { return }
        let closing = lastRemoved[left][right]
        guard closing >= 0 else { return }
        appendOrder(from: left, to: closing, lastRemoved: lastRemoved, into: &order)
        appendOrder(from: closing, to: right, lastRemoved: lastRemoved, into: &order)
        order.append(closing)
    }

    /// The third dimension, made a type so the memo reads as what it is.
    private struct CollapseKey: Hashable {
        let from: Int
        let to: Int
        let carried: Int
    }

    /// Best saving for the buffers `from...to`, given that `carried` buffers of
    /// the same stage type as the one at `from` are already folded in from the
    /// left and will be retired in the same run. The carried buffers sit to the
    /// left of `from` and share its stage type.
    ///
    /// Two moves, and the second one is the reason this needs its own table:
    /// close the run here, so it saves the square of its length scaled by this
    /// buffer's width; or defer this buffer, clear everything between it and a
    /// later buffer of the same stage type, and let the run grow.
    private func collapseSaving(
        from: Int,
        to: Int,
        carried: Int,
        widths: [Int],
        types: [String],
        memo: inout [CollapseKey: Int]
    ) -> Int {
        guard from <= to else { return 0 }
        let key = CollapseKey(from: from, to: to, carried: carried)
        if let cached = memo[key] { return cached }

        // Close the run at this buffer. Its length is what was carried in plus
        // this one, and the width that scales it is this buffer's, because this
        // is where the scheduler reconciles the run.
        var best = (carried + 1) * (carried + 1) * widths[from]
            + collapseSaving(
                from: from + 1, to: to, carried: 0,
                widths: widths, types: types, memo: &memo
            )

        // Or defer it. Everything strictly between here and the buffer it joins
        // has to go first, which is what makes the two sides independent.
        if from + 1 <= to {
            for later in (from + 1)...to where types[later] == types[from] {
                let deferred = collapseSaving(
                    from: from + 1, to: later - 1, carried: 0,
                    widths: widths, types: types, memo: &memo
                ) + collapseSaving(
                    from: later, to: to, carried: carried + 1,
                    widths: widths, types: types, memo: &memo
                )
                best = max(best, deferred)
            }
        }

        memo[key] = best
        return best
    }
}
