// Problem 15: Tic-Tac-Toe Engine
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build a configurable, value-semantic board. Board is generic so the engine is
// reusable, while Mark supplies the familiar tic-tac-toe players. All mutable
// state belongs to each Board value; copies must evolve independently.
//
/*
# Example
var board = try Board<Mark>()
try board.place(.x, at: Position(row: 0, column: 0)) // -> .inProgress
try board.place(.x, at: Position(row: 0, column: 1)) // -> .inProgress
try board.place(.x, at: Position(row: 0, column: 2)) // -> .won(.x)
*/
//
// PART 1 — Generic board analysis  (~10 min)
// Model cells with Position and analyze rows, columns, and both diagonals.
// result() returns in-progress, won, or draw without string sentinels.
//
// PART 2 — Mutating moves and value semantics  (~20 min)
// place validates bounds and occupancy, mutates this board, and returns result().
// Expose the mark at a position and reset the board. Board copies must not share state.
//
// PART 3 — Configurable dimensions and win runs  (~15 min)
// Support arbitrary positive size and winLength (1...size). Detect consecutive
// horizontal, vertical, and diagonal runs of winLength on larger boards.

public enum Mark: Hashable, Sendable { case x, o, custom(String) }
public struct Position: Hashable, Sendable {
    public let row: Int; public let column: Int
    public init(row: Int, column: Int) { self.row = row; self.column = column }
}
public enum GameResult<Player: Hashable & Sendable>: Equatable, Sendable {
    case inProgress, won(Player), draw
}
public enum BoardError: Error, Equatable, Sendable {
    case invalidConfiguration
    case outOfBounds(Position)
    case occupied(Position)
    case notImplemented
}

public struct Board<Player: Hashable & Sendable>: Sendable {
    public let size: Int
    public let winLength: Int
    private var cells: [Position: Player]
    public init(size: Int = 3, winLength: Int? = nil, positions: [Position: Player] = [:]) throws(BoardError) {
        let target = winLength ?? size
        guard size > 0, target > 0, target <= size else { throw .invalidConfiguration }
        guard positions.keys.allSatisfy({ (0..<size).contains($0.row) && (0..<size).contains($0.column) }) else { throw .invalidConfiguration }
        self.size = size; self.winLength = target; self.cells = positions
    }
    public func mark(at position: Position) -> Player? { nil }
    public func result() -> GameResult<Player> { .inProgress }
    public mutating func place(_ player: Player, at position: Position) throws(BoardError) -> GameResult<Player> { throw .notImplemented }
    public mutating func reset() {}
}
