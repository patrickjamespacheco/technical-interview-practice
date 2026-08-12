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

    // MARK: Part 1 — generic board analysis

    public func mark(at position: Position) -> Player? { cells[position] }

    public func result() -> GameResult<Player> {
        for row in 0..<size {
            for column in 0..<size {
                if let winner = winner(startingAt: Position(row: row, column: column)) { return .won(winner) }
            }
        }
        return cells.count == size * size ? .draw : .inProgress
    }

    /// The four step vectors cover every line once: east, south, south-east,
    /// and south-west. Scanning from every occupied cell reaches all of them.
    private static var directions: [(rowStep: Int, columnStep: Int)] {
        [(0, 1), (1, 0), (1, 1), (1, -1)]
    }

    private func winner(startingAt position: Position) -> Player? {
        guard let player = cells[position] else { return nil }
        for direction in Self.directions {
            let run = (0..<winLength).allSatisfy { offset in
                cells[Position(row: position.row + direction.rowStep * offset,
                               column: position.column + direction.columnStep * offset)] == player
            }
            if run { return player }
        }
        return nil
    }

    // MARK: Part 2 — mutating moves and value semantics

    public mutating func place(_ player: Player, at position: Position) throws(BoardError) -> GameResult<Player> {
        guard (0..<size).contains(position.row), (0..<size).contains(position.column) else {
            throw .outOfBounds(position)
        }
        guard cells[position] == nil else { throw .occupied(position) }
        cells[position] = player
        // A move's outcome is just the board's analysis after the move.
        return result()
    }

    public mutating func reset() { cells.removeAll() }
}
