import Testing
@testable import Problem25WarehouseGridRoutePlanner

private func makeFreshPlanner() -> RoutePlanner {
    RoutePlanner()
}

/// Builds a grid from a cost matrix where a negative marker means blocked, so a
/// fixture reads as the floor plan it represents.
private func makeGrid(_ costs: [[Int]], blockedMarker: Int = -1) -> [[Aisle]] {
    costs.map { row in
        row.map { $0 == blockedMarker ? Aisle.blocked : Aisle.open(traversalCost: $0) }
    }
}

private func makeOpenGrid(rows: Int, columns: Int, cost: Int = 0) -> [[Aisle]] {
    Array(repeating: Array(repeating: Aisle.open(traversalCost: cost), count: columns), count: rows)
}

// The worked floor plan: a single closed aisle in the middle of a 3x3 grid.
private let workedGrid = makeGrid([
    [1, 3, 1],
    [1, -1, 1],
    [4, 2, 1],
])

private let railMoves: Set<DriveMove> = [.east, .south]
private let freeMoves: Set<DriveMove> = [.east, .south, .southEast]

@Suite("Part 1 - Count monotone routes")
struct RoutePart1Tests {
    @Test("an open square floor counts its monotone routes")
    func openSquareFloor() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.routeCount(grid: makeOpenGrid(rows: 3, columns: 3)) == 6)
        #expect(try planner.routeCount(grid: makeOpenGrid(rows: 3, columns: 7)) == 28)
        #expect(try planner.routeCount(grid: makeOpenGrid(rows: 1, columns: 1)) == 1)
        #expect(try planner.routeCount(grid: makeOpenGrid(rows: 1, columns: 6)) == 1)
    }

    @Test("the worked floor plan leaves two routes")
    func workedFloorPlan() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.routeCount(grid: workedGrid) == 2)
    }

    @Test("a closed aisle in the first row cuts off everything east of it")
    func firstRowBlockPropagates() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [0, -1, 0],
            [0, 0, 0],
            [0, 0, 0],
        ])
        #expect(try planner.routeCount(grid: grid) == 3)
    }

    @Test("a closed aisle in the first column cuts off everything south of it")
    func firstColumnBlockPropagates() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [0, 0, 0],
            [-1, 0, 0],
            [0, 0, 0],
        ])
        #expect(try planner.routeCount(grid: grid) == 3)
    }

    @Test("a closed origin or destination leaves no route at all")
    func closedCornersHaveNoRoutes() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.routeCount(grid: makeGrid([[-1, 0], [0, 0]])) == 0)
        #expect(try planner.routeCount(grid: makeGrid([[0, 0], [0, -1]])) == 0)
    }

    @Test("an empty or ragged floor plan is a typed failure")
    func malformedGridsFail() {
        let planner = makeFreshPlanner()
        #expect(throws: RouteError.emptyGrid) { try planner.routeCount(grid: []) }
        #expect(throws: RouteError.emptyGrid) { try planner.routeCount(grid: [[]]) }
        #expect(throws: RouteError.raggedGrid) {
            try planner.routeCount(grid: [
                [.open(traversalCost: 0), .open(traversalCost: 0)],
                [.open(traversalCost: 0)],
            ])
        }
    }
}

@Suite("Part 2 - Cheapest traversal cost")
struct RoutePart2Tests {
    @Test("the worked floor plan costs seven to cross")
    func workedFloorPlan() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.cheapestCost(grid: workedGrid, moves: railMoves) == 7)
    }

    @Test("the cheaper first move is not always the cheaper route")
    func greedyFirstStepLoses() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [0, 1, 1],
            [2, 99, 99],
            [2, 2, 2],
        ])
        #expect(try planner.cheapestCost(grid: grid, moves: railMoves) == 8)
    }

    @Test("a free chassis beats a rail chassis on a diagonal floor plan")
    func diagonalMoveWins() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [1, 9, 9],
            [9, 1, 9],
            [9, 9, 1],
        ])
        #expect(try planner.cheapestCost(grid: grid, moves: railMoves) == 21)
        #expect(try planner.cheapestCost(grid: grid, moves: freeMoves) == 3)
    }

    @Test("a single cell floor costs its own traversal")
    func singleCellFloor() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.cheapestCost(grid: makeGrid([[5]]), moves: railMoves) == 5)
    }

    @Test("a chassis with no moves is a typed failure")
    func emptyMoveSetFails() {
        let planner = makeFreshPlanner()
        #expect(throws: RouteError.emptyMoveSet) {
            try planner.cheapestCost(grid: workedGrid, moves: [])
        }
    }

    @Test("a negative traversal cost is a typed failure")
    func negativeTraversalCostFails() {
        let planner = makeFreshPlanner()
        let grid: [[Aisle]] = [
            [.open(traversalCost: 1), .open(traversalCost: -2)],
            [.open(traversalCost: 1), .open(traversalCost: 1)],
        ]
        #expect(throws: RouteError.negativeTraversalCost) {
            try planner.cheapestCost(grid: grid, moves: railMoves)
        }
    }

    @Test("a destination walled off from every route is a typed failure")
    func unreachableDestinationFails() {
        let planner = makeFreshPlanner()
        let walled = makeGrid([
            [0, -1],
            [-1, 0],
        ])
        #expect(throws: RouteError.unreachableDestination) {
            try planner.cheapestCost(grid: walled, moves: railMoves)
        }
        #expect(throws: RouteError.unreachableDestination) {
            try planner.cheapestCost(grid: makeGrid([[-1, 0], [0, 0]]), moves: railMoves)
        }
    }

    @Test("a diagonal move can reach a destination the rail chassis cannot")
    func diagonalReachesWalledDestination() throws {
        let planner = makeFreshPlanner()
        let walled = makeGrid([
            [1, -1],
            [-1, 1],
        ])
        #expect(try planner.cheapestCost(grid: walled, moves: freeMoves) == 2)
    }
}

@Suite("Part 3 - Emit the cheapest route")
struct RoutePart3Tests {
    @Test("the worked route runs along the first row and down the last column")
    func workedRoute() throws {
        let planner = makeFreshPlanner()
        let route = try planner.cheapestRoute(grid: workedGrid, moves: railMoves)
        try #require(route.count == 5)
        #expect(route[0] == GridPosition(row: 0, column: 0))
        #expect(route[4] == GridPosition(row: 2, column: 2))
        #expect(route == [
            GridPosition(row: 0, column: 0),
            GridPosition(row: 0, column: 1),
            GridPosition(row: 0, column: 2),
            GridPosition(row: 1, column: 2),
            GridPosition(row: 2, column: 2),
        ])
    }

    @Test("the route's traversal costs add up to the reported cheapest cost")
    func routeCostsAgreeWithPart2() throws {
        let planner = makeFreshPlanner()
        let fixtures: [([[Aisle]], Set<DriveMove>)] = [
            (workedGrid, railMoves),
            (makeGrid([[0, 1, 1], [2, 99, 99], [2, 2, 2]]), railMoves),
            (makeGrid([[1, 9, 9], [9, 1, 9], [9, 9, 1]]), freeMoves),
            (makeOpenGrid(rows: 4, columns: 3, cost: 2), railMoves),
        ]
        for (grid, moves) in fixtures {
            let route = try planner.cheapestRoute(grid: grid, moves: moves)
            try #require(!route.isEmpty)
            let summed = route.reduce(0) { total, position in
                guard case .open(let cost) = grid[position.row][position.column] else { return total }
                return total + cost
            }
            #expect(summed == (try planner.cheapestCost(grid: grid, moves: moves)))
        }
    }

    @Test("every route starts at the origin, ends at the destination, and steps legally over open aisles")
    func routeIsWellFormed() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [1, 9, 9],
            [9, 1, 9],
            [9, 9, 1],
        ])
        let route = try planner.cheapestRoute(grid: grid, moves: freeMoves)
        try #require(route.count == 3)
        #expect(route.first == GridPosition(row: 0, column: 0))
        #expect(route.last == GridPosition(row: 2, column: 2))
        for position in route {
            #expect(grid[position.row][position.column] != Aisle.blocked)
        }
        let steps = zip(route, route.dropFirst()).map { from, to in
            (to.row - from.row, to.column - from.column)
        }
        #expect(steps.allSatisfy { $0 == (0, 1) || $0 == (1, 0) || $0 == (1, 1) })
    }

    @Test("a tie enters each cell by the earliest move in the planner's order")
    func tiesResolveTowardTheEarlierMove() throws {
        let planner = makeFreshPlanner()
        let route = try planner.cheapestRoute(grid: makeOpenGrid(rows: 2, columns: 2), moves: railMoves)
        try #require(route.count == 3)
        #expect(route == [
            GridPosition(row: 0, column: 0),
            GridPosition(row: 1, column: 0),
            GridPosition(row: 1, column: 1),
        ])
    }

    @Test("a single cell floor is a route of one position")
    func singleCellRoute() throws {
        let planner = makeFreshPlanner()
        let route = try planner.cheapestRoute(grid: makeGrid([[5]]), moves: railMoves)
        #expect(route == [GridPosition(row: 0, column: 0)])
    }

    @Test("a walled-off destination is a typed failure rather than a partial route")
    func unreachableDestinationFails() {
        let planner = makeFreshPlanner()
        #expect(throws: RouteError.unreachableDestination) {
            try planner.cheapestRoute(grid: makeGrid([[0, -1], [-1, 0]]), moves: railMoves)
        }
    }
}

@Suite("Part 4 - Largest clear staging square")
struct RoutePart4Tests {
    @Test("the worked floor plan stages nothing larger than one aisle")
    func workedFloorPlan() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.largestClearSquareSide(grid: workedGrid) == 1)
        #expect(try planner.clearSquareCount(grid: workedGrid) == 8)
    }

    @Test("an open square floor is one big staging square")
    func openSquareFloor() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.largestClearSquareSide(grid: makeOpenGrid(rows: 3, columns: 3)) == 3)
        #expect(try planner.clearSquareCount(grid: makeOpenGrid(rows: 3, columns: 3)) == 14)
    }

    @Test("a fully closed floor stages nothing")
    func fullyClosedFloor() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([[-1, -1], [-1, -1]])
        #expect(try planner.largestClearSquareSide(grid: grid) == 0)
        #expect(try planner.clearSquareCount(grid: grid) == 0)
    }

    @Test("one closed corner caps the staging square below the floor's size")
    func closedCornerCapsTheSquare() throws {
        let planner = makeFreshPlanner()
        let grid = makeGrid([
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, -1],
        ])
        #expect(try planner.largestClearSquareSide(grid: grid) == 2)
        #expect(try planner.clearSquareCount(grid: grid) == 11)
    }

    @Test("a wide floor stages a square no larger than its narrow side")
    func narrowFloor() throws {
        let planner = makeFreshPlanner()
        #expect(try planner.largestClearSquareSide(grid: makeOpenGrid(rows: 2, columns: 6)) == 2)
        #expect(try planner.clearSquareCount(grid: makeOpenGrid(rows: 2, columns: 6)) == 17)
    }

    @Test("an empty floor plan is a typed failure")
    func emptyGridFails() {
        let planner = makeFreshPlanner()
        #expect(throws: RouteError.emptyGrid) { try planner.largestClearSquareSide(grid: []) }
        #expect(throws: RouteError.emptyGrid) { try planner.clearSquareCount(grid: []) }
    }

    @Test("planners are stateless: a second planner agrees and the caller's floor plan is untouched")
    func plannersAreIndependent() throws {
        let busy = makeFreshPlanner()
        let fresh = makeFreshPlanner()
        let grid = workedGrid

        for _ in 0..<5 {
            _ = try busy.routeCount(grid: grid)
            _ = try busy.cheapestRoute(grid: grid, moves: railMoves)
            _ = try busy.largestClearSquareSide(grid: makeOpenGrid(rows: 4, columns: 4))
        }

        #expect(try fresh.routeCount(grid: grid) == 2)
        #expect(try fresh.cheapestCost(grid: grid, moves: railMoves) == 7)
        #expect(try fresh.clearSquareCount(grid: grid) == 8)
        #expect(grid == workedGrid)
        #expect(try busy.routeCount(grid: grid) == 2)
    }
}
