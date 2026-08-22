public struct Window: Equatable, Comparable, Sendable {
    public let start: Int
    public let end: Int

    public init(_ start: Int, _ end: Int) {
        self.start = start
        self.end = end
    }

    /// Windows are half-open, so a window that ends where another begins
    /// contributes nothing to the overlap between them.
    public var duration: Int { end - start }

    public static func < (lhs: Window, rhs: Window) -> Bool {
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }
}

public struct Overlap: Equatable, Sendable {
    public let window: Window
    public let leftIndex: Int
    public let rightIndex: Int

    public init(window: Window, leftIndex: Int, rightIndex: Int) {
        self.window = window
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
    }
}

public enum WindowError: Error, Equatable, Sendable {
    case emptyOrInvertedWindow(start: Int, end: Int)
    case unsortedInput(index: Int)
    case overlappingInput(index: Int)
    case noResources
    case notImplemented
}

public struct DispatchMatcher: Sendable {
    public init() {}

    // MARK: Part 1 - Intersect two sorted window lists

    /// Every span during which both resources are simultaneously free.
    ///
    /// One cursor per list. There is no converging band here and no lagging
    /// write cursor: the two cursors walk two different sequences, so the
    /// invariant has to be restated as "every intersection involving a window
    /// already passed has been emitted".
    ///
    /// The move rule follows from that restatement. The window that ends first
    /// can have no further intersections, because every remaining window in the
    /// other list starts at or after the window the other cursor stands on,
    /// which itself ends later. So the list whose current window ends first is
    /// the one that advances, and nothing is stepped over.
    public func overlaps(_ left: [Window], _ right: [Window]) throws(WindowError) -> [Overlap] {
        try validate(left)
        try validate(right)

        var overlaps: [Overlap] = []
        var i = 0
        var j = 0

        while i < left.count, j < right.count {
            let lo = max(left[i].start, right[j].start)
            let hi = min(left[i].end, right[j].end)

            // Half-open windows only genuinely overlap when lo is strictly
            // below hi. Emitting lo == hi manufactures zero-length overlaps
            // that inflate every downstream count.
            if lo < hi {
                overlaps.append(Overlap(window: Window(lo, hi), leftIndex: i, rightIndex: j))
            }

            // Ends, not starts. Comparing starts still terminates, which is
            // what makes it such a comfortable bug.
            if left[i].end < right[j].end {
                i += 1
            } else {
                j += 1
            }
        }

        return overlaps
    }

    // MARK: Part 2 - Common availability across k resources

    /// The spans during which every listed resource is simultaneously free.
    ///
    /// This folds the pairwise intersection across the resources rather than
    /// generalising the sweep to k cursors: the intersection of sorted disjoint
    /// lists is itself sorted and disjoint, which is exactly what makes the
    /// fold legal and what makes a k-cursor rewrite unnecessary.
    public func commonAvailability(of lists: [[Window]]) throws(WindowError) -> [Window] {
        guard let first = lists.first else { throw .noResources }

        // Every roster is checked before the fold starts. A malformed list is a
        // fault whether or not the fold would have reached it: once the running
        // intersection empties, nothing later can put a span back, and a
        // validation that rode along with the fold would fall silent exactly
        // then.
        for list in lists {
            try validate(list)
        }

        var running = first
        for list in lists.dropFirst() {
            running = try overlaps(running, list).map(\.window)
        }

        return running
    }

    // MARK: Part 3 - Coalesced union and its gaps

    /// Every span during which at least one of the two resources is free, with
    /// touching and overlapping spans coalesced into one.
    ///
    /// The same two cursors, now taking whichever window starts first instead
    /// of intersecting them. Coalescing on touch as well as on overlap is what
    /// makes the result a genuine union: two windows that meet at an instant
    /// describe one continuous span of availability.
    public func coalescedUnion(_ left: [Window], _ right: [Window]) throws(WindowError) -> [Window] {
        try validate(left)
        try validate(right)

        var merged: [Window] = []
        var i = 0
        var j = 0

        while i < left.count || j < right.count {
            let next: Window
            if j == right.count || (i < left.count && left[i] < right[j]) {
                next = left[i]
                i += 1
            } else {
                next = right[j]
                j += 1
            }

            if let last = merged.last, next.start <= last.end {
                merged[merged.count - 1] = Window(last.start, max(last.end, next.end))
            } else {
                merged.append(next)
            }
        }

        return merged
    }

    /// The spans inside the horizon that the given windows do not cover.
    ///
    /// The windows are expected to be coalesced already, which is why the
    /// coalescing lives in this part rather than being assumed by it: gaps of a
    /// list that still holds two windows describing one span are not defined.
    public func gaps(in windows: [Window], within horizon: Window) throws(WindowError) -> [Window] {
        try validate(windows)
        guard horizon.end > horizon.start else {
            throw .emptyOrInvertedWindow(start: horizon.start, end: horizon.end)
        }

        var gaps: [Window] = []
        var cursor = horizon.start

        for window in windows {
            let start = max(window.start, horizon.start)
            let end = min(window.end, horizon.end)
            guard start < end else { continue }

            if start > cursor {
                gaps.append(Window(cursor, start))
            }
            cursor = max(cursor, end)
        }

        if cursor < horizon.end {
            gaps.append(Window(cursor, horizon.end))
        }

        return gaps
    }

    // MARK: Shared validation

    /// The precondition every part rests on: each window is a real span, and
    /// the list is sorted and internally disjoint. All three parts read the
    /// list assuming this, so all three check it.
    private func validate(_ windows: [Window]) throws(WindowError) {
        for (index, window) in windows.enumerated() {
            guard window.end > window.start else {
                throw .emptyOrInvertedWindow(start: window.start, end: window.end)
            }
            guard index > 0 else { continue }
            let previous = windows[index - 1]
            guard window.start >= previous.start else { throw .unsortedInput(index: index) }
            guard window.start >= previous.end else { throw .overlappingInput(index: index) }
        }
    }
}
