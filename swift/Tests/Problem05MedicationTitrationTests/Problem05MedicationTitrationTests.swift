import Foundation
import Testing
@testable import Problem05MedicationTitration

private func dose(_ value: Decimal) -> Dose { Dose(milligrams: value) }
private func event(_ patient: PatientID, _ medication: MedicationID, _ direction: TitrationDirection, _ amount: Decimal, _ time: Int) -> MedicationEvent {
    MedicationEvent(patientID: patient, medicationID: medication, direction: direction, dose: dose(amount), timestamp: MedicationTimestamp(time))
}
private let seededEvents: [MedicationEvent] = [
    event("maria", "metformin", .stop, 0, 40), event("maria", "metformin", .start, 500, 10), event("maria", "metformin", .increase, 1000, 20), event("maria", "metformin", .decrease, 500, 30),
    event("maria", "glipizide", .start, 5, 10), event("maria", "glipizide", .decrease, 2.5, 35),
    event("james", "metformin", .start, 500, 10), event("james", "metformin", .increase, 1000, 20),
    event("susan", "metformin", .start, 500, 10), event("susan", "metformin", .stop, 0, 20)
]
private func makeFreshTracker() -> TitrationTracker { TitrationTracker() }
private func makeSeededTracker() -> TitrationTracker { TitrationTracker(events: seededEvents) }

@Suite("Part 1 — Patient medication snapshots")
struct MedicationPart1 {
    @Test("history is chronological despite arrival order")
    func history() {
        let tracker = makeSeededTracker()
        #expect(tracker.medicationHistory(for: "maria", medicationID: "metformin").map(\.timestamp) == [MedicationTimestamp(10), MedicationTimestamp(20), MedicationTimestamp(30), MedicationTimestamp(40)])
        #expect(tracker.medicationHistory(for: "unknown-history", medicationID: "metformin") == [])
    }
    @Test("snapshots include active latest dose and total changes")
    func snapshots() {
        let medications = makeSeededTracker().currentMedications(for: "maria")
        #expect(medications == [MedicationSnapshot(medicationID: "glipizide", dose: dose(2.5), lastChanged: MedicationTimestamp(35), totalChanges: 2)])
        #expect(makeSeededTracker().currentMedications(for: "susan") == [])
    }
    @Test("trackers own independent immutable event values")
    func isolation() {
        let original = makeFreshTracker()
        let updated = original.adding(event("patient-isolation", "med-isolation", .start, 10, 1))
        #expect(original.currentMedications(for: "patient-isolation") == [])
        #expect(updated.currentMedications(for: "patient-isolation").count == 1)
    }
}

@Suite("Part 2 — Patient-level reductions")
struct MedicationPart2 {
    @Test("counts reuse typed histories with an optional direction")
    func counts() {
        let tracker = makeSeededTracker()
        #expect(tracker.titrationCount(for: "maria", medicationID: "metformin") == 4)
        #expect(tracker.titrationCount(for: "maria", medicationID: "metformin", direction: .decrease) == 1)
        #expect(tracker.titrationCount(for: "unknown-count", medicationID: "metformin") == 0)
    }
    @Test("de-escalation includes only decrease and stop events")
    func deEscalation() {
        let summary = makeSeededTracker().deEscalationSummary(for: "maria")
        #expect(summary == ["metformin": 2, "glipizide": 1])
        #expect(makeSeededTracker().deEscalationSummary(for: "unknown-summary") == [:])
    }
}

@Suite("Part 3 — Population-level reductions")
struct MedicationPart3 {
    @Test("active patient IDs are unique and sorted")
    func activePatients() {
        let tracker = makeSeededTracker().adding(event("anna-population", "metformin", .start, 250, 5)).adding(event("zoe-population", "metformin", .start, 250, 5))
        #expect(tracker.patients(on: "metformin") == ["anna-population", "james", "zoe-population"])
        #expect(tracker.patients(on: "unknown-medication") == [])
    }
    @Test("most titrated medications sort by count then typed ID")
    func ranking() {
        let ranking = makeSeededTracker().mostTitratedMedications(limit: 2)
        #expect(ranking == [MedicationCount(medicationID: "metformin", count: 8), MedicationCount(medicationID: "glipizide", count: 2)])
        #expect(makeSeededTracker().mostTitratedMedications(limit: 0) == [])
    }
}

@Suite("Part 4 — Immutable event ingestion")
struct MedicationPart4 {
    @Test("adding returns a new tracker and updates reductions")
    func ingestion() {
        let original = makeSeededTracker()
        let updated = original.adding(event("james", "metformin", .stop, 0, 50))
        #expect(original.patients(on: "metformin") == ["james"])
        #expect(updated.patients(on: "metformin") == [])
    }
    @Test("same identity and timestamp uses last-write-wins replacement")
    func replacement() {
        let updated = makeSeededTracker().adding(event("james", "metformin", .stop, 0, 20))
        let history = updated.medicationHistory(for: "james", medicationID: "metformin")
        #expect(history.count == 2)
        #expect(history.last?.direction == .stop)
        #expect(updated.currentMedications(for: "james") == [])
    }
}
