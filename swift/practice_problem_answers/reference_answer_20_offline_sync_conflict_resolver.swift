import Foundation

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
    private var recordsByID: [String: SyncRecord] = [:]
    /// Only dirty records have a baseline: it is the clean value their local
    /// edits started from, which is exactly what a field merge needs.
    private var baselines: [String: SyncRecord] = [:]

    public init(records: [SyncRecord] = []) {
        for record in records { recordsByID[record.id] = record }
    }

    // MARK: Part 1 — versioned local state and dirty snapshots

    public func record(id: String) -> SyncRecord? { recordsByID[id] }

    @discardableResult
    public mutating func edit(
        id: String,
        title: String? = nil,
        body: String? = nil,
        at instant: Date,
        originID: String
    ) throws(SyncStoreError) -> SyncRecord {
        let current = try liveRecord(id)
        guard case let .note(fields) = current.content else { throw .recordDeleted(id) }
        return applyLocalChange(
            to: current,
            content: .note(NoteFields(title: title ?? fields.title, body: body ?? fields.body)),
            at: instant,
            originID: originID
        )
    }

    @discardableResult
    public mutating func delete(
        id: String,
        at instant: Date,
        originID: String
    ) throws(SyncStoreError) -> SyncRecord {
        let current = try liveRecord(id)
        return applyLocalChange(to: current, content: .tombstone(reason: .userDeleted), at: instant, originID: originID)
    }

    public func pendingChanges() -> PendingChanges {
        PendingChanges(changes: baselines.keys.sorted().compactMap { id in
            guard let baseline = baselines[id], let local = recordsByID[id] else { return nil }
            return PendingChange(baseline: baseline, local: local)
        })
    }

    private func liveRecord(_ id: String) throws(SyncStoreError) -> SyncRecord {
        guard let current = recordsByID[id] else { throw .unknownRecord(id) }
        guard case .note = current.content else { throw .recordDeleted(id) }
        return current
    }

    /// Every local mutation goes through here, so versioning, the injected
    /// instant, and baseline capture can never drift apart.
    private mutating func applyLocalChange(to current: SyncRecord, content: RecordContent, at instant: Date, originID: String) -> SyncRecord {
        if baselines[current.id] == nil { baselines[current.id] = current }
        let updated = SyncRecord(
            id: current.id,
            version: current.version + 1,
            lastModified: instant,
            originID: originID,
            content: content
        )
        recordsByID[current.id] = updated
        return updated
    }

    // MARK: Part 2 — deterministic reconciliation

    public func reconcile(remote: [SyncRecord]) -> [ReconciliationOutcome] {
        let baselinesByID = Dictionary(uniqueKeysWithValues: pendingChanges().changes.map { ($0.local.id, $0.baseline) })
        return remote.sorted { $0.id < $1.id }.map { remoteRecord in
            guard let local = recordsByID[remoteRecord.id] else {
                return .remoteWins(SyncComparison(baseline: nil, local: nil, remote: remoteRecord))
            }
            guard local != remoteRecord else { return .unchanged(local) }
            let comparison = SyncComparison(baseline: baselinesByID[remoteRecord.id], local: local, remote: remoteRecord)
            switch precedence(local: local, remote: remoteRecord) {
            case .local: return .localWins(comparison)
            case .remote: return .remoteWins(comparison)
            case .ambiguous: return .conflicted(comparison)
            }
        }
    }

    private enum Precedence { case local, remote, ambiguous }

    /// Version, then modification time, then origin ID. The last step exists so
    /// two devices never disagree about who won.
    private func precedence(local: SyncRecord, remote: SyncRecord) -> Precedence {
        if local.version != remote.version { return local.version > remote.version ? .local : .remote }
        if local.lastModified != remote.lastModified { return local.lastModified > remote.lastModified ? .local : .remote }
        if local.originID != remote.originID { return local.originID > remote.originID ? .local : .remote }
        return .ambiguous
    }

    // MARK: Part 3 — outcome-driven resolution

    @discardableResult
    public mutating func apply(
        _ outcomes: [ReconciliationOutcome],
        resolution: ResolutionStrategy,
        at instant: Date,
        originID: String
    ) -> [AppliedResolution] {
        outcomes.map { outcome in
            let applied = resolve(outcome, resolution: resolution, at: instant, originID: originID)
            // Every input of `resolve` comes from the outcome, so replaying the
            // same batch produces the same record: application is idempotent.
            recordsByID[applied.record.id] = applied.record
            baselines[applied.record.id] = nil
            return applied
        }
    }

    private func resolve(_ outcome: ReconciliationOutcome, resolution: ResolutionStrategy, at instant: Date, originID: String) -> AppliedResolution {
        switch outcome {
        case let .unchanged(record):
            return AppliedResolution(record: record, reason: .unchanged)
        case let .localWins(comparison):
            guard case .mergeFields = resolution, comparison.local != nil else {
                return AppliedResolution(record: comparison.local ?? comparison.remote, reason: .retainedLocal)
            }
            return merge(comparison, resolution: resolution, at: instant, originID: originID)
        case let .remoteWins(comparison), let .conflicted(comparison):
            guard case .mergeFields = resolution, comparison.local != nil else {
                return AppliedResolution(record: comparison.remote, reason: .acceptedRemote)
            }
            return merge(comparison, resolution: resolution, at: instant, originID: originID)
        }
    }

    private func merge(_ comparison: SyncComparison, resolution: ResolutionStrategy, at instant: Date, originID: String) -> AppliedResolution {
        guard case let .mergeFields(preference) = resolution, let local = comparison.local else {
            return AppliedResolution(record: comparison.remote, reason: .acceptedRemote)
        }
        let remote = comparison.remote
        let version = max(local.version, remote.version) + 1
        // A deletion is not a field, so it cannot be merged: whichever side
        // deleted the record wins, and the record says why.
        if case .tombstone = local.content {
            return AppliedResolution(
                record: SyncRecord(id: local.id, version: version, lastModified: instant, originID: originID,
                                   content: .tombstone(reason: .tombstonePrecedence(deletedOriginID: local.originID, editedOriginID: remote.originID))),
                reason: .tombstonePrecedence
            )
        }
        if case .tombstone = remote.content {
            return AppliedResolution(
                record: SyncRecord(id: local.id, version: version, lastModified: instant, originID: originID,
                                   content: .tombstone(reason: .tombstonePrecedence(deletedOriginID: remote.originID, editedOriginID: local.originID))),
                reason: .tombstonePrecedence
            )
        }
        guard case let .note(localFields) = local.content, case let .note(remoteFields) = remote.content else {
            return AppliedResolution(record: remote, reason: .acceptedRemote)
        }
        var baselineFields: NoteFields?
        if case let .note(fields)? = comparison.baseline?.content { baselineFields = fields }
        let merged = NoteFields(
            title: mergedValue(baseline: baselineFields?.title, local: localFields.title, remote: remoteFields.title, prefer: preference),
            body: mergedValue(baseline: baselineFields?.body, local: localFields.body, remote: remoteFields.body, prefer: preference)
        )
        return AppliedResolution(
            record: SyncRecord(id: local.id, version: version, lastModified: instant, originID: originID, content: .note(merged)),
            reason: .fieldMerge
        )
    }

    /// A one-sided edit is not a conflict; the preference only settles the case
    /// where both sides changed the same field to different values.
    private func mergedValue(baseline: String?, local: String, remote: String, prefer: MergePreference) -> String {
        guard local != remote else { return local }
        let baseline = baseline ?? local
        if local == baseline { return remote }
        if remote == baseline { return local }
        return prefer == .local ? local : remote
    }
}
