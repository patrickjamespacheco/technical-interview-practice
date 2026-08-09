// Problem 22: Undo/Redo Command Stack
// Swift 6, macOS 14+ | Mid-level | approximately 45 minutes
//
// Build the history engine behind a small document editor. Commands know how to
// apply and revert themselves, while UndoRedoStack owns the current document and
// its history. You choose the internal data structures; the public interface is
// the contract. Store all mutable state in instance properties initialized by
// init. Never use mutable global or static state.
//
/*
# Example
struct RenameCommand: Command {
    let from: String; let to: String
    var actionDescription: String { "Rename" }
    func apply(to document: inout Document) { document.title = to }
    func revert(on document: inout Document) { document.title = from }
}
struct AppendCommand: Command {
    let text: String
    var actionDescription: String { "Typing" }
    func apply(to document: inout Document) { document.body += text }
    func revert(on document: inout Document) { document.body.removeLast(text.count) }
    func coalesced(with newer: any Command) -> (any Command)? {
        guard let newer = newer as? AppendCommand else { return nil }
        return AppendCommand(text: text + newer.text)
    }
}
struct DeleteSuffixCommand: Command {
    let text: String
    var actionDescription: String { "Delete" }
    func apply(to document: inout Document) { document.body.removeLast(text.count) }
    func revert(on document: inout Document) { document.body += text }
}
var history = UndoRedoStack(document: Document(title: "Draft", body: ""))
history.execute(RenameCommand(from: "Draft", to: "Plan"))
history.executeCoalescing(AppendCommand(text: "H"), at: 10, within: 2)
history.executeCoalescing(AppendCommand(text: "i"), at: 11, within: 2)
history.execute(DeleteSuffixCommand(text: "i"))
history.undoCount // -> 3
try history.undo()
try history.undo()
history.execute(AppendCommand(text: "!"))
history.canRedo // -> false
history.beginGroup(description: "Format section")
history.executeCoalescing(AppendCommand(text: "A"), at: 20, within: 2)
history.executeCoalescing(AppendCommand(text: "B"), at: 21, within: 2)
history.execute(RenameCommand(from: "Plan", to: "Final"))
try history.endGroup()
try history.undo() // -> reverts all three grouped edits
*/
//
// PART 1 — Execute, undo, and redo  (~18 min)
// Implement Command and the basic history stack. execute is the one method that
// applies a command to the document. undo and redo move commands between their
// respective histories. Executing a new command always clears redo history.
// nextUndoDescription describes the command that undo() would revert.
//
// PART 2 — Coalesce compatible commands  (~12 min)
// executeCoalescing(_:at:within:) must call execute(_:) for the mutation. When
// this command and the immediately preceding command are compatible, within the
// inclusive injected time window, ask the older command to coalesce(with:) the
// newer one and replace those two history entries with the returned command.
// A negative window is invalid. Never read the system clock.
//
// PART 3 — Group commands into transactions  (~15 min)
// beginGroup opens an explicit transaction and endGroup closes it. Commands in a
// group still travel through execute or executeCoalescing, but the completed
// outer group becomes one undoable command. Nested groups become one command in
// their parent. Undo a group in reverse order and redo it in forward order. Empty
// groups add no history. An unmatched endGroup is a typed failure.

public struct Document: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public protocol Command: Sendable {
    var actionDescription: String { get }
    func apply(to document: inout Document)
    func revert(on document: inout Document)

    /// Return one command representing `self` followed by `newer`, or nil when
    /// the commands are incompatible and must remain separate undo steps.
    func coalesced(with newer: any Command) -> (any Command)?
}

public extension Command {
    func coalesced(with newer: any Command) -> (any Command)? { nil }
}

public enum UndoRedoError: Error, Equatable, Sendable {
    case nothingToUndo
    case nothingToRedo
    case invalidCoalescingWindow
    case noOpenGroup
    case notImplemented
}

public struct UndoRedoStack: Sendable {
    public private(set) var document: Document

    public init(document: Document) {
        self.document = document
    }

    // MARK: Part 1 — execute, undo, and redo
    public var canUndo: Bool { false }
    public var canRedo: Bool { false }
    public var undoCount: Int { 0 }
    public var redoCount: Int { 0 }
    public var nextUndoDescription: String? { nil }

    public mutating func execute(_ command: any Command) {}
    public mutating func undo() throws(UndoRedoError) { throw .notImplemented }
    public mutating func redo() throws(UndoRedoError) { throw .notImplemented }

    // MARK: Part 2 — command-directed coalescing
    public mutating func executeCoalescing(
        _ command: any Command,
        at timestamp: Int,
        within window: Int
    ) throws(UndoRedoError) {
        throw .notImplemented
    }

    // MARK: Part 3 — nested transaction groups
    public mutating func beginGroup(description: String) {}
    public mutating func endGroup() throws(UndoRedoError) { throw .notImplemented }
}
