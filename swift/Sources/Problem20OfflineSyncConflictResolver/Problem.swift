import Foundation

// Active source placeholder. The runner substitutes a candidate answer here.

public struct NoteFields: Equatable, Sendable { public let title: String; public let body: String; public init(title: String, body: String) { self.title = title; self.body = body } }
public enum DeletionReason: Equatable, Sendable { case userDeleted; case tombstonePrecedence(deletedOriginID: String, editedOriginID: String) }
public enum RecordContent: Equatable, Sendable { case note(NoteFields); case tombstone(reason: DeletionReason) }
public struct SyncRecord: Equatable, Sendable { public let id: String; public let version: Int; public let lastModified: Date; public let originID: String; public let content: RecordContent; public init(id: String, version: Int, lastModified: Date, originID: String, content: RecordContent) { self.id = id; self.version = version; self.lastModified = lastModified; self.originID = originID; self.content = content } }
public struct PendingChange: Equatable, Sendable { public let baseline: SyncRecord; public let local: SyncRecord; public init(baseline: SyncRecord, local: SyncRecord) { self.baseline = baseline; self.local = local } }
public struct PendingChanges: Equatable, Sendable { public let changes: [PendingChange]; public init(changes: [PendingChange]) { self.changes = changes } }
public struct SyncComparison: Equatable, Sendable { public let baseline: SyncRecord?; public let local: SyncRecord?; public let remote: SyncRecord; public init(baseline: SyncRecord?, local: SyncRecord?, remote: SyncRecord) { self.baseline = baseline; self.local = local; self.remote = remote } }
public enum ReconciliationKind: Equatable, Sendable { case unchanged, remoteWins, localWins, conflicted }
public enum ReconciliationOutcome: Equatable, Sendable {
    case unchanged(SyncRecord); case remoteWins(SyncComparison); case localWins(SyncComparison); case conflicted(SyncComparison)
    public var kind: ReconciliationKind { switch self { case .unchanged: .unchanged; case .remoteWins: .remoteWins; case .localWins: .localWins; case .conflicted: .conflicted } }
    public var recordID: String { switch self { case let .unchanged(record): record.id; case let .remoteWins(value), let .localWins(value), let .conflicted(value): value.remote.id } }
}
public enum MergePreference: Equatable, Sendable { case local, remote }
public enum ResolutionStrategy: Equatable, Sendable { case acceptWinner; case mergeFields(prefer: MergePreference) }
public enum ResolutionReason: Equatable, Sendable { case unchanged, acceptedRemote, retainedLocal, fieldMerge, tombstonePrecedence }
public struct AppliedResolution: Equatable, Sendable { public let record: SyncRecord; public let reason: ResolutionReason; public init(record: SyncRecord, reason: ResolutionReason) { self.record = record; self.reason = reason } }
public enum SyncStoreError: Error, Equatable, Sendable { case unknownRecord(String), recordDeleted(String), notImplemented }
public struct OfflineSyncStore: Sendable {
    public init(records: [SyncRecord] = []) {}
    public func record(id: String) -> SyncRecord? { nil }
    public mutating func edit(id: String, title: String? = nil, body: String? = nil, at instant: Date, originID: String) throws(SyncStoreError) -> SyncRecord { throw .notImplemented }
    public mutating func delete(id: String, at instant: Date, originID: String) throws(SyncStoreError) -> SyncRecord { throw .notImplemented }
    public func pendingChanges() -> PendingChanges { .init(changes: []) }
    public func reconcile(remote: [SyncRecord]) -> [ReconciliationOutcome] { [] }
    public mutating func apply(_ outcomes: [ReconciliationOutcome], resolution: ResolutionStrategy, at instant: Date, originID: String) -> [AppliedResolution] { [] }
}
