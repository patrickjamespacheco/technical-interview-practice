import Testing
@testable import Problem70DepotChargerCapacitySizer

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// The worked day: one vehicle parked across the whole morning while three
/// short sessions come and go beside it.
private let v1 = ChargeSession(vehicleID: "v1", arrival: 0, departure: 30)
private let workedDay = [
    v1,
    ChargeSession(vehicleID: "v2", arrival: 5, departure: 10),
    ChargeSession(vehicleID: "v3", arrival: 15, departure: 20),
    ChargeSession(vehicleID: "v4", arrival: 25, departure: 40),
]

/// One vehicle leaves at the instant the next arrives, so the depot needs one
/// bay. A sweep that orders arrivals before departures at a shared instant
/// reports two.
private let handover = [
    ChargeSession(vehicleID: "b1", arrival: 0, departure: 30),
    ChargeSession(vehicleID: "b2", arrival: 30, departure: 60),
]

/// The whole fleet returns together, so every vehicle needs its own bay.
private let a1 = ChargeSession(vehicleID: "a1", arrival: 0, departure: 10)
private let a2 = ChargeSession(vehicleID: "a2", arrival: 0, departure: 10)
private let a3 = ChargeSession(vehicleID: "a3", arrival: 0, departure: 10)
private let allAtOnce = [a1, a2, a3]

/// Overlapping sessions that build to a single peak in the middle of the day.
private let staircase = [
    ChargeSession(vehicleID: "s1", arrival: 0, departure: 40),
    ChargeSession(vehicleID: "s2", arrival: 10, departure: 50),
    ChargeSession(vehicleID: "s3", arrival: 20, departure: 60),
]

/// Sessions that never meet, so one bay serves the entire day.
private let sequential = [
    ChargeSession(vehicleID: "q1", arrival: 0, departure: 5),
    ChargeSession(vehicleID: "q2", arrival: 20, departure: 25),
    ChargeSession(vehicleID: "q3", arrival: 40, departure: 45),
]

private let schedules: [[ChargeSession]] = [
    workedDay, handover, allAtOnce, staircase, sequential, [v1], [],
]

private func makeSizer() -> ChargerCapacitySizer {
    ChargerCapacitySizer()
}

/// Occupancy counted one minute at a time, written here so it cannot share the
/// sweep's bugs. Only usable because every fixture spans a handful of minutes.
private func bruteForcePeakOccupancy(_ sessions: [ChargeSession]) -> Int {
    guard let last = sessions.map(\.departure).max() else { return 0 }
    var peak = 0
    for minute in 0..<last {
        let parked = sessions.filter { $0.arrival <= minute && minute < $0.departure }.count
        peak = max(peak, parked)
    }
    return peak
}

private func sessionsOverlap(_ first: ChargeSession, _ second: ChargeSession) -> Bool {
    first.arrival < second.departure && second.arrival < first.departure
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Decompose into events")
struct ChargerCapacitySizerPart1Tests {
    @Test("every session becomes one arrival and one departure")
    func eventsPerSession() throws {
        let sizer = makeSizer()
        let timeline = try sizer.events(from: workedDay)

        try #require(timeline.count == 8)
        #expect(timeline.filter { if case .arrives = $0 { return true } else { return false } }.count == 4)
        #expect(timeline.filter { if case .departs = $0 { return true } else { return false } }.count == 4)
    }

    @Test("the worked day decomposes into one ordered timeline")
    func workedDayTimeline() throws {
        let sizer = makeSizer()
        let timeline = try sizer.events(from: workedDay)

        try #require(timeline.count == 8)
        #expect(timeline == [
            .arrives(vehicleID: "v1", at: 0),
            .arrives(vehicleID: "v2", at: 5),
            .departs(vehicleID: "v2", at: 10),
            .arrives(vehicleID: "v3", at: 15),
            .departs(vehicleID: "v3", at: 20),
            .arrives(vehicleID: "v4", at: 25),
            .departs(vehicleID: "v1", at: 30),
            .departs(vehicleID: "v4", at: 40),
        ])
    }

    @Test("a departure comes before an arrival at the same instant")
    func departuresComeFirst() throws {
        let sizer = makeSizer()
        let timeline = try sizer.events(from: handover)

        // Both events happen at 30. Ordering them the other way makes the
        // depot look like it needs a second bay it will never use.
        try #require(timeline.count == 4)
        #expect(timeline[1] == .departs(vehicleID: "b1", at: 30))
        #expect(timeline[2] == .arrives(vehicleID: "b2", at: 30))
    }

    @Test("events of the same kind at the same instant order by vehicle id")
    func sameKindTiesOrderByID() throws {
        let sizer = makeSizer()
        let timeline = try sizer.events(from: [a3, a1, a2])

        try #require(timeline.count == 6)
        #expect(timeline.prefix(3).map(\.vehicleID) == ["a1", "a2", "a3"])
        #expect(timeline.suffix(3).map(\.vehicleID) == ["a1", "a2", "a3"])
    }

    @Test("the timeline never steps backwards on any schedule")
    func timelineIsOrdered() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let timeline = try sizer.events(from: schedule)
            #expect(timeline.count == schedule.count * 2)
            for index in timeline.indices where index > 0 {
                #expect(timeline[index - 1].instant <= timeline[index].instant)
            }
        }
    }

    @Test("an empty schedule decomposes into no events rather than failing")
    func emptyScheduleDecomposes() throws {
        let sizer = makeSizer()

        #expect(try sizer.events(from: []) == [])
    }

    @Test("a session whose departure is not after its arrival is a typed failure")
    func invalidSessionFails() {
        let sizer = makeSizer()

        #expect(throws: DepotError.departureNotAfterArrival(vehicleID: "z1")) {
            try sizer.events(from: [ChargeSession(vehicleID: "z1", arrival: 10, departure: 10)])
        }
        #expect(throws: DepotError.departureNotAfterArrival(vehicleID: "z2")) {
            try sizer.events(from: [ChargeSession(vehicleID: "z2", arrival: 10, departure: 4)])
        }
    }

    @Test("a repeated vehicle id is a typed failure naming it")
    func duplicateVehicleFails() {
        let sizer = makeSizer()

        #expect(throws: DepotError.duplicateVehicleID("v1")) {
            try sizer.events(from: workedDay + [ChargeSession(vehicleID: "v1", arrival: 60, departure: 70)])
        }
    }

    @Test("a schedule larger than the supported session count is a typed failure")
    func tooManySessionsFails() {
        let sizer = makeSizer()
        let oversized = (0...ChargerCapacitySizer.maximumSessionCount).map {
            ChargeSession(vehicleID: "over-\($0)", arrival: $0, departure: $0 + 1)
        }

        #expect(throws: DepotError.tooManySessions(ChargerCapacitySizer.maximumSessionCount + 1)) {
            try sizer.events(from: oversized)
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Peak occupancy")
struct ChargerCapacitySizerPart2Tests {
    @Test("the worked day needs two bays")
    func workedDayNeedsTwoBays() throws {
        let sizer = makeSizer()

        #expect(try sizer.requiredBays(workedDay) == 2)
    }

    @Test("a handover at a shared instant needs one bay, not two")
    func handoverNeedsOneBay() throws {
        let sizer = makeSizer()

        // The whole tie rule shows up as a single number here.
        #expect(try sizer.requiredBays(handover) == 1)
    }

    @Test("a fleet returning together needs one bay each")
    func simultaneousArrivals() throws {
        let sizer = makeSizer()

        #expect(try sizer.requiredBays(allAtOnce) == 3)
        #expect(try sizer.requiredBays(staircase) == 3)
    }

    @Test("sessions that never meet share one bay")
    func sequentialSessions() throws {
        let sizer = makeSizer()

        #expect(try sizer.requiredBays(sequential) == 1)
    }

    @Test("an empty schedule needs no bays rather than failing")
    func emptyScheduleNeedsNoBays() throws {
        let sizer = makeSizer()

        #expect(try sizer.requiredBays([]) == 0)
    }

    @Test("the sweep agrees with counting occupancy one minute at a time")
    func sweepAgreesWithMinuteByMinuteCount() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            #expect(try sizer.requiredBays(schedule) == bruteForcePeakOccupancy(schedule))
        }
    }

    @Test("a malformed schedule is a typed failure here too")
    func malformedScheduleFails() {
        let sizer = makeSizer()

        #expect(throws: DepotError.departureNotAfterArrival(vehicleID: "z3")) {
            try sizer.requiredBays([ChargeSession(vehicleID: "z3", arrival: 5, departure: 5)])
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - When, and who")
struct ChargerCapacitySizerPart3Tests {
    @Test("the worked day is at its peak three separate times")
    func workedDayPeaks() throws {
        let sizer = makeSizer()
        let peaks = try sizer.peakWindows(workedDay)

        try #require(peaks.count == 3)
        #expect(peaks[0] == PeakWindow(start: 5, end: 10, occupancy: 2, vehicleIDs: ["v1", "v2"]))
        #expect(peaks[1] == PeakWindow(start: 15, end: 20, occupancy: 2, vehicleIDs: ["v1", "v3"]))
        #expect(peaks[2] == PeakWindow(start: 25, end: 30, occupancy: 2, vehicleIDs: ["v1", "v4"]))
    }

    @Test("stretches at the same occupancy stay separate when the fleet changes")
    func adjacentStretchesStaySeparate() throws {
        let sizer = makeSizer()
        let peaks = try sizer.peakWindows(handover)

        // Both stretches sit at one vehicle, but merging them would claim both
        // vehicles were parked together, which never happened.
        try #require(peaks.count == 2)
        #expect(peaks[0] == PeakWindow(start: 0, end: 30, occupancy: 1, vehicleIDs: ["b1"]))
        #expect(peaks[1] == PeakWindow(start: 30, end: 60, occupancy: 1, vehicleIDs: ["b2"]))
    }

    @Test("a single peak reports every vehicle parked during it")
    func singlePeakNamesItsFleet() throws {
        let sizer = makeSizer()
        let peaks = try sizer.peakWindows(staircase)

        try #require(peaks.count == 1)
        #expect(peaks[0] == PeakWindow(start: 20, end: 40, occupancy: 3, vehicleIDs: ["s1", "s2", "s3"]))
    }

    @Test("an empty schedule has no peak windows rather than failing")
    func emptyScheduleHasNoPeaks() throws {
        let sizer = makeSizer()

        #expect(try sizer.peakWindows([]) == [])
    }

    @Test("every reported window is a real stretch of time")
    func windowsAreNonEmptyAndOrdered() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let peaks = try sizer.peakWindows(schedule)
            #expect(peaks.allSatisfy { $0.end > $0.start })
            #expect(peaks.allSatisfy { $0.vehicleIDs == $0.vehicleIDs.sorted() })
            #expect(peaks.allSatisfy { $0.vehicleIDs.count == $0.occupancy })
            for index in peaks.indices where index > 0 {
                #expect(peaks[index - 1].end <= peaks[index].start)
            }
        }
    }

    @Test("every window sits at the occupancy the depot must build for")
    func windowsSitAtThePeak() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let required = try sizer.requiredBays(schedule)
            let peaks = try sizer.peakWindows(schedule)
            #expect(peaks.allSatisfy { $0.occupancy == required })
            #expect(peaks.isEmpty == (required == 0))
        }
    }

    @Test("every vehicle a window names is genuinely parked throughout it")
    func namedVehiclesAreParked() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let byID = Dictionary(uniqueKeysWithValues: schedule.map { ($0.vehicleID, $0) })
            for window in try sizer.peakWindows(schedule) {
                for vehicleID in window.vehicleIDs {
                    let session = try #require(byID[vehicleID])
                    #expect(session.arrival <= window.start && window.end <= session.departure)
                }
                let parked = schedule.filter { $0.arrival <= window.start && window.start < $0.departure }
                #expect(Set(parked.map(\.vehicleID)) == Set(window.vehicleIDs))
            }
        }
    }

    @Test("a malformed schedule is a typed failure here too")
    func malformedScheduleFails() {
        let sizer = makeSizer()

        #expect(throws: DepotError.duplicateVehicleID("s1")) {
            try sizer.peakWindows(staircase + [ChargeSession(vehicleID: "s1", arrival: 90, departure: 95)])
        }
    }
}

// ── Part 4 ───────────────────────────────────────────────────────────────────

@Suite("Part 4 - Assign a bay to every session")
struct ChargerCapacitySizerPart4Tests {
    @Test("the worked day sends one vehicle to bay zero and reuses bay one")
    func workedDayAssignment() throws {
        let sizer = makeSizer()
        let assignment = try sizer.bayAssignment(workedDay)

        #expect(assignment == ["v1": 0, "v2": 1, "v3": 1, "v4": 1])
    }

    @Test("a handover reuses the bay the departing vehicle just left")
    func handoverReusesTheBay() throws {
        let sizer = makeSizer()

        #expect(try sizer.bayAssignment(handover) == ["b1": 0, "b2": 0])
        #expect(try sizer.bayAssignment(sequential) == ["q1": 0, "q2": 0, "q3": 0])
    }

    @Test("a fleet returning together fills consecutive bays from zero")
    func simultaneousArrivalsFillBays() throws {
        let sizer = makeSizer()

        #expect(try sizer.bayAssignment(allAtOnce) == ["a1": 0, "a2": 1, "a3": 2])
    }

    @Test("an empty schedule assigns nothing rather than failing")
    func emptyScheduleAssignsNothing() throws {
        let sizer = makeSizer()

        #expect(try sizer.bayAssignment([]) == [:])
    }

    @Test("every vehicle gets exactly one bay, numbered from zero")
    func everyVehicleIsAssigned() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let assignment = try sizer.bayAssignment(schedule)
            let required = try sizer.requiredBays(schedule)

            #expect(Set(assignment.keys) == Set(schedule.map(\.vehicleID)))
            #expect(assignment.values.allSatisfy { 0 <= $0 && $0 < required })
        }
    }

    @Test("the assignment uses exactly as many bays as the depot must build")
    func assignmentUsesTheRequiredBayCount() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let assignment = try sizer.bayAssignment(schedule)
            #expect(Set(assignment.values).count == (try sizer.requiredBays(schedule)))
        }
    }

    @Test("no two vehicles sharing a bay are ever parked at the same time")
    func sharedBaysNeverDoubleBook() throws {
        let sizer = makeSizer()
        for schedule in schedules {
            let assignment = try sizer.bayAssignment(schedule)
            for first in schedule {
                for second in schedule where first.vehicleID < second.vehicleID {
                    guard assignment[first.vehicleID] == assignment[second.vehicleID] else { continue }
                    // Using the right number of bays and double-booking one is
                    // exactly what deriving this from the counter produces, so
                    // both properties are checked separately.
                    #expect(!sessionsOverlap(first, second))
                }
            }
        }
    }

    @Test("a malformed schedule is a typed failure here too")
    func malformedScheduleFails() {
        let sizer = makeSizer()

        #expect(throws: DepotError.departureNotAfterArrival(vehicleID: "z4")) {
            try sizer.bayAssignment([ChargeSession(vehicleID: "z4", arrival: 9, departure: 2)])
        }
        #expect(throws: DepotError.duplicateVehicleID("q2")) {
            try sizer.bayAssignment(sequential + [ChargeSession(vehicleID: "q2", arrival: 80, departure: 90)])
        }
    }

    @Test("sizers are independent and never mutate the schedule they are given")
    func sizersAreIndependentAndNonMutating() throws {
        let busy = makeSizer()
        let fresh = makeSizer()

        var schedule = workedDay
        let original = schedule

        for _ in 0..<5 {
            _ = try busy.bayAssignment(schedule)
            _ = try busy.peakWindows(staircase)
            _ = try busy.requiredBays(allAtOnce)
        }

        // A second sizer still reports the documented answers, which is what a
        // sweep result cached in static storage would break.
        #expect(try fresh.requiredBays(workedDay) == 2)
        #expect(try fresh.bayAssignment(workedDay) == ["v1": 0, "v2": 1, "v3": 1, "v4": 1])

        // The busy sizer answers two different schedules independently.
        #expect(try busy.requiredBays(handover) == 1)
        #expect(try busy.requiredBays(allAtOnce) == 3)
        #expect(try busy.requiredBays(handover) == 1)

        // The caller's schedule is untouched, and a caller emptying its own
        // copy changes nothing about a later call.
        #expect(schedule == original)
        schedule.removeAll()
        #expect(try fresh.requiredBays(original) == 2)
    }
}
