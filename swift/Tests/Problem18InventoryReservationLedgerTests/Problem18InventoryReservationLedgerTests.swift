import Foundation
import Testing
@testable import Problem18InventoryReservationLedger

private let expiry = Date(timeIntervalSince1970: 1_000)
private func makeFreshLedger() -> InventoryReservationLedger { InventoryReservationLedger() }
private func makeSeededLedger() -> InventoryReservationLedger { InventoryReservationLedger(initialStock: ["camera": 5, "lens": 3]) }
private extension Result {
    var successValue: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}

@Suite("Part 1 — Typed stock and availability")
struct Part1Inventory {
    @Test("snapshots and adjustments return typed values")
    func adjustments() async {
        let ledger = makeSeededLedger()
        #expect(await ledger.snapshot(for: "camera") == .success(.init(sku: "camera", onHand: 5, reserved: 0, available: 5)))
        #expect(await ledger.adjustStock(sku: "camera", by: 2) == .success(.init(sku: "camera", onHand: 7, reserved: 0, available: 7)))
        #expect(await ledger.adjustStock(sku: "camera", by: -3) == .success(.init(sku: "camera", onHand: 4, reserved: 0, available: 4)))
        #expect(await ledger.availability(for: "camera", quantity: 4) == .success(.init(sku: "camera", onHand: 4, reserved: 0, available: 4)))
    }

    @Test("invalid, unknown, and insufficient operations use associated-value errors")
    func errors() async {
        let ledger = makeSeededLedger()
        #expect(await ledger.availability(for: "camera", quantity: 0) == .failure(.invalidQuantity(0)))
        #expect(await ledger.adjustStock(sku: "ghost_adjustment", by: 1) == .failure(.unknownSKU("ghost_adjustment")))
        #expect(await ledger.adjustStock(sku: "lens", by: -4) == .failure(.insufficientAvailable(sku: "lens", requested: 4, available: 3)))
        #expect(await ledger.availability(for: "lens", quantity: 4) == .failure(.insufficientAvailable(sku: "lens", requested: 4, available: 3)))
    }

    @Test("ledger instances own independent stock")
    func isolation() async {
        let first = InventoryReservationLedger(initialStock: ["isolation_sku": 2])
        let second = InventoryReservationLedger(initialStock: ["isolation_sku": 2])
        _ = await first.adjustStock(sku: "isolation_sku", by: 3)
        #expect(await first.snapshot(for: "isolation_sku").successValue?.onHand == 5)
        #expect(await second.snapshot(for: "isolation_sku").successValue?.onHand == 2)
    }
}

@Suite("Part 2 — Idempotent concurrent reservations")
struct Part2Reservations {
    @Test("an idempotency-key replay returns the original reservation")
    func replay() async {
        let ledger = makeSeededLedger()
        let first = await ledger.reserve(id: "res_replay_original", idempotencyKey: "key_replay", sku: "camera", quantity: 2, expiresAt: expiry)
        let replay = await ledger.reserve(id: "res_replay_ignored", idempotencyKey: "key_replay", sku: "lens", quantity: 99, expiresAt: .distantFuture)
        #expect(replay == first)
        #expect(await ledger.snapshot(for: "camera").successValue?.reserved == 2)
        #expect(await ledger.snapshot(for: "lens").successValue?.reserved == 0)
    }

    @Test("reservation IDs are unique and release restores availability")
    func release() async {
        let ledger = makeSeededLedger()
        _ = await ledger.reserve(id: "res_release_test", idempotencyKey: "key_release", sku: "lens", quantity: 2, expiresAt: expiry)
        #expect(await ledger.reserve(id: "res_release_test", idempotencyKey: "different_key", sku: "lens", quantity: 1, expiresAt: expiry) == .failure(.duplicateReservationID("res_release_test")))
        #expect(await ledger.reservation(id: "res_release_test").successValue?.state == .active)
        #expect(await ledger.release(reservationID: "res_release_test").successValue?.state == .released)
        #expect(await ledger.snapshot(for: "lens").successValue?.available == 3)
        #expect(await ledger.release(reservationID: "res_release_test") == .failure(.reservationNotActive("res_release_test")))
    }

    @Test("a task group cannot oversell one SKU")
    func concurrentOversell() async {
        let ledger = InventoryReservationLedger(initialStock: ["camera": 2])
        let successes = await withTaskGroup(of: Result<Reservation, InventoryError>.self, returning: [Reservation].self) { group in
            for number in 1...12 {
                group.addTask {
                    await ledger.reserve(id: "res_concurrent_\(number)", idempotencyKey: "key_concurrent_\(number)", sku: "camera", quantity: 2, expiresAt: expiry)
                }
            }
            var reservations: [Reservation] = []
            for await result in group { if case let .success(value) = result { reservations.append(value) } }
            return reservations
        }
        #expect(successes.count == 1)
        #expect(await ledger.snapshot(for: "camera") == .success(.init(sku: "camera", onHand: 2, reserved: 2, available: 0)))
    }
}

@Suite("Part 3 — Expiry and atomic commits")
struct Part3Completion {
    @Test("expiry uses the injected instant and releases only eligible reservations")
    func deterministicExpiry() async {
        let ledger = makeSeededLedger()
        _ = await ledger.reserve(id: "res_expire_now", idempotencyKey: "key_expire_now", sku: "camera", quantity: 2, expiresAt: expiry)
        _ = await ledger.reserve(id: "res_expire_later", idempotencyKey: "key_expire_later", sku: "camera", quantity: 1, expiresAt: expiry.addingTimeInterval(1))
        let expired = await ledger.expireReservations(at: expiry)
        #expect(expired.map(\.id) == ["res_expire_now"])
        #expect(expired.first?.state == .expired)
        #expect(await ledger.snapshot(for: "camera").successValue?.available == 4)
    }

    @Test("commit is atomic and permanently consumes stock")
    func commit() async {
        let ledger = makeSeededLedger()
        _ = await ledger.reserve(id: "res_commit_camera", idempotencyKey: "key_commit_camera", sku: "camera", quantity: 2, expiresAt: expiry)
        _ = await ledger.reserve(id: "res_commit_lens", idempotencyKey: "key_commit_lens", sku: "lens", quantity: 1, expiresAt: expiry)
        #expect(await ledger.commit(orderID: "order_atomic", reservationIDs: ["res_commit_camera", "missing_commit"]) == .failure(.unknownReservation("missing_commit")))
        #expect(await ledger.reservation(id: "res_commit_camera").successValue?.state == .active)
        #expect(await ledger.commit(orderID: "order_atomic", reservationIDs: ["res_commit_camera", "res_commit_lens"]) == .success(.init(id: "order_atomic", reservationIDs: ["res_commit_camera", "res_commit_lens"])))
        #expect(await ledger.snapshot(for: "camera") == .success(.init(sku: "camera", onHand: 3, reserved: 0, available: 3)))
        #expect(await ledger.snapshot(for: "lens") == .success(.init(sku: "lens", onHand: 2, reserved: 0, available: 2)))
        #expect(await ledger.commit(orderID: "order_atomic", reservationIDs: ["res_commit_camera"]) == .failure(.duplicateOrderID("order_atomic")))
    }

    @Test("concurrent expiry and commit have one coherent winner")
    func race() async {
        let ledger = InventoryReservationLedger(initialStock: ["camera": 2])
        _ = await ledger.reserve(id: "res_race", idempotencyKey: "key_race", sku: "camera", quantity: 2, expiresAt: expiry)
        async let expired = ledger.expireReservations(at: expiry)
        async let committed = ledger.commit(orderID: "order_race", reservationIDs: ["res_race"])
        let (expiredResult, commitResult) = await (expired, committed)
        let expiryWon = expiredResult.count == 1
        let commitWon = commitResult == .success(.init(id: "order_race", reservationIDs: ["res_race"] ))
        #expect(expiryWon != commitWon)
        let snapshot = await ledger.snapshot(for: "camera").successValue
        #expect(snapshot?.reserved == 0)
        #expect(snapshot?.available == (expiryWon ? 2 : 0))
    }
}
