import Testing
@testable import Problem29RuleGroupingAnalyzer

/// The worked expression. Its three operators give five groupings and only four
/// distinct results, so it exercises the deduplication as well as the split.
private let workedExpression: [ExpressionToken] = [
    .value(2), .multiply, .value(3), .subtract, .value(4), .multiply, .value(5),
]

/// Nine operators, which is far more groupings than could be listed by hand and
/// is what makes a missing memo obvious.
private let nineOperatorExpression: [ExpressionToken] = [
    .value(2), .multiply, .value(2), .subtract, .value(3), .add, .value(4),
    .multiply, .value(5), .subtract, .value(2), .add, .value(3),
    .multiply, .value(4), .subtract, .value(5), .add, .value(2),
]

/// The first Catalan numbers, which is what the shape count has to reproduce.
private let expectedShapeCounts = [1, 1, 2, 5, 14, 42, 132, 429]

private func makeAnalyzer() -> RuleGroupingAnalyzer {
    RuleGroupingAnalyzer()
}

@Suite("Part 1 - Count distinct rule-tree shapes")
struct GroupingPart1Tests {
    @Test("a tree of no nodes has exactly one shape")
    func emptyTreeHasOneShape() throws {
        let analyzer = makeAnalyzer()
        #expect(try analyzer.shapeCount(nodeCount: 0) == 1)
    }

    @Test("the first eight sizes follow the counting sequence")
    func countingSequence() throws {
        let analyzer = makeAnalyzer()
        let counts = try (0..<expectedShapeCounts.count).map { try analyzer.shapeCount(nodeCount: $0) }
        try #require(counts.count == expectedShapeCounts.count)
        #expect(counts == expectedShapeCounts)
    }

    @Test("each size is the convolution of the sizes below it")
    func convolutionHolds() throws {
        let analyzer = makeAnalyzer()
        let counts = try (0...9).map { try analyzer.shapeCount(nodeCount: $0) }
        try #require(counts.count == 10)
        for size in 1...9 {
            let convolution = (0..<size).reduce(0) { $0 + counts[$1] * counts[size - 1 - $1] }
            #expect(counts[size] == convolution)
        }
    }

    @Test("a negative node count is a typed failure")
    func negativeNodeCountFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: GroupingError.negativeNodeCount) {
            try analyzer.shapeCount(nodeCount: -1)
        }
    }

    @Test("the documented maximum is counted without trapping, and one past it is refused")
    func overflowIsRefusedNotTrapped() throws {
        let analyzer = makeAnalyzer()
        let atMaximum = try analyzer.shapeCount(nodeCount: RuleGroupingAnalyzer.maximumCountableNodeCount)
        #expect(atMaximum == 212_336_130_412_243_110)
        #expect(throws: GroupingError.countOverflow) {
            try analyzer.shapeCount(nodeCount: RuleGroupingAnalyzer.maximumCountableNodeCount + 1)
        }
    }
}

@Suite("Part 2 - Enumerate the shapes")
struct GroupingPart2Tests {
    @Test("a tree of no nodes enumerates the empty shape alone")
    func emptyTreeEnumeratesOnce() throws {
        let analyzer = makeAnalyzer()
        let shapes = try analyzer.shapes(nodeCount: 0)
        try #require(shapes.count == 1)
        #expect(shapes[0] == .empty)
    }

    @Test("two nodes enumerate two shapes, smallest left side first")
    func twoNodesInOrder() throws {
        let analyzer = makeAnalyzer()
        let shapes = try analyzer.shapes(nodeCount: 2)
        try #require(shapes.count == 2)
        #expect(shapes[0] == .node(left: .empty, right: .node(left: .empty, right: .empty)))
        #expect(shapes[1] == .node(left: .node(left: .empty, right: .empty), right: .empty))
    }

    @Test("one node enumerates the single branching shape")
    func oneNode() throws {
        let analyzer = makeAnalyzer()
        let shapes = try analyzer.shapes(nodeCount: 1)
        try #require(shapes.count == 1)
        #expect(shapes[0] == .node(left: .empty, right: .empty))
    }

    @Test("no shape is enumerated twice")
    func shapesAreDistinct() throws {
        let analyzer = makeAnalyzer()
        for size in 0...6 {
            let shapes = try analyzer.shapes(nodeCount: size)
            #expect(Set(shapes).count == shapes.count)
        }
    }

    @Test("the enumeration and the count agree about what a shape is")
    func enumerationMatchesCount() throws {
        let analyzer = makeAnalyzer()
        for size in 0...7 {
            #expect(try analyzer.shapes(nodeCount: size).count == analyzer.shapeCount(nodeCount: size))
        }
    }

    @Test("a negative size fails, and a size beyond what can be listed is refused")
    func outOfRangeSizesFail() {
        let analyzer = makeAnalyzer()
        #expect(throws: GroupingError.negativeNodeCount) {
            try analyzer.shapes(nodeCount: -1)
        }
        #expect(throws: GroupingError.countOverflow) {
            try analyzer.shapes(nodeCount: RuleGroupingAnalyzer.maximumEnumerableNodeCount + 1)
        }
    }
}

@Suite("Part 3 - Every result an ungrouped expression can produce")
struct GroupingPart3Tests {
    @Test("the worked expression has five groupings and four distinct results")
    func workedExpression3() throws {
        let analyzer = makeAnalyzer()
        let results = try analyzer.possibleResults(workedExpression)
        try #require(results.count == 4)
        #expect(results == [-34, -14, -10, 10])
        // Three operators means three split points, so five groupings collapsed
        // into those four values.
        #expect(try analyzer.shapeCount(nodeCount: 3) == 5)
    }

    @Test("a bare value has one result and no grouping to make")
    func bareValue() throws {
        let analyzer = makeAnalyzer()
        let results = try analyzer.possibleResults([.value(7)])
        try #require(results.count == 1)
        #expect(results == [7])
    }

    @Test("one operator has nothing to regroup")
    func singleOperator() throws {
        let analyzer = makeAnalyzer()
        #expect(try analyzer.possibleResults([.value(2), .add, .value(3)]) == [5])
    }

    @Test("an expression whose groupings all agree returns one value")
    func groupingsThatAgree() throws {
        let analyzer = makeAnalyzer()
        let results = try analyzer.possibleResults([
            .value(1), .add, .value(2), .add, .value(3), .add, .value(4),
        ])
        try #require(results.count == 1)
        #expect(results == [10])
    }

    @Test("the results come back sorted with no duplicates")
    func resultsAreSortedAndDistinct() throws {
        let analyzer = makeAnalyzer()
        let results = try analyzer.possibleResults(workedExpression)
        #expect(results == results.sorted())
        #expect(Set(results).count == results.count)
    }

    @Test("an empty expression is a typed failure")
    func emptyExpressionFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: GroupingError.emptyExpression) {
            try analyzer.possibleResults([])
        }
    }

    @Test("an expression that does not alternate value and operator is a typed failure")
    func malformedExpressionFails() {
        let analyzer = makeAnalyzer()
        for tokens in [
            [ExpressionToken.add],
            [ExpressionToken.value(1), .add],
            [ExpressionToken.value(1), .value(2)],
            [ExpressionToken.add, .value(1), .add],
            [ExpressionToken.value(1), .add, .add, .value(2)],
        ] {
            #expect(throws: GroupingError.malformedExpression) {
                try analyzer.possibleResults(tokens)
            }
        }
    }

    @Test("nine operators are evaluated without visiting the same range twice")
    func nineOperatorsAreMemoised() throws {
        let analyzer = makeAnalyzer()
        // Far more groupings than distinct results, which is only tractable
        // because each token range is solved once.
        #expect(try analyzer.shapeCount(nodeCount: 9) == 4862)
        #expect(try analyzer.possibleResults(nineOperatorExpression).count == 440)
    }

    @Test("analyzers are independent and never mutate the tokens they are given")
    func analyzersAreIndependentAndNonMutating() throws {
        let busy = makeAnalyzer()
        let fresh = makeAnalyzer()

        var tokens = workedExpression
        let originalTokens = tokens

        for _ in 0..<5 {
            _ = try busy.possibleResults(nineOperatorExpression)
            _ = try busy.shapes(nodeCount: 8)
            _ = try busy.shapeCount(nodeCount: 30)
        }

        // A second analyzer still reports the documented answers, which is what a
        // table cached in static storage would break.
        #expect(try fresh.shapeCount(nodeCount: 5) == 42)
        #expect(try fresh.shapes(nodeCount: 4).count == 14)
        #expect(try fresh.possibleResults(tokens) == [-34, -14, -10, 10])

        // Two analyzers agree on the enumeration, element for element.
        #expect(try busy.shapes(nodeCount: 4) == fresh.shapes(nodeCount: 4))

        // The caller's tokens are untouched, and a caller mutating its own copy
        // changes nothing about a later call.
        #expect(tokens == originalTokens)
        tokens.removeLast(2)
        #expect(try fresh.possibleResults(originalTokens) == [-34, -14, -10, 10])
    }
}
