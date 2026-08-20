// Problem 29: Rule Grouping Analyzer
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A feature-flag service evaluates policy expressions such as 2 * 3 - 4 * 5.
// The rule language defines no operator precedence and no associativity, which
// is a real correctness hazard rather than a curiosity: the same expression can
// evaluate to different values under different groupings, and the service
// cannot be declared deterministic until someone knows the full set of values
// it might return.
//
// Upstream of that, a rule-tree linter needs to know how many distinct shapes a
// tree of a given number of branching nodes can take, and to list them, so its
// fixture generator can cover every shape rather than the handful somebody
// thought of.
//
// All three parts are the same decomposition: pick the one distinguished thing
// at the top, split what is left into a piece on either side of it, and combine
// the two sides. Only what sits at the split point changes.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let analyzer = RuleGroupingAnalyzer()
try analyzer.shapeCount(nodeCount: 0)  // -> 1
try analyzer.shapeCount(nodeCount: 3)  // -> 5
try analyzer.shapeCount(nodeCount: 5)  // -> 42
try analyzer.shapes(nodeCount: 2)
// -> [.node(left: .empty, right: .node(left: .empty, right: .empty)),
//     .node(left: .node(left: .empty, right: .empty), right: .empty)]
try analyzer.possibleResults([
    .value(2), .multiply, .value(3), .subtract, .value(4), .multiply, .value(5),
])
// -> [-34, -14, -10, 10]
// (five groupings, four distinct values, sorted and deduplicated)
*/
//
// PART 1 - Count distinct rule-tree shapes  (~13 min)
// Report how many distinct shapes a rule tree with nodeCount branching nodes
// can take. One node sits at the top and is consumed by the split; the rest
// divide between the two sides in every possible way, and each way contributes
// the two sides multiplied together. Say what the count for no nodes at all
// should be before you write anything, because reading it as zero collapses
// every later entry to zero and the mistake is invisible until you print the
// sequence.
// A negative size is a typed failure. So is a size whose count would not fit in
// an Int: these numbers grow fast, and an Int overflow in Swift is a trap that
// kills the process rather than a wrong answer, so the guard has to fire before
// the multiply. Declare the supported maximum as a static constant and check
// against it. Thirty-three is a safe ceiling.
//
// PART 2 - Enumerate the shapes  (~15 min)
// Report every distinct shape at that size, building structures where Part 1
// built numbers. It is the same split, so both parts should agree about what a
// shape is - and a test here asserts exactly that, which is worth more than
// either method calling the other.
// Fix the order and document it, because an unspecified order makes this
// unusable as a fixture generator: ascending size of the left side, and within
// a left size, the order the two sides already came out in. Building the sizes
// ascending means both sides of any split are ready before the split needs
// them. Listing is bounded by memory rather than by Int, so this part has its
// own much smaller maximum; twelve is a reasonable one.
//
// PART 3 - Every result an ungrouped expression can produce  (~17 min)
// Report every value the expression can evaluate to, over every grouping,
// sorted ascending with duplicates removed - two groupings agreeing on a value
// is precisely the case a caller wants collapsed.
// Part 2 split a size into a left size and a right size. This splits a token
// range at an operator. It is the same split; only what sits at the split point
// changed, and the memo key changes with it from one number to a pair of
// indices. Memoise on the range, or a modest expression will re-solve the same
// sub-expression thousands of times.
// A well-formed expression alternates value, operator, value, beginning and
// ending with a value; anything else is a typed failure, as is an empty one. A
// grouping whose arithmetic overflows is a typed failure too, for the same
// reason as Part 1: an unchecked multiply here takes the process down.

/// The shape of a rule tree, with the rule data stripped away. Two trees have
/// the same shape when they branch in the same places.
public indirect enum RuleShape: Hashable, Sendable {
    case empty
    case node(left: RuleShape, right: RuleShape)
}

/// One token of a policy expression. A well-formed expression alternates a
/// value, an operator, a value, and so on, beginning and ending with a value.
public enum ExpressionToken: Equatable, Sendable {
    case value(Int)
    case add
    case subtract
    case multiply
}

public enum GroupingError: Error, Equatable, Sendable {
    case negativeNodeCount
    case countOverflow
    case emptyExpression
    case malformedExpression
    case notImplemented
}

public struct RuleGroupingAnalyzer: Sendable {
    /// The largest node count whose shape count still fits in an Int.
    public static let maximumCountableNodeCount = 33

    /// The largest node count worth enumerating.
    public static let maximumEnumerableNodeCount = 12

    public init() {}

    // MARK: Part 1 - Count distinct rule-tree shapes
    public func shapeCount(nodeCount: Int) throws(GroupingError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 2 - Enumerate the shapes
    public func shapes(nodeCount: Int) throws(GroupingError) -> [RuleShape] {
        throw .notImplemented
    }

    // MARK: Part 3 - Every result an ungrouped expression can produce
    public func possibleResults(_ tokens: [ExpressionToken]) throws(GroupingError) -> [Int] {
        throw .notImplemented
    }
}
