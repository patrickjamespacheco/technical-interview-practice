/// One cell of the warehouse floor: either drivable at a known cost, or closed
/// for restocking.
public enum Aisle: Equatable, Sendable {
    case open(traversalCost: Int)
    case blocked
}

public struct GridPosition: Hashable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// The forward moves a chassis can make. A rail chassis has east and south; a
/// free chassis adds southEast. Every move increases the row or the column, so
/// no route can revisit a cell.
public enum DriveMove: Hashable, Sendable, CaseIterable {
    case east
    case south
    case southEast
}

public enum RouteError: Error, Equatable, Sendable {
    case emptyGrid
    case raggedGrid
    case negativeTraversalCost
    case emptyMoveSet
    case unreachableDestination
    case notImplemented
}

public struct RoutePlanner: Sendable {
    /// The order ties are resolved in when a route is reconstructed. It is the
    /// declaration order of DriveMove, stated once so the tie rule is a fact
    /// about the planner rather than an accident of a loop.
    private static let moveOrder: [DriveMove] = [.east, .south, .southEast]

    public init() {}

    // MARK: Part 1 - Count monotone routes

    /// How many east/south routes cross the floor from the north-west corner to
    /// the south-east one.
    ///
    /// One entry counts the routes that end on that cell, so a cell's entry is
    /// the sum of the entries of the cells a picker could have arrived from. A
    /// blocked cell ends no routes and therefore contributes nothing, which is
    /// what propagates a closed aisle along the first row and the first column.
    public func routeCount(grid: [[Aisle]]) throws(RouteError) -> Int {
        try validate(grid)
        let railMoves: Set<DriveMove> = [.east, .south]
        var routes = Array(repeating: Array(repeating: 0, count: grid[0].count), count: grid.count)

        for row in 0..<grid.count {
            for column in 0..<grid[row].count {
                guard case .open = grid[row][column] else { continue }
                if row == 0 && column == 0 {
                    routes[0][0] = 1
                    continue
                }
                let position = GridPosition(row: row, column: column)
                for predecessor in predecessors(of: position, in: grid, moves: railMoves) {
                    routes[row][column] += routes[predecessor.row][predecessor.column]
                }
            }
        }

        return routes[grid.count - 1][grid[0].count - 1]
    }

    // MARK: Part 2 - Cheapest traversal cost

    public func cheapestCost(grid: [[Aisle]], moves: Set<DriveMove>) throws(RouteError) -> Int {
        let costs = try costTable(grid, moves)
        guard let destination = costs[grid.count - 1][grid[0].count - 1] else {
            throw .unreachableDestination
        }
        return destination
    }

    // MARK: Part 3 - Emit the cheapest route

    /// The route is read back out of the same table the cost came from. A cell is
    /// on the cheapest route when its own cost plus a predecessor's cost equals
    /// its entry; ties resolve to the earliest move in the planner's move order.
    public func cheapestRoute(grid: [[Aisle]], moves: Set<DriveMove>) throws(RouteError) -> [GridPosition] {
        let costs = try costTable(grid, moves)
        var position = GridPosition(row: grid.count - 1, column: grid[0].count - 1)
        guard let total = costs[position.row][position.column] else { throw .unreachableDestination }

        var reversedRoute = [position]
        var remaining = total
        while position.row != 0 || position.column != 0 {
            let cost = traversalCost(of: position, in: grid) ?? 0
            let step = predecessors(of: position, in: grid, moves: moves).first { predecessor in
                costs[predecessor.row][predecessor.column].map { $0 + cost == remaining } ?? false
            }
            guard let step else { break }
            reversedRoute.append(step)
            remaining -= cost
            position = step
        }

        return reversedRoute.reversed()
    }

    // MARK: Part 4 - Largest clear staging square

    /// Parts 1 to 3 folded over the cells a route could arrive from. This folds
    /// over a cell's three northern and western neighbours to grow a region, so
    /// an entry now means the side of the largest all-open square whose
    /// south-east corner is that cell. Same grid, same row-major order, a
    /// different meaning for one entry.
    public func largestClearSquareSide(grid: [[Aisle]]) throws(RouteError) -> Int {
        try squareTable(grid).lazy.map { $0.max() ?? 0 }.max() ?? 0
    }

    /// Every entry of that table is also the number of all-open squares whose
    /// south-east corner is that cell, so the count is the same table summed
    /// rather than maximised. The table is the asset; the answer is a fold.
    public func clearSquareCount(grid: [[Aisle]]) throws(RouteError) -> Int {
        try squareTable(grid).reduce(0) { $0 + $1.reduce(0, +) }
    }

    // MARK: Shared machinery

    private func validate(_ grid: [[Aisle]]) throws(RouteError) {
        guard let firstRow = grid.first, !firstRow.isEmpty else { throw .emptyGrid }
        for row in grid where row.count != firstRow.count { throw .raggedGrid }
        for row in grid {
            for aisle in row {
                if case .open(let cost) = aisle, cost < 0 { throw .negativeTraversalCost }
            }
        }
    }

    private func traversalCost(of position: GridPosition, in grid: [[Aisle]]) -> Int? {
        guard case .open(let cost) = grid[position.row][position.column] else { return nil }
        return cost
    }

    /// The cells a picker could have arrived at `position` from, in the planner's
    /// move order. The movement model lives here so Part 1 and Parts 2 and 3
    /// cannot disagree about what a legal step is, even though they fold over
    /// these cells differently.
    private func predecessors(
        of position: GridPosition,
        in grid: [[Aisle]],
        moves: Set<DriveMove>
    ) -> [GridPosition] {
        var found: [GridPosition] = []
        for move in Self.moveOrder where moves.contains(move) {
            let candidate: GridPosition
            switch move {
            case .east: candidate = GridPosition(row: position.row, column: position.column - 1)
            case .south: candidate = GridPosition(row: position.row - 1, column: position.column)
            case .southEast: candidate = GridPosition(row: position.row - 1, column: position.column - 1)
            }
            guard candidate.row >= 0, candidate.column >= 0 else { continue }
            found.append(candidate)
        }
        return found
    }

    /// The cheapest cost of reaching each cell, or nil where no legal route
    /// reaches it. Part 2 reads its corner; Part 3 walks it backwards.
    private func costTable(_ grid: [[Aisle]], _ moves: Set<DriveMove>) throws(RouteError) -> [[Int?]] {
        try validate(grid)
        guard !moves.isEmpty else { throw .emptyMoveSet }

        var costs: [[Int?]] = Array(repeating: Array(repeating: nil, count: grid[0].count), count: grid.count)
        for row in 0..<grid.count {
            for column in 0..<grid[row].count {
                let position = GridPosition(row: row, column: column)
                guard let cost = traversalCost(of: position, in: grid) else { continue }
                if row == 0 && column == 0 {
                    costs[0][0] = cost
                    continue
                }
                let reachable = predecessors(of: position, in: grid, moves: moves).compactMap { costs[$0.row][$0.column] }
                if let best = reachable.min() {
                    costs[row][column] = best + cost
                }
            }
        }
        return costs
    }

    /// The side of the largest all-open square ending at each cell.
    private func squareTable(_ grid: [[Aisle]]) throws(RouteError) -> [[Int]] {
        try validate(grid)
        var sides = Array(repeating: Array(repeating: 0, count: grid[0].count), count: grid.count)
        for row in 0..<grid.count {
            for column in 0..<grid[row].count {
                guard case .open = grid[row][column] else { continue }
                if row == 0 || column == 0 {
                    sides[row][column] = 1
                } else {
                    sides[row][column] = 1 + min(
                        sides[row - 1][column],
                        sides[row][column - 1],
                        sides[row - 1][column - 1]
                    )
                }
            }
        }
        return sides
    }
}
