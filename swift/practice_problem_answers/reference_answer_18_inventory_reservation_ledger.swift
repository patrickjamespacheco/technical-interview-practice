import Foundation

public struct InventorySnapshot: Equatable, Sendable {
    public let sku: String
    public let onHand: Int
    public let reserved: Int
    public let available: Int

    public init(sku: String, onHand: Int, reserved: Int, available: Int) {
        self.sku = sku
        self.onHand = onHand
        self.reserved = reserved
        self.available = available
    }
}

public enum InventoryError: Error, Equatable, Sendable {
    case invalidQuantity(Int)
    case unknownSKU(String)
    case insufficientAvailable(sku: String, requested: Int, available: Int)
    case duplicateReservationID(String)
    case unknownReservation(String)
    case reservationNotActive(String)
    case duplicateOrderID(String)
    case emptyOrder
    case notImplemented
}

public enum ReservationState: Equatable, Sendable {
    case active
    case released
    case expired
    case committed(orderID: String)
}

public struct Reservation: Equatable, Sendable {
    public let id: String
    public let idempotencyKey: String
    public let sku: String
    public let quantity: Int
    public let expiresAt: Date
    public let state: ReservationState

    public init(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date, state: ReservationState = .active) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.sku = sku
        self.quantity = quantity
        self.expiresAt = expiresAt
        self.state = state
    }
}

public struct CommittedOrder: Equatable, Sendable {
    public let id: String
    public let reservationIDs: [String]

    public init(id: String, reservationIDs: [String]) {
        self.id = id
        self.reservationIDs = reservationIDs
    }
}

public actor InventoryReservationLedger {
    private var onHand: [String: Int]
    private var reservations: [String: Reservation] = [:]
    private var reservationIDsByKey: [String: String] = [:]
    private var orders: [String: CommittedOrder] = [:]

    public init(initialStock: [String: Int] = [:]) { self.onHand = initialStock }

    // MARK: Part 1 — typed stock and availability

    public func snapshot(for sku: String) -> Result<InventorySnapshot, InventoryError> {
        guard let stock = onHand[sku] else { return .failure(.unknownSKU(sku)) }
        // `reserved` is derived from the reservations themselves, so there is no
        // counter that can drift out of step with them.
        let reserved = reservations.values
            .filter { $0.sku == sku && $0.state == .active }
            .reduce(0) { $0 + $1.quantity }
        return .success(InventorySnapshot(sku: sku, onHand: stock, reserved: reserved, available: stock - reserved))
    }

    public func availability(for sku: String, quantity: Int) -> Result<InventorySnapshot, InventoryError> {
        guard quantity > 0 else { return .failure(.invalidQuantity(quantity)) }
        return snapshot(for: sku).flatMap { snapshot in
            guard snapshot.available >= quantity else {
                return .failure(.insufficientAvailable(sku: sku, requested: quantity, available: snapshot.available))
            }
            return .success(snapshot)
        }
    }

    public func adjustStock(sku: String, by quantity: Int) -> Result<InventorySnapshot, InventoryError> {
        guard onHand[sku] != nil else { return .failure(.unknownSKU(sku)) }
        guard quantity != 0 else { return .failure(.invalidQuantity(quantity)) }
        if quantity < 0 {
            // Removing stock may only take from what nobody has reserved.
            if case let .failure(error) = availability(for: sku, quantity: -quantity) { return .failure(error) }
        }
        onHand[sku]! += quantity
        return snapshot(for: sku)
    }

    // MARK: Part 2 — idempotent concurrent reservations

    public func reservation(id: String) -> Result<Reservation, InventoryError> {
        guard let reservation = reservations[id] else { return .failure(.unknownReservation(id)) }
        return .success(reservation)
    }

    public func reserve(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date) -> Result<Reservation, InventoryError> {
        // A replayed key returns its original outcome; the other arguments of the
        // replay are deliberately ignored.
        if let existingID = reservationIDsByKey[idempotencyKey] { return reservation(id: existingID) }
        guard reservations[id] == nil else { return .failure(.duplicateReservationID(id)) }
        return availability(for: sku, quantity: quantity).map { _ in
            let reservation = Reservation(id: id, idempotencyKey: idempotencyKey, sku: sku, quantity: quantity, expiresAt: expiresAt)
            // Actor isolation makes check-then-record atomic: no suspension point
            // sits between the availability check and this write, so a task group
            // cannot oversell.
            reservations[id] = reservation
            reservationIDsByKey[idempotencyKey] = id
            return reservation
        }
    }

    public func release(reservationID: String) -> Result<Reservation, InventoryError> {
        finish(reservationID, as: .released)
    }

    /// The single place a reservation leaves the active set. Release, expiry, and
    /// commit differ only in the terminal state they record.
    private func finish(_ reservationID: String, as state: ReservationState) -> Result<Reservation, InventoryError> {
        reservation(id: reservationID).flatMap { reservation in
            guard reservation.state == .active else { return .failure(.reservationNotActive(reservationID)) }
            let finished = Reservation(
                id: reservation.id,
                idempotencyKey: reservation.idempotencyKey,
                sku: reservation.sku,
                quantity: reservation.quantity,
                expiresAt: reservation.expiresAt,
                state: state
            )
            reservations[reservationID] = finished
            return .success(finished)
        }
    }

    // MARK: Part 3 — expiry and atomic commits

    public func expireReservations(at instant: Date) -> [Reservation] {
        let due = reservations.values
            .filter { $0.state == .active && $0.expiresAt <= instant }
            .map(\.id)
            .sorted()
        return due.compactMap { finish($0, as: .expired).successValue }
    }

    public func commit(orderID: String, reservationIDs: [String]) -> Result<CommittedOrder, InventoryError> {
        guard orders[orderID] == nil else { return .failure(.duplicateOrderID(orderID)) }
        guard !reservationIDs.isEmpty else { return .failure(.emptyOrder) }
        // Validate the whole order before touching any stock, so a bad ID leaves
        // every reservation exactly as it was.
        var validated: [Reservation] = []
        for reservationID in reservationIDs {
            switch reservation(id: reservationID) {
            case let .failure(error): return .failure(error)
            case let .success(reservation):
                guard reservation.state == .active else { return .failure(.reservationNotActive(reservationID)) }
                validated.append(reservation)
            }
        }
        for reservation in validated {
            onHand[reservation.sku]! -= reservation.quantity
            _ = finish(reservation.id, as: .committed(orderID: orderID))
        }
        let order = CommittedOrder(id: orderID, reservationIDs: reservationIDs)
        orders[orderID] = order
        return .success(order)
    }
}

private extension Result {
    var successValue: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}
