import Foundation

public struct PatientID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String; public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct MedicationID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String; public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct MedicationTimestamp: Hashable, Comparable, Sendable {
    public let rawValue: Int; public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct Dose: Equatable, Sendable {
    public let milligrams: Decimal
    public init(milligrams: Decimal) { self.milligrams = milligrams }
    public static let zero = Dose(milligrams: 0)
}
public enum TitrationDirection: Equatable, Sendable { case start, increase, decrease, stop }
public struct MedicationEvent: Equatable, Sendable {
    public let patientID: PatientID; public let medicationID: MedicationID
    public let direction: TitrationDirection; public let dose: Dose; public let timestamp: MedicationTimestamp
    public init(patientID: PatientID, medicationID: MedicationID, direction: TitrationDirection, dose: Dose, timestamp: MedicationTimestamp) {
        self.patientID = patientID; self.medicationID = medicationID; self.direction = direction; self.dose = dose; self.timestamp = timestamp
    }
}
public struct MedicationSnapshot: Equatable, Sendable {
    public let medicationID: MedicationID; public let dose: Dose
    public let lastChanged: MedicationTimestamp; public let totalChanges: Int
}
public struct MedicationCount: Equatable, Sendable {
    public let medicationID: MedicationID; public let count: Int
}
public struct TitrationTracker: Sendable {
    public init(events: [MedicationEvent] = []) { self.events = events }
    private let events: [MedicationEvent]

    // MARK: Part 1 — patient medication snapshots

    /// The single ordering authority. Every later reduction reads through this.
    public func medicationHistory(for patientID: PatientID, medicationID: MedicationID) -> [MedicationEvent] {
        events
            .filter { $0.patientID == patientID && $0.medicationID == medicationID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func currentMedications(for patientID: PatientID) -> [MedicationSnapshot] {
        medicationIDs(for: patientID)
            .compactMap { snapshot(for: patientID, medicationID: $0) }
            .sorted { $0.medicationID < $1.medicationID }
    }

    /// A medication is active when its most recent event is not a stop.
    private func snapshot(for patientID: PatientID, medicationID: MedicationID) -> MedicationSnapshot? {
        let history = medicationHistory(for: patientID, medicationID: medicationID)
        guard let latest = history.last, latest.direction != .stop else { return nil }
        return MedicationSnapshot(
            medicationID: medicationID,
            dose: latest.dose,
            lastChanged: latest.timestamp,
            totalChanges: history.count
        )
    }

    private func medicationIDs(for patientID: PatientID) -> [MedicationID] {
        Set(events.filter { $0.patientID == patientID }.map(\.medicationID)).sorted()
    }

    // MARK: Part 2 — patient-level reductions

    public func titrationCount(for patientID: PatientID, medicationID: MedicationID, direction: TitrationDirection? = nil) -> Int {
        let history = medicationHistory(for: patientID, medicationID: medicationID)
        guard let direction else { return history.count }
        return history.filter { $0.direction == direction }.count
    }

    public func deEscalationSummary(for patientID: PatientID) -> [MedicationID: Int] {
        medicationIDs(for: patientID).reduce(into: [:]) { summary, medicationID in
            let decreases = titrationCount(for: patientID, medicationID: medicationID, direction: .decrease)
            let stops = titrationCount(for: patientID, medicationID: medicationID, direction: .stop)
            if decreases + stops > 0 { summary[medicationID] = decreases + stops }
        }
    }

    // MARK: Part 3 — population-level reductions

    public func patients(on medicationID: MedicationID) -> [PatientID] {
        Set(events.map(\.patientID))
            .filter { patient in currentMedications(for: patient).contains { $0.medicationID == medicationID } }
            .sorted()
    }

    public func mostTitratedMedications(limit: Int = 3) -> [MedicationCount] {
        let counts = events.reduce(into: [MedicationID: Int]()) { totals, event in
            totals[event.medicationID, default: 0] += 1
        }
        let ranked = counts
            .map { MedicationCount(medicationID: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.medicationID < rhs.medicationID : lhs.count > rhs.count
            }
        return Array(ranked.prefix(max(0, limit)))
    }

    // MARK: Part 4 — immutable event ingestion

    public func adding(_ event: MedicationEvent) -> TitrationTracker {
        // Last write wins for the same patient, medication, and instant.
        let retained = events.filter {
            !($0.patientID == event.patientID && $0.medicationID == event.medicationID && $0.timestamp == event.timestamp)
        }
        return TitrationTracker(events: retained + [event])
    }
}
