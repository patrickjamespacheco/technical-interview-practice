// Problem 25: Warehouse Grid Route Planner
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// An autonomous picker crosses a rectangular warehouse floor from the north-west
// corner to the south-east one. Its drive controller only makes forward moves,
// and which forward moves depends on the chassis: a rail chassis moves east or
// south, a free chassis can also cut south-east. Aisles close for restocking.
//
// Planning needs the number of routes across the floor, the cheapest route's
// cost and its cell sequence, and - separately - the largest square of
// contiguous open aisles, because that is where a staging pallet can be parked.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Note that Array(repeating:count:) is safe for
// a grid of values like these, and would alias every row if the element were a
// reference type.
//
/*
# Example
let planner = RoutePlanner()
let openFloor = Array(repeating: Array(repeating: Aisle.open(traversalCost: 0), count: 3), count: 3)
try planner.routeCount(grid: openFloor)                              // -> 6
let floor: [[Aisle]] = [
    [.open(traversalCost: 1), .open(traversalCost: 3), .open(traversalCost: 1)],
    [.open(traversalCost: 1), .blocked,                .open(traversalCost: 1)],
    [.open(traversalCost: 4), .open(traversalCost: 2), .open(traversalCost: 1)],
]
try planner.routeCount(grid: floor)                                  // -> 2
try planner.cheapestCost(grid: floor, moves: [.east, .south])        // -> 7
try planner.cheapestRoute(grid: floor, moves: [.east, .south]).count // -> 5
// -> [(0,0), (0,1), (0,2), (1,2), (2,2)]
try planner.largestClearSquareSide(grid: floor)                      // -> 1
try planner.clearSquareCount(grid: floor)                            // -> 8
try planner.largestClearSquareSide(grid: openFloor)                  // -> 3
try planner.clearSquareCount(grid: openFloor)                        // -> 14
*/
//
// PART 1 - Count monotone routes  (~10 min)
// Count the east/south routes from the north-west corner to the south-east one.
// A closed aisle ends no route, and watch what that does along the first row and
// the first column. A closed origin or destination leaves no route at all. An
// empty floor plan and a ragged one are each a typed failure.
// This takes a floor plan rather than a pair of dimensions on purpose: run it
// against an all-open floor and you have the unobstructed count too.
//
// PART 2 - Cheapest traversal cost  (~12 min)
// Report the cheapest total traversal cost of crossing the floor with the given
// move set, counting the origin and the destination. Making the move set a
// parameter is what keeps one method covering both chassis; do not hard-code
// east and south anywhere. A chassis with no moves, a negative traversal cost,
// and a destination no route can reach are each a typed failure.
//
// PART 3 - Emit the cheapest route  (~12 min)
// Report the cheapest route itself, as the cells it visits from origin to
// destination. Parts 2 and 3 must share one private cost table: the cost is its
// corner, and the route is that same table walked backwards. Where two
// predecessors tie, enter the cell by the earliest move in the order east,
// south, southEast.
//
// PART 4 - Largest clear staging square  (~11 min)
// Report the side of the largest square of contiguous open aisles anywhere on
// the floor, and how many all-open squares of any size the floor contains.
// Parts 1 to 3 folded over the cells a route could arrive from. This folds over
// a cell's neighbours to grow a region. Same grid, same row-major order, a
// different meaning for one table entry - name that meaning before you write the
// transition, and note that both methods here are folds of the same table.

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

/// The forward moves a chassis can make. Every move increases the row or the
/// column, so no route can revisit a cell.
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
    public init() {}

    // MARK: Part 1 - Count monotone routes
    public func routeCount(grid: [[Aisle]]) throws(RouteError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 2 - Cheapest traversal cost
    public func cheapestCost(grid: [[Aisle]], moves: Set<DriveMove>) throws(RouteError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - Emit the cheapest route
    public func cheapestRoute(grid: [[Aisle]], moves: Set<DriveMove>) throws(RouteError) -> [GridPosition] {
        throw .notImplemented
    }

    // MARK: Part 4 - Largest clear staging square
    public func largestClearSquareSide(grid: [[Aisle]]) throws(RouteError) -> Int {
        throw .notImplemented
    }

    public func clearSquareCount(grid: [[Aisle]]) throws(RouteError) -> Int {
        throw .notImplemented
    }
}
