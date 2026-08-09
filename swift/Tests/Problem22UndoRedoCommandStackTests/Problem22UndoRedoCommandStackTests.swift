import Testing
@testable import Problem22UndoRedoCommandStack

private struct RenameCommand: Command {
    let from: String
    let to: String
    var actionDescription: String { "Rename" }
    func apply(to document: inout Document) { document.title = to }
    func revert(on document: inout Document) { document.title = from }
}

private struct AppendCommand: Command {
    let text: String
    var actionDescription: String { "Typing" }
    func apply(to document: inout Document) { document.body += text }
    func revert(on document: inout Document) { document.body.removeLast(text.count) }
    func coalesced(with newer: any Command) -> (any Command)? {
        guard let newer = newer as? AppendCommand else { return nil }
        return AppendCommand(text: text + newer.text)
    }
}

private struct DeleteSuffixCommand: Command {
    let text: String
    var actionDescription: String { "Delete" }
    func apply(to document: inout Document) { document.body.removeLast(text.count) }
    func revert(on document: inout Document) { document.body += text }
}

private struct TaggedAppendCommand: Command {
    let tag: String
    let text: String
    var actionDescription: String { "Typing \(tag)" }
    func apply(to document: inout Document) { document.body += text }
    func revert(on document: inout Document) { document.body.removeLast(text.count) }
    func coalesced(with newer: any Command) -> (any Command)? {
        guard let newer = newer as? TaggedAppendCommand, newer.tag == tag else { return nil }
        return TaggedAppendCommand(tag: tag, text: text + newer.text)
    }
}

private func makeFreshStack(title: String = "Draft", body: String = "") -> UndoRedoStack {
    UndoRedoStack(document: Document(title: title, body: body))
}

private func makeSeededStack() -> UndoRedoStack {
    var stack = makeFreshStack()
    stack.execute(RenameCommand(from: "Draft", to: "Plan"))
    stack.execute(AppendCommand(text: "hello"))
    return stack
}

@Suite("Part 1 — Execute, undo, and redo")
struct UndoRedoPart1Tests {
    @Test("execute applies commands and exposes undo state")
    func execute() {
        var stack = makeFreshStack()
        stack.execute(RenameCommand(from: "Draft", to: "Proposal"))
        #expect(stack.document.title == "Proposal")
        #expect(stack.canUndo)
        #expect(!stack.canRedo)
        #expect(stack.undoCount == 1)
        #expect(stack.nextUndoDescription == "Rename")
    }

    @Test("undo reverts the latest command")
    func undo() throws {
        var stack = makeSeededStack()
        try stack.undo()
        #expect(stack.document == Document(title: "Plan", body: ""))
        #expect(stack.undoCount == 1)
        #expect(stack.redoCount == 1)
        #expect(stack.nextUndoDescription == "Rename")
    }

    @Test("redo reapplies the latest undone command")
    func redo() throws {
        var stack = makeSeededStack()
        try stack.undo()
        try stack.redo()
        #expect(stack.document == Document(title: "Plan", body: "hello"))
        #expect(stack.undoCount == 2)
        #expect(!stack.canRedo)
    }

    @Test("empty history failures are typed")
    func emptyHistory() {
        var stack = makeFreshStack()
        #expect(throws: UndoRedoError.nothingToUndo) { try stack.undo() }
        #expect(throws: UndoRedoError.nothingToRedo) { try stack.redo() }
    }

    @Test("a new command after undo discards redo history")
    func redoClearing() throws {
        var stack = makeSeededStack()
        try stack.undo()
        stack.execute(AppendCommand(text: "future-replacement"))
        #expect(stack.document.body == "future-replacement")
        #expect(!stack.canRedo)
        #expect(stack.redoCount == 0)
    }

    @Test("stack values own independent history and documents")
    func isolation() {
        var first = makeFreshStack()
        let second = makeFreshStack()
        first.execute(AppendCommand(text: "only-first"))
        #expect(first.document.body == "only-first")
        #expect(second.document.body.isEmpty)
        #expect(!second.canUndo)
    }
}

@Suite("Part 2 — Coalesce compatible commands")
struct UndoRedoPart2Tests {
    @Test("compatible commands inside the inclusive window become one step")
    func insideWindow() throws {
        var stack = makeFreshStack()
        try stack.executeCoalescing(AppendCommand(text: "a"), at: 100, within: 2)
        try stack.executeCoalescing(AppendCommand(text: "b"), at: 102, within: 2)
        #expect(stack.document.body == "ab")
        #expect(stack.undoCount == 1)
        try stack.undo()
        #expect(stack.document.body.isEmpty)
    }

    @Test("compatible commands outside the window remain separate")
    func outsideWindow() throws {
        var stack = makeFreshStack()
        try stack.executeCoalescing(AppendCommand(text: "a"), at: 200, within: 2)
        try stack.executeCoalescing(AppendCommand(text: "b"), at: 203, within: 2)
        #expect(stack.undoCount == 2)
        try stack.undo()
        #expect(stack.document.body == "a")
    }

    @Test("the command itself can refuse coalescing")
    func incompatible() throws {
        var stack = makeFreshStack()
        try stack.executeCoalescing(TaggedAppendCommand(tag: "title", text: "x"), at: 300, within: 5)
        try stack.executeCoalescing(TaggedAppendCommand(tag: "body", text: "y"), at: 301, within: 5)
        #expect(stack.undoCount == 2)
    }

    @Test("a negative window fails before applying the command")
    func invalidWindow() {
        var stack = makeFreshStack()
        #expect(throws: UndoRedoError.invalidCoalescingWindow) {
            try stack.executeCoalescing(AppendCommand(text: "never"), at: 400, within: -1)
        }
        #expect(stack.document.body.isEmpty)
        #expect(!stack.canUndo)
    }
}

@Suite("Part 3 — Group commands into transactions")
struct UndoRedoPart3Tests {
    @Test("a group reverts atomically and redoes in forward order")
    func atomicGroup() throws {
        var stack = makeFreshStack()
        stack.beginGroup(description: "Build heading")
        stack.execute(RenameCommand(from: "Draft", to: "Launch"))
        stack.execute(AppendCommand(text: "A"))
        stack.execute(AppendCommand(text: "B"))
        try stack.endGroup()
        #expect(stack.undoCount == 1)
        #expect(stack.nextUndoDescription == "Build heading")
        try stack.undo()
        #expect(stack.document == Document(title: "Draft", body: ""))
        try stack.redo()
        #expect(stack.document == Document(title: "Launch", body: "AB"))
    }

    @Test("nested groups remain one step in their parent")
    func nesting() throws {
        var stack = makeFreshStack()
        stack.beginGroup(description: "Outer edit")
        stack.execute(AppendCommand(text: "1"))
        stack.beginGroup(description: "Inner edit")
        stack.execute(AppendCommand(text: "2"))
        stack.execute(AppendCommand(text: "3"))
        try stack.endGroup()
        stack.execute(AppendCommand(text: "4"))
        try stack.endGroup()
        #expect(stack.document.body == "1234")
        #expect(stack.undoCount == 1)
        try stack.undo()
        #expect(stack.document.body.isEmpty)
    }

    @Test("coalescing works inside a group without escaping it")
    func groupWithCoalescing() throws {
        var stack = makeFreshStack()
        stack.beginGroup(description: "Write and rename")
        try stack.executeCoalescing(AppendCommand(text: "h"), at: 500, within: 3)
        try stack.executeCoalescing(AppendCommand(text: "i"), at: 501, within: 3)
        stack.execute(RenameCommand(from: "Draft", to: "Greeting"))
        try stack.endGroup()
        #expect(stack.document == Document(title: "Greeting", body: "hi"))
        #expect(stack.undoCount == 1)
        try stack.undo()
        #expect(stack.document == Document(title: "Draft", body: ""))
    }

    @Test("empty and unmatched groups have explicit behavior")
    func groupEdges() throws {
        var stack = makeFreshStack()
        stack.beginGroup(description: "No changes")
        try stack.endGroup()
        #expect(!stack.canUndo)
        #expect(throws: UndoRedoError.noOpenGroup) { try stack.endGroup() }
    }
}
