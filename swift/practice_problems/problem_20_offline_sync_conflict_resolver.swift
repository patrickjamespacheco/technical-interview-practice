import Foundation

// Problem 20: Offline Sync Conflict Resolver
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build the reconciliation core for a productivity app whose notes can change
// while a device is offline. The public interface is the contract; you choose
// the internal data structures. Store all mutable state in instance properties
// initialized by init. Never use mutable global or static state.
//
// PART 1 — Versioned local changes  (~12 min)
// Store the supplied records. edit changes selected fields, increments the
// record's version once, uses only the injected instant, and marks it dirty.
// delete replaces a live record with a tombstone under the same rules.
// pendingChanges returns a value snapshot, sorted by record ID, containing each
// dirty record and the clean baseline from which its local changes began.
//
// PART 2 — Rich reconciliation outcomes  (~15 min)
// reconcile(remote:) compares a batch with local state. It must call
// pendingChanges() to discover dirty records and return one outcome per remote
// ID, sorted by ID. Compare version first, then lastModified, then originID
// lexicographically as the deterministic tie-break. Identical records are
// unchanged. If all ordering metadata ties but content differs, report a
// conflicted outcome. Every non-unchanged outcome carries a SyncComparison with
// enough baseline/local/remote context for Part 3; do not expose parallel logic.
//
// PART 3 — Merge fields and preserve tombstones  (~18 min)
// apply(_:resolution:at:originID:) consumes Part 2 outcomes directly. With
// mergeFields, compare each field with the baseline: preserve one-sided edits,
// and use the chosen preference only when both sides changed the same field
// differently. A tombstone always beats a live edit, recording why deletion won.
// A synthesized merge has max(local, remote) version + 1 and the injected time
// and origin. Applying the exact same outcome batch again must be idempotent.
//
/*
 * Example
 * let base = SyncRecord(id: "note-plan", version: 2, lastModified: Date(timeIntervalSince1970: 20), originID: "server", content: .note(.init(title: "Plan", body: "Draft")))
 * var store = OfflineSyncStore(records: [base])
 * try store.edit(id: "note-plan", title: "Launch plan", at: Date(timeIntervalSince1970: 30), originID: "phone").version // -> 3
 * store.reconcile(remote: [base]).first?.kind // -> .localWins
 * let remote = SyncRecord(id: "note-plan", version: 4, lastModified: Date(timeIntervalSince1970: 40), originID: "server", content: .note(.init(title: "Plan", body: "Approved")))
 * let outcomes = store.reconcile(remote: [remote])
 * store.apply(outcomes, resolution: .mergeFields(prefer: .remote), at: Date(timeIntervalSince1970: 50), originID: "phone").first?.record.content // -> .note(.init(title: "Launch plan", body: "Approved"))
 * After delete, applying a racing live edit returns .tombstone with reason .tombstonePrecedence.
 */

public struct NoteFields: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum DeletionReason: Equatable, Sendable {
    case userDeleted
    case tombstonePrecedence(deletedOriginID: String, editedOriginID: String)
}

public enum RecordContent: Equatable, Sendable {
    case note(NoteFields)
    case tombstone(reason: DeletionReason)
}

public struct SyncRecord: Equatable, Sendable {
    public let id: String
    public let version: Int
    public let lastModified: Date
    public let originID: String
    public let content: RecordContent

    public init(id: String, version: Int, lastModified: Date, originID: String, content: RecordContent) {
        self.id = id
        self.version = version
        self.lastModified = lastModified
        self.originID = originID
        self.content = content
    }
}

public struct PendingChange: Equatable, Sendable {
    public let baseline: SyncRecord
    public let local: SyncRecord

    public init(baseline: SyncRecord, local: SyncRecord) {
        self.baseline = baseline
        self.local = local
    }
}

public struct PendingChanges: Equatable, Sendable {
    public let changes: [PendingChange]

    public init(changes: [PendingChange]) {
        self.changes = changes
    }
}

public struct SyncComparison: Equatable, Sendable {
    public let baseline: SyncRecord?
    public let local: SyncRecord?
    public let remote: SyncRecord

    public init(baseline: SyncRecord?, local: SyncRecord?, remote: SyncRecord) {
        self.baseline = baseline
        self.local = local
        self.remote = remote
    }
}

public enum ReconciliationKind: Equatable, Sendable {
    case unchanged
    case remoteWins
    case localWins
    case conflicted
}

public enum ReconciliationOutcome: Equatable, Sendable {
    case unchanged(SyncRecord)
    case remoteWins(SyncComparison)
    case localWins(SyncComparison)
    case conflicted(SyncComparison)

    public var kind: ReconciliationKind {
        switch self {
        case .unchanged: .unchanged
        case .remoteWins: .remoteWins
        case .localWins: .localWins
        case .conflicted: .conflicted
        }
    }

    public var recordID: String {
        switch self {
        case let .unchanged(record): record.id
        case let .remoteWins(comparison), let .localWins(comparison), let .conflicted(comparison): comparison.remote.id
        }
    }
}

public enum MergePreference: Equatable, Sendable {
    case local
    case remote
}

public enum ResolutionStrategy: Equatable, Sendable {
    case acceptWinner
    case mergeFields(prefer: MergePreference)
}

public enum ResolutionReason: Equatable, Sendable {
    case unchanged
    case acceptedRemote
    case retainedLocal
    case fieldMerge
    case tombstonePrecedence
}

public struct AppliedResolution: Equatable, Sendable {
    public let record: SyncRecord
    public let reason: ResolutionReason

    public init(record: SyncRecord, reason: ResolutionReason) {
        self.record = record
        self.reason = reason
    }
}

public enum SyncStoreError: Error, Equatable, Sendable {
    case unknownRecord(String)
    case recordDeleted(String)
    case notImplemented
}

public struct OfflineSyncStore: Sendable {
    public init(records: [SyncRecord] = []) {}

    // MARK: Part 1 — versioned local state and dirty snapshots
    public func record(id: String) -> SyncRecord? { nil }

    @discardableResult
    public mutating func edit(
        id: String,
        title: String? = nil,
        body: String? = nil,
        at instant: Date,
        originID: String
    ) throws(SyncStoreError) -> SyncRecord {
        throw .notImplemented
    }

    @discardableResult
    public mutating func delete(
        id: String,
        at instant: Date,
        originID: String
    ) throws(SyncStoreError) -> SyncRecord {
        throw .notImplemented
    }

    public func pendingChanges() -> PendingChanges { PendingChanges(changes: []) }

    // MARK: Part 2 — deterministic reconciliation
    public func reconcile(remote: [SyncRecord]) -> [ReconciliationOutcome] { [] }

    // MARK: Part 3 — outcome-driven resolution
    @discardableResult
    public mutating func apply(
        _ outcomes: [ReconciliationOutcome],
        resolution: ResolutionStrategy,
        at instant: Date,
        originID: String
    ) -> [AppliedResolution] { [] }
}
