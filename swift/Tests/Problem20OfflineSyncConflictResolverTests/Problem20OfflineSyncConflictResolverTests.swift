import Foundation
import Testing
@testable import Problem20OfflineSyncConflictResolver

private func instant(_ value: TimeInterval) -> Date { Date(timeIntervalSince1970: value) }
private func note(_ id: String, version: Int = 1, time: TimeInterval = 10, origin: String = "server", title: String = "Title", body: String = "Body") -> SyncRecord {
    SyncRecord(id: id, version: version, lastModified: instant(time), originID: origin, content: .note(.init(title: title, body: body)))
}
private func makeFreshStore() -> OfflineSyncStore { OfflineSyncStore() }
private func makeSeededStore(id: String = "seed-note") -> OfflineSyncStore { OfflineSyncStore(records: [note(id)]) }

@Suite("Part 1 — Versioned local changes")
struct Part1VersionedStore {
    @Test("edits bump versions, use injected time, and preserve untouched typed fields")
    func versioning() throws {
        var store = makeSeededStore(id: "version-note")
        let edited = try store.edit(id: "version-note", title: "Updated", at: instant(40), originID: "phone-a")
        #expect(edited == note("version-note", version: 2, time: 40, origin: "phone-a", title: "Updated"))
        let editedAgain = try store.edit(id: "version-note", body: "New body", at: instant(50), originID: "phone-a")
        #expect(editedAgain.version == 3)
        #expect(editedAgain.content == .note(.init(title: "Updated", body: "New body")))
    }

    @Test("dirty tracking retains the original baseline and returns a sorted value snapshot")
    func pendingSnapshot() throws {
        let first = note("pending-b")
        let second = note("pending-a", title: "Second")
        var store = OfflineSyncStore(records: [first, second])
        _ = try store.edit(id: "pending-b", title: "Local B", at: instant(20), originID: "phone")
        _ = try store.edit(id: "pending-b", body: "Local body", at: instant(30), originID: "phone")
        _ = try store.delete(id: "pending-a", at: instant(25), originID: "tablet")
        let snapshot = store.pendingChanges()
        #expect(snapshot.changes.map(\.local.id) == ["pending-a", "pending-b"])
        #expect(snapshot.changes.last?.baseline == first)
        #expect(snapshot.changes.last?.local.version == 3)
        var copied = snapshot.changes
        copied.removeAll()
        #expect(store.pendingChanges().changes.count == 2)
    }

    @Test("unknown and deleted edits fail without hidden wall-clock behavior")
    func typedFailures() throws {
        var store = makeSeededStore(id: "failure-note")
        #expect(throws: SyncStoreError.unknownRecord("missing-note")) {
            try store.edit(id: "missing-note", title: "Nope", at: instant(60), originID: "phone")
        }
        _ = try store.delete(id: "failure-note", at: instant(70), originID: "phone")
        #expect(throws: SyncStoreError.recordDeleted("failure-note")) {
            try store.edit(id: "failure-note", body: "Resurrect", at: instant(80), originID: "phone")
        }
    }

    @Test("store values own independent mutable state")
    func isolation() throws {
        var first = makeSeededStore(id: "isolation-note")
        let second = first
        _ = try first.edit(id: "isolation-note", title: "First only", at: instant(90), originID: "phone")
        #expect(first.record(id: "isolation-note")?.version == 2)
        #expect(second.record(id: "isolation-note")?.version == 1)
        #expect(second.pendingChanges().changes.isEmpty)
    }
}

@Suite("Part 2 — Rich reconciliation outcomes")
struct Part2Reconciliation {
    @Test("identical records are unchanged and newer versions win on either side")
    func versionOutcomes() throws {
        let base = note("outcome-unchanged", version: 2)
        let unchangedStore = OfflineSyncStore(records: [base])
        #expect(unchangedStore.reconcile(remote: [base]) == [.unchanged(base)])

        var localStore = OfflineSyncStore(records: [note("outcome-local", version: 2)])
        let local = try localStore.edit(id: "outcome-local", title: "Local", at: instant(30), originID: "phone")
        let localOutcome = try #require(localStore.reconcile(remote: [note("outcome-local", version: 2)]).first)
        #expect(localOutcome.kind == .localWins)
        guard case let .localWins(context) = localOutcome else { return }
        #expect(context.local == local)
        #expect(context.baseline?.version == 2)

        let remoteStore = OfflineSyncStore(records: [note("outcome-remote", version: 2)])
        let remote = note("outcome-remote", version: 3, time: 20, origin: "server", body: "Remote")
        #expect(remoteStore.reconcile(remote: [remote]).first?.kind == .remoteWins)
    }

    @Test("timestamp then origin ID provide deterministic same-version tie-breaks")
    func deterministicTiebreak() {
        let local = note("tie-time", version: 4, time: 40, origin: "phone", title: "Local")
        let newerRemote = note("tie-time", version: 4, time: 41, origin: "server", title: "Remote")
        #expect(OfflineSyncStore(records: [local]).reconcile(remote: [newerRemote]).first?.kind == .remoteWins)

        let originLocal = note("tie-origin", version: 4, time: 40, origin: "alpha", title: "Local")
        let originRemote = note("tie-origin", version: 4, time: 40, origin: "omega", title: "Remote")
        #expect(OfflineSyncStore(records: [originLocal]).reconcile(remote: [originRemote]).first?.kind == .remoteWins)
    }

    @Test("equal ordering metadata with divergent content stays explicitly ambiguous")
    func ambiguousConflict() {
        let local = note("ambiguous-note", version: 5, time: 50, origin: "same-device", title: "Local")
        let remote = note("ambiguous-note", version: 5, time: 50, origin: "same-device", title: "Remote")
        let outcome = OfflineSyncStore(records: [local]).reconcile(remote: [remote]).first
        #expect(outcome?.kind == .conflicted)
    }

    @Test("remote-only records are classified and input order is normalized")
    func remoteOnlyAndOrdering() {
        let store = makeFreshStore()
        let outcomes = store.reconcile(remote: [note("remote-z"), note("remote-a")])
        #expect(outcomes.map(\.recordID) == ["remote-a", "remote-z"])
        #expect(outcomes.allSatisfy { $0.kind == .remoteWins })
    }
}

@Suite("Part 3 — Field merges and tombstones")
struct Part3Resolution {
    @Test("field merge keeps independent local and remote edits")
    func independentFields() throws {
        let base = note("merge-note", version: 2, title: "Plan", body: "Draft")
        var store = OfflineSyncStore(records: [base])
        _ = try store.edit(id: "merge-note", title: "Launch plan", at: instant(30), originID: "phone")
        let remote = note("merge-note", version: 4, time: 40, origin: "server", title: "Plan", body: "Approved")
        let outcomes = store.reconcile(remote: [remote])
        let applied = store.apply(outcomes, resolution: .mergeFields(prefer: .remote), at: instant(50), originID: "phone")
        #expect(applied.first?.reason == .fieldMerge)
        #expect(applied.first?.record == note("merge-note", version: 5, time: 50, origin: "phone", title: "Launch plan", body: "Approved"))
    }

    @Test("same-field divergence obeys the explicit merge preference")
    func preference() throws {
        let base = note("preference-note", version: 2, title: "Base")
        var store = OfflineSyncStore(records: [base])
        _ = try store.edit(id: "preference-note", title: "Local", at: instant(20), originID: "phone")
        let remote = note("preference-note", version: 4, time: 30, origin: "server", title: "Remote")
        let outcomes = store.reconcile(remote: [remote])
        _ = store.apply(outcomes, resolution: .mergeFields(prefer: .local), at: instant(40), originID: "phone")
        #expect(store.record(id: "preference-note")?.content == .note(.init(title: "Local", body: "Body")))
    }

    @Test("a tombstone beats a racing edit and records both origins")
    func tombstonePrecedence() throws {
        let base = note("deleted-note", version: 3)
        var store = OfflineSyncStore(records: [base])
        _ = try store.delete(id: "deleted-note", at: instant(40), originID: "phone")
        let remote = note("deleted-note", version: 5, time: 50, origin: "server", body: "Edited remotely")
        let outcomes = store.reconcile(remote: [remote])
        let applied = store.apply(outcomes, resolution: .mergeFields(prefer: .remote), at: instant(60), originID: "phone")
        #expect(applied.first?.reason == .tombstonePrecedence)
        #expect(applied.first?.record.content == .tombstone(reason: .tombstonePrecedence(deletedOriginID: "phone", editedOriginID: "server")))
        #expect(applied.first?.record.version == 6)
    }

    @Test("reapplying an outcome batch is idempotent")
    func idempotentApplication() throws {
        let base = note("idempotent-note", version: 2)
        var store = OfflineSyncStore(records: [base])
        _ = try store.edit(id: "idempotent-note", title: "Local", at: instant(20), originID: "phone")
        let outcomes = store.reconcile(remote: [note("idempotent-note", version: 4, time: 30, origin: "server", body: "Remote")])
        let first = store.apply(outcomes, resolution: .mergeFields(prefer: .local), at: instant(40), originID: "phone")
        let second = store.apply(outcomes, resolution: .mergeFields(prefer: .local), at: instant(40), originID: "phone")
        #expect(second == first)
        #expect(store.record(id: "idempotent-note") == first.first?.record)
    }

    @Test("fixture arrays and their value records are never mutated")
    func inputValueSemantics() {
        let fixture = [note("fixture-note", version: 2)]
        let original = fixture
        var store = OfflineSyncStore(records: fixture)
        let outcomes = store.reconcile(remote: fixture)
        _ = store.apply(outcomes, resolution: .acceptWinner, at: instant(100), originID: "phone")
        #expect(fixture == original)
    }
}
