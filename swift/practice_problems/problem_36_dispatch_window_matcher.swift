// Problem 36: Dispatch Window Matcher
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A dispatch system holds availability windows per resource: a driver's legal
// hours, a vehicle's maintenance-free windows, a dock's booking slots. Each
// resource's windows arrive already sorted and internally non-overlapping,
// which is what the upstream rostering system guarantees. A job needs a span
// during which every resource it requires is simultaneously free.
//
// Windows are half-open, measured in minutes since the planning epoch: a window
// that ends where another begins describes no shared instant. Every part walks
// one cursor per list, which is what makes this family's invariant read
// differently here. There is no band closing in from the ends and no write
// cursor lagging a read cursor over one array. Instead, after each step, every
// answer involving a window already passed has been emitted, and the rule that
// keeps that true is the whole problem.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let matcher = DispatchMatcher()
let driver  = [Window(8, 12), Window(14, 18)]
let vehicle = [Window(9, 10), Window(11, 16), Window(17, 20)]
let dock    = [Window(9, 15)]

try matcher.overlaps(driver, vehicle).map(\.window)
// -> [Window(9, 10), Window(11, 12), Window(14, 16), Window(17, 18)]

try matcher.commonAvailability(of: [driver, vehicle, dock])
// -> [Window(9, 10), Window(11, 12), Window(14, 15)]

try matcher.coalescedUnion(driver, vehicle)          // -> [Window(8, 20)]
try matcher.gaps(in: [Window(8, 20)], within: Window(8, 22))
// -> [Window(20, 22)]
*/
//
// PART 1 - Intersect two sorted window lists  (~16 min)
// Report every span during which both resources are free, each tagged with the
// index in each list that contributed it.
// One cursor per list. The move rule is the line candidates get wrong: advance
// the list whose current window ENDS first, because that window can have no
// further intersections, while the other one still might. Comparing starts
// instead still terminates and still produces plausible output, which is what
// makes it worth deciding deliberately rather than by reflex.
// The second trap is the empty intersection. With half-open windows an overlap
// is real only when its low bound is strictly below its high bound; emitting a
// zero-length overlap where two windows merely touch inflates every count that
// reads this result.
// A window that is empty or inverted is a fault, and so is a list that arrives
// out of order or with two windows overlapping each other. Each is a typed
// failure, and the last two name the index that broke the precondition.
//
// PART 2 - Common availability across k resources  (~13 min)
// Report the spans during which every resource in a roster is free.
// Fold the pairwise intersection across the roster rather than generalising the
// sweep to k cursors. The intersection of two sorted, disjoint lists is itself
// sorted and disjoint, and that is exactly what makes the fold legal; say so
// before you write it, because it is the reason a k-cursor rewrite is not
// needed. Mapping the overlaps back to plain windows between folds is the only
// glue this needs.
// A roster of one resource returns that resource's own windows, validated. An
// empty roster is a typed failure rather than an empty answer: no resource is a
// different question from no availability, and answering it with an empty list
// hides a caller's bug.
//
// PART 3 - Coalesced union and its gaps  (~16 min)
// Report every span during which at least one of the two resources is free,
// with touching and overlapping spans coalesced into one, and separately report
// what a coalesced list leaves uncovered inside a horizon.
// The same two cursors, now taking whichever window starts first rather than
// intersecting them. Coalesce on touch as well as on overlap: two windows that
// meet at an instant describe one continuous span of availability, and leaving
// them apart makes the union report a boundary that does not exist.
// The gaps method expects an already-coalesced list, which is why the
// coalescing lives here rather than being assumed: the gaps of a list that
// still holds two windows describing one span are not defined. Windows outside
// the horizon are clipped to it, and a horizon that is itself empty or
// inverted is a fault.
// This part does not call Part 1, and it is not meant to. What ties them
// together is an identity worth checking by hand on any pair of lists: the
// total duration of both inputs equals the total duration of their union plus
// the total duration of their intersection. Every window either lies in exactly
// one input, and is counted once on each side, or lies in both, and is counted
// twice on the left, once in the union and once in the intersection. An
// implementation that emits zero-length overlaps or drops a touching merge
// breaks it immediately.

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
    public func overlaps(_ left: [Window], _ right: [Window]) throws(WindowError) -> [Overlap] {
        throw .notImplemented
    }

    // MARK: Part 2 - Common availability across k resources
    public func commonAvailability(of lists: [[Window]]) throws(WindowError) -> [Window] {
        throw .notImplemented
    }

    // MARK: Part 3 - Coalesced union and its gaps
    public func coalescedUnion(_ left: [Window], _ right: [Window]) throws(WindowError) -> [Window] {
        throw .notImplemented
    }

    public func gaps(in windows: [Window], within horizon: Window) throws(WindowError) -> [Window] {
        throw .notImplemented
    }
}
