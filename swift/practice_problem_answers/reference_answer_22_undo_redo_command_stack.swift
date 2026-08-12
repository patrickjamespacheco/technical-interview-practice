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

    /// A history entry keeps the timestamp that produced it so Part 2 can decide
    /// whether the next command is close enough in time to coalesce.
    private struct HistoryEntry {
        let command: any Command
        let timestamp: Int?
    }

    private struct GroupFrame {
        let description: String
        var entries: [HistoryEntry]
    }

    /// A finished group is just another command: apply forward, revert backward.
    private struct GroupCommand: Command {
        let actionDescription: String
        let commands: [any Command]
        func apply(to document: inout Document) {
            for command in commands { command.apply(to: &document) }
        }
        func revert(on document: inout Document) {
            for command in commands.reversed() { command.revert(on: &document) }
        }
    }

    private var undoStack: [HistoryEntry] = []
    private var redoStack: [any Command] = []
    private var openGroups: [GroupFrame] = []

    public init(document: Document) {
        self.document = document
    }

    // MARK: Part 1 — execute, undo, and redo

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoCount: Int { undoStack.count }
    public var redoCount: Int { redoStack.count }
    public var nextUndoDescription: String? { undoStack.last?.command.actionDescription }

    public mutating func execute(_ command: any Command) {
        execute(command, timestamp: nil)
    }

    public mutating func undo() throws(UndoRedoError) {
        guard let entry = undoStack.popLast() else { throw .nothingToUndo }
        entry.command.revert(on: &document)
        redoStack.append(entry.command)
    }

    public mutating func redo() throws(UndoRedoError) {
        guard let command = redoStack.popLast() else { throw .nothingToRedo }
        command.apply(to: &document)
        undoStack.append(HistoryEntry(command: command, timestamp: nil))
    }

    /// The single mutation path: everything that changes the document goes
    /// through here, so history and the document can never disagree.
    private mutating func execute(_ command: any Command, timestamp: Int?) {
        command.apply(to: &document)
        redoStack.removeAll()
        currentEntries.append(HistoryEntry(command: command, timestamp: timestamp))
    }

    /// History is recorded into the innermost open group, or into the undo stack
    /// when no group is open. Coalescing therefore never crosses a group edge.
    private var currentEntries: [HistoryEntry] {
        get { openGroups.last?.entries ?? undoStack }
        set {
            if openGroups.isEmpty { undoStack = newValue } else { openGroups[openGroups.count - 1].entries = newValue }
        }
    }

    // MARK: Part 2 — command-directed coalescing

    public mutating func executeCoalescing(
        _ command: any Command,
        at timestamp: Int,
        within window: Int
    ) throws(UndoRedoError) {
        guard window >= 0 else { throw .invalidCoalescingWindow }
        execute(command, timestamp: timestamp)
        var entries = currentEntries
        guard entries.count >= 2 else { return }
        let older = entries[entries.count - 2]
        guard let previousTimestamp = older.timestamp, timestamp - previousTimestamp <= window else { return }
        // Only the older command knows whether the two can become one step.
        guard let merged = older.command.coalesced(with: command) else { return }
        entries.removeLast(2)
        entries.append(HistoryEntry(command: merged, timestamp: timestamp))
        currentEntries = entries
    }

    // MARK: Part 3 — nested transaction groups

    public mutating func beginGroup(description: String) {
        openGroups.append(GroupFrame(description: description, entries: []))
    }

    public mutating func endGroup() throws(UndoRedoError) {
        guard let frame = openGroups.popLast() else { throw .noOpenGroup }
        guard !frame.entries.isEmpty else { return }
        // The document is already in its final state, so the group command is
        // only recorded; recording it in the parent makes nesting collapse.
        currentEntries.append(HistoryEntry(
            command: GroupCommand(actionDescription: frame.description, commands: frame.entries.map(\.command)),
            timestamp: nil
        ))
    }
}
