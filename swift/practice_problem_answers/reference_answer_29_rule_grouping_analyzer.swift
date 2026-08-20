/// The shape of a rule tree, with the rule data stripped away. Two trees have
/// the same shape when they branch in the same places.
///
/// Deriving Hashable is the reason this is an indirect enum rather than a class:
/// tests can compare shapes and put them in a set with no equality code at all.
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
    /// The largest node count whose shape count still fits in an Int. Counting
    /// past this would overflow, and an Int overflow in Swift is a trap that
    /// takes the process down rather than a wrong answer, so the guard has to
    /// fire before the multiply rather than after it.
    public static let maximumCountableNodeCount = 33

    /// The largest node count worth enumerating. The shapes are counted by the
    /// same numbers Part 1 produces, so this ceiling is about what fits in
    /// memory, not about what fits in an Int.
    public static let maximumEnumerableNodeCount = 12

    public init() {}

    // MARK: Part 1 - Count distinct rule-tree shapes

    /// How many distinct shapes a rule tree with `nodeCount` internal nodes can
    /// take.
    ///
    /// One node is distinguished - the root - and it is consumed by the split,
    /// which is where the minus one comes from: the remaining nodes divide
    /// between the two sides in every possible way, and each way contributes the
    /// product of the two sides' counts. A tree of no nodes has exactly one
    /// shape, the empty one, and reading that base case as zero collapses every
    /// later entry to nothing.
    public func shapeCount(nodeCount: Int) throws(GroupingError) -> Int {
        guard nodeCount >= 0 else { throw .negativeNodeCount }
        guard nodeCount <= Self.maximumCountableNodeCount else { throw .countOverflow }

        var counts = Array(repeating: 0, count: nodeCount + 1)
        counts[0] = 1
        guard nodeCount >= 1 else { return counts[nodeCount] }
        for size in 1...nodeCount {
            counts[size] = (0..<size).reduce(0) { running, leftSize in
                running + counts[leftSize] * counts[size - 1 - leftSize]
            }
        }
        return counts[nodeCount]
    }

    // MARK: Part 2 - Enumerate the shapes

    /// Every distinct shape a rule tree with `nodeCount` internal nodes can take.
    ///
    /// The same split as Part 1, building structures where Part 1 built numbers.
    /// The order is fixed on purpose so callers and tests can rely on it:
    /// ascending left size, and within a left size the two sides in the order
    /// this method already produced them.
    public func shapes(nodeCount: Int) throws(GroupingError) -> [RuleShape] {
        guard nodeCount >= 0 else { throw .negativeNodeCount }
        guard nodeCount <= Self.maximumEnumerableNodeCount else { throw .countOverflow }

        // Filling ascending means both sides of every split are already built by
        // the time the split needs them, so nothing here has to recurse.
        var built: [[RuleShape]] = [[.empty]]
        guard nodeCount >= 1 else { return built[0] }
        for size in 1...nodeCount {
            var atSize: [RuleShape] = []
            for leftSize in 0..<size {
                for left in built[leftSize] {
                    for right in built[size - 1 - leftSize] {
                        atSize.append(.node(left: left, right: right))
                    }
                }
            }
            built.append(atSize)
        }
        return built[nodeCount]
    }

    // MARK: Part 3 - Every result an ungrouped expression can produce

    /// Every value the expression can evaluate to, over every way of grouping it.
    ///
    /// Part 2 split a size into a left size and a right size. This splits a token
    /// range at an operator. It is the same split; only what sits at the split
    /// point changed, and the memo key changes with it from one number to a pair
    /// of indices.
    ///
    /// The results come back sorted with duplicates removed, because two
    /// different groupings landing on the same value is exactly the case the
    /// caller wants collapsed: what matters is whether the set has more than one
    /// element.
    public func possibleResults(_ tokens: [ExpressionToken]) throws(GroupingError) -> [Int] {
        guard !tokens.isEmpty else { throw .emptyExpression }
        try validateAlternation(tokens)

        var memo: [Range<Int>: [Int]] = [:]
        let results = try resultSet(tokens, 0..<tokens.count, &memo)
        return results.sorted()
    }

    // MARK: Shared machinery

    /// A well-formed expression has a value at every even position, an operator
    /// at every odd one, and therefore an odd length.
    private func validateAlternation(_ tokens: [ExpressionToken]) throws(GroupingError) {
        guard tokens.count % 2 == 1 else { throw .malformedExpression }
        for (position, token) in tokens.enumerated() {
            let isValue: Bool
            switch token {
            case .value: isValue = true
            case .add, .subtract, .multiply: isValue = false
            }
            guard isValue == (position % 2 == 0) else { throw .malformedExpression }
        }
    }

    /// Every distinct value the tokens in `range` can produce, memoised on the
    /// range so each sub-expression is solved once however many groupings reach
    /// it.
    private func resultSet(
        _ tokens: [ExpressionToken],
        _ range: Range<Int>,
        _ memo: inout [Range<Int>: [Int]]
    ) throws(GroupingError) -> Set<Int> {
        if let cached = memo[range] { return Set(cached) }

        // A range of one token is a bare value: there is nothing left to group.
        if range.count == 1, case .value(let number) = tokens[range.lowerBound] {
            memo[range] = [number]
            return [number]
        }

        var results: Set<Int> = []
        for split in stride(from: range.lowerBound + 1, to: range.upperBound, by: 2) {
            let left = try resultSet(tokens, range.lowerBound..<split, &memo)
            let right = try resultSet(tokens, (split + 1)..<range.upperBound, &memo)
            for leftValue in left {
                for rightValue in right {
                    results.insert(try combine(leftValue, tokens[split], rightValue))
                }
            }
        }

        memo[range] = Array(results)
        return results
    }

    /// One operator applied to one pair of values.
    ///
    /// Every arithmetic step is checked rather than written plainly. An Int
    /// overflow traps in Swift, and a grouping that overflows is a caller's
    /// expression the service cannot evaluate, which is a typed failure and not
    /// a reason to bring the process down.
    private func combine(_ left: Int, _ token: ExpressionToken, _ right: Int) throws(GroupingError) -> Int {
        let outcome: (partialValue: Int, overflow: Bool)
        switch token {
        case .add: outcome = left.addingReportingOverflow(right)
        case .subtract: outcome = left.subtractingReportingOverflow(right)
        case .multiply: outcome = left.multipliedReportingOverflow(by: right)
        case .value: throw .malformedExpression
        }
        guard !outcome.overflow else { throw .countOverflow }
        return outcome.partialValue
    }
}
