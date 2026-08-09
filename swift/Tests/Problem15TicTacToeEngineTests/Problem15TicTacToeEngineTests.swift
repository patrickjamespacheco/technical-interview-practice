import Testing
@testable import Problem15TicTacToeEngine

private func makeFreshBoard(size: Int = 3, winLength: Int? = nil) throws -> Board<Mark> { try Board(size: size, winLength: winLength) }

@Suite("Part 1 — Generic board analysis")
struct TicTacToePart1Tests {
    @Test func newBoardIsInProgressAndEmpty() throws {
        let board = try makeFreshBoard()
        #expect(board.result() == .inProgress)
        #expect(board.mark(at: Position(row: 1, column: 1)) == nil)
    }

    @Test func resultDistinguishesWinAndDraw() throws {
        let won = try Board<Mark>(positions: [.init(row: 0, column: 0): .x, .init(row: 0, column: 1): .x, .init(row: 0, column: 2): .x])
        #expect(won.result() == .won(.x))
        let marks: [[Mark]] = [[.x,.o,.x],[.x,.o,.o],[.o,.x,.x]]
        let positions = Dictionary(uniqueKeysWithValues: (0..<3).flatMap { row in (0..<3).map { column in (Position(row: row, column: column), marks[row][column]) } })
        let draw = try Board<Mark>(positions: positions)
        #expect(draw.result() == .draw)
    }

    @Test func genericPlayersAreSupported() throws {
        let board = try Board<String>(positions: [.init(row: 0, column: 2): "blue", .init(row: 1, column: 2): "blue", .init(row: 2, column: 2): "blue"])
        #expect(board.result() == .won("blue"))
    }
}

@Suite("Part 2 — Mutating moves and value semantics")
struct TicTacToePart2Tests {
    @Test func moveReturnsRichResultAndStoresMark() throws {
        var board = try makeFreshBoard()
        #expect(try board.place(.o, at: .init(row: 1, column: 1)) == .inProgress)
        #expect(board.mark(at: .init(row: 1, column: 1)) == .o)
    }

    @Test func invalidMovesAreTypedAndDoNotMutate() throws {
        var board = try makeFreshBoard()
        let occupied = Position(row: 0, column: 0)
        _ = try board.place(.x, at: occupied)
        #expect(throws: BoardError.occupied(occupied)) { try board.place(.o, at: occupied) }
        let outside = Position(row: -1, column: 2)
        #expect(throws: BoardError.outOfBounds(outside)) { try board.place(.o, at: outside) }
        #expect(board.mark(at: occupied) == .x)
    }

    @Test func boardCopiesAreGenuinelyIndependent() throws {
        var original = try makeFreshBoard(); var copy = original
        _ = try original.place(.x, at: .init(row: 0, column: 0))
        _ = try copy.place(.o, at: .init(row: 2, column: 2))
        #expect(copy.mark(at: .init(row: 0, column: 0)) == nil)
        #expect(original.mark(at: .init(row: 2, column: 2)) == nil)
    }

    @Test func resetClearsBoardAndOutcome() throws {
        var board = try makeFreshBoard()
        for column in 0..<3 { _ = try board.place(.x, at: .init(row: 1, column: column)) }
        board.reset()
        #expect(board.result() == .inProgress)
        #expect(board.mark(at: .init(row: 1, column: 1)) == nil)
    }
}

@Suite("Part 3 — Configurable dimensions and win runs")
struct TicTacToePart3Tests {
    @Test func invalidConfigurationsAreRejected() {
        #expect(throws: BoardError.invalidConfiguration) { try Board<Mark>(size: 0) }
        #expect(throws: BoardError.invalidConfiguration) { try Board<Mark>(size: 4, winLength: 5) }
    }

    @Test(arguments: [(0, 1), (1, 0), (1, 1), (1, -1)])
    func consecutiveRunsWinInEveryDirection(rowStep: Int, columnStep: Int) throws {
        var board = try makeFreshBoard(size: 5, winLength: 3)
        let start = columnStep < 0 ? Position(row: 1, column: 3) : Position(row: 1, column: 1)
        var final: GameResult<Mark> = .inProgress
        for offset in 0..<3 { final = try board.place(.custom("green"), at: .init(row: start.row + rowStep * offset, column: start.column + columnStep * offset)) }
        #expect(final == .won(.custom("green")))
    }

    @Test func gapsAndShortRunsDoNotWin() throws {
        var board = try makeFreshBoard(size: 5, winLength: 3)
        _ = try board.place(.x, at: .init(row: 2, column: 0))
        _ = try board.place(.x, at: .init(row: 2, column: 2))
        _ = try board.place(.x, at: .init(row: 2, column: 3))
        #expect(board.result() == .inProgress)
    }
}
