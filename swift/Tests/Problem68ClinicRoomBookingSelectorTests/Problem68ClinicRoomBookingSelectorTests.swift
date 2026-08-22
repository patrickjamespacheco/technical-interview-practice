import Testing
@testable import Problem68ClinicRoomBookingSelector

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// The worked day: four requests for one procedure room, in minutes from
/// midnight. b1 releases the room exactly as b3 wants it.
private let b1 = Booking(id: "b1", start: 540, end: 600)
private let b2 = Booking(id: "b2", start: 560, end: 640)
private let b3 = Booking(id: "b3", start: 600, end: 660)
private let b4 = Booking(id: "b4", start: 630, end: 700)
private let workedDay = [b1, b2, b3, b4]

/// Sorting by start time takes the long request first and hosts one booking
/// where two fit. Two requests can never separate the keys, because any two
/// that overlap admit exactly one; it takes three.
private let startKeyTrap = [
    Booking(id: "s1", start: 0, end: 100),
    Booking(id: "s2", start: 10, end: 20),
    Booking(id: "s3", start: 30, end: 40),
]

/// Sorting by shortest duration takes the middle request, which collides with
/// both of the others.
private let durationKeyTrap = [
    Booking(id: "d1", start: 0, end: 10),
    Booking(id: "d2", start: 9, end: 12),
    Booking(id: "d3", start: 11, end: 20),
]

/// Two requests releasing the room at the same minute, handed over out of id
/// order so an unstable or missing tie-break shows up.
private let tiedFinishes = [
    Booking(id: "t2", start: 5, end: 20),
    Booking(id: "t1", start: 0, end: 20),
    Booking(id: "t3", start: 20, end: 30),
]

/// Three requests that meet at their boundaries, which under the half-open
/// convention all fit.
private let backToBack = [
    Booking(id: "c1", start: 0, end: 10),
    Booking(id: "c2", start: 10, end: 20),
    Booking(id: "c3", start: 20, end: 30),
]

/// Each request contains the next, so only the innermost is hosted.
private let nested = [
    Booking(id: "n1", start: 0, end: 50),
    Booking(id: "n2", start: 5, end: 45),
    Booking(id: "n3", start: 10, end: 40),
]

private let days: [[Booking]] = [
    workedDay, startKeyTrap, durationKeyTrap, tiedFinishes, backToBack, nested, [b1], [],
]

private func makeSelector() -> RoomBookingSelector {
    RoomBookingSelector()
}

/// An exhaustive search over every subset, written here so it cannot share the
/// sweep's bugs. Only used on fixtures small enough to enumerate.
private func bruteForceMaximumCompatible(_ bookings: [Booking]) -> Int {
    precondition(bookings.count <= 12, "exhaustive search is for small fixtures only")
    var best = 0
    for mask in 0..<(1 << bookings.count) {
        var chosen: [Booking] = []
        for index in bookings.indices where mask & (1 << index) != 0 {
            chosen.append(bookings[index])
        }
        let compatible = chosen.allSatisfy { first in
            chosen.allSatisfy { second in
                first.id == second.id || !(first.start < second.end && second.start < first.end)
            }
        }
        if compatible {
            best = max(best, chosen.count)
        }
    }
    return best
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Validate and order")
struct RoomBookingSelectorPart1Tests {
    @Test("requests that share a minute overlap")
    func overlappingRequests() {
        let selector = makeSelector()

        #expect(selector.overlaps(b1, b2))
        #expect(selector.overlaps(b2, b1))
        #expect(selector.overlaps(b2, b3))
    }

    @Test("a request beginning as the room is released does not overlap it")
    func halfOpenBoundary() {
        let selector = makeSelector()

        // b1 runs to 600 and b3 begins at 600. Under the half-open convention
        // they share no minute, so the room can host both.
        #expect(!selector.overlaps(b1, b3))
        #expect(!selector.overlaps(b3, b1))
        #expect(!selector.overlaps(b1, b4))
    }

    @Test("a request that contains another overlaps it")
    func containedRequestsOverlap() {
        let selector = makeSelector()

        #expect(selector.overlaps(Booking(id: "outer", start: 0, end: 50), Booking(id: "inner", start: 10, end: 20)))
        #expect(selector.overlaps(Booking(id: "inner", start: 10, end: 20), Booking(id: "outer", start: 0, end: 50)))
    }

    @Test("the worked day orders by the minute the room is released")
    func workedDayOrdering() throws {
        let selector = makeSelector()
        let ordered = try selector.orderedByFinish(workedDay)

        try #require(ordered.count == 4)
        #expect(ordered.map(\.id) == ["b1", "b2", "b3", "b4"])
    }

    @Test("requests releasing the room at the same minute order by id")
    func tiesOrderByID() throws {
        let selector = makeSelector()
        let ordered = try selector.orderedByFinish(tiedFinishes)

        // Handed over as t2, t1, t3. Without an explicit tie-break the first
        // two come back in whichever order the sort happened to leave them.
        try #require(ordered.count == 3)
        #expect(ordered.map(\.id) == ["t1", "t2", "t3"])
    }

    @Test("the ordering is a permutation of the input on every fixture")
    func orderingIsAPermutation() throws {
        let selector = makeSelector()
        for day in days {
            let ordered = try selector.orderedByFinish(day)
            #expect(ordered.count == day.count)
            #expect(Set(ordered.map(\.id)) == Set(day.map(\.id)))
            for index in ordered.indices where index > 0 {
                #expect(ordered[index - 1].end <= ordered[index].end)
            }
        }
    }

    @Test("an empty day orders to an empty list rather than failing")
    func emptyDayOrders() throws {
        let selector = makeSelector()

        #expect(try selector.orderedByFinish([]) == [])
    }

    @Test("a request whose end is not after its start is a typed failure naming it")
    func invalidRequestFails() {
        let selector = makeSelector()

        #expect(throws: BookingError.endNotAfterStart(id: "z1")) {
            try selector.orderedByFinish([b1, Booking(id: "z1", start: 700, end: 700)])
        }
        #expect(throws: BookingError.endNotAfterStart(id: "z2")) {
            try selector.orderedByFinish([Booking(id: "z2", start: 700, end: 640)])
        }
    }

    @Test("a repeated request id is a typed failure naming it")
    func duplicateIDFails() {
        let selector = makeSelector()

        #expect(throws: BookingError.duplicateBookingID("b1")) {
            try selector.orderedByFinish([b1, b2, Booking(id: "b1", start: 800, end: 900)])
        }
    }

    @Test("a day larger than the supported request count is a typed failure")
    func tooManyBookingsFails() {
        let selector = makeSelector()
        let oversized = (0...RoomBookingSelector.maximumBookingCount).map {
            Booking(id: "over-\($0)", start: $0, end: $0 + 1)
        }

        #expect(throws: BookingError.tooManyBookings(RoomBookingSelector.maximumBookingCount + 1)) {
            try selector.orderedByFinish(oversized)
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - The most compatible bookings")
struct RoomBookingSelectorPart2Tests {
    @Test("the worked day hosts two of its four requests")
    func workedDaySelection() throws {
        let selector = makeSelector()
        let accepted = try selector.selectCompatible(workedDay)

        try #require(accepted.count == 2)
        #expect(accepted.map(\.id) == ["b1", "b3"])
        #expect(try selector.maximumCompatibleCount(workedDay) == 2)
    }

    @Test("two short requests fit where a start-time sweep would host only the long one")
    func startKeyIsWrong() throws {
        let selector = makeSelector()
        let accepted = try selector.selectCompatible(startKeyTrap)

        // A start-time sweep commits to the hundred-minute request first and
        // then has nowhere left to put either short one.
        try #require(accepted.count == 2)
        #expect(accepted.map(\.id) == ["s2", "s3"])
    }

    @Test("two requests fit where a shortest-duration sweep would host only the middle one")
    func durationKeyIsWrong() throws {
        let selector = makeSelector()
        let accepted = try selector.selectCompatible(durationKeyTrap)

        // The shortest request is the middle one, and it collides with both of
        // the others, so a duration sweep hosts exactly one.
        try #require(accepted.count == 2)
        #expect(accepted.map(\.id) == ["d1", "d3"])
    }

    @Test("requests meeting at their boundaries all fit")
    func backToBackRequestsAllFit() throws {
        let selector = makeSelector()
        let accepted = try selector.selectCompatible(backToBack)

        // A sweep testing `start > lastEnd` instead of `start >= lastEnd`
        // rejects two of these three.
        try #require(accepted.count == 3)
        #expect(accepted.map(\.id) == ["c1", "c2", "c3"])
    }

    @Test("nested requests leave only the innermost")
    func nestedRequests() throws {
        let selector = makeSelector()
        let accepted = try selector.selectCompatible(nested)

        try #require(accepted.count == 1)
        #expect(accepted[0].id == "n3")
    }

    @Test("an empty day hosts nothing rather than failing")
    func emptyDaySelects() throws {
        let selector = makeSelector()

        #expect(try selector.selectCompatible([]) == [])
        #expect(try selector.maximumCompatibleCount([]) == 0)
    }

    @Test("the selection is genuinely compatible and ordered on every fixture")
    func selectionIsCompatible() throws {
        let selector = makeSelector()
        for day in days {
            let accepted = try selector.selectCompatible(day)
            #expect(Set(accepted.map(\.id)).isSubset(of: Set(day.map(\.id))))
            for index in accepted.indices where index > 0 {
                #expect(!selector.overlaps(accepted[index - 1], accepted[index]))
                #expect(accepted[index - 1].end <= accepted[index].start)
            }
        }
    }

    @Test("the sweep matches an exhaustive search over every subset")
    func sweepMatchesExhaustiveSearch() throws {
        let selector = makeSelector()
        for day in days {
            #expect(try selector.maximumCompatibleCount(day) == bruteForceMaximumCompatible(day))
        }
    }

    @Test("the count is the size of the selection, not a separate answer")
    func countAgreesWithSelection() throws {
        let selector = makeSelector()
        for day in days {
            #expect(try selector.maximumCompatibleCount(day) == selector.selectCompatible(day).count)
        }
    }

    @Test("a malformed day is a typed failure here too")
    func malformedDayFails() {
        let selector = makeSelector()

        #expect(throws: BookingError.endNotAfterStart(id: "z1")) {
            try selector.selectCompatible([b1, Booking(id: "z1", start: 700, end: 700)])
        }
        #expect(throws: BookingError.duplicateBookingID("b2")) {
            try selector.maximumCompatibleCount([b2, b3, Booking(id: "b2", start: 0, end: 1)])
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Which requests to decline")
struct RoomBookingSelectorPart3Tests {
    @Test("the worked day declines the two requests it cannot host")
    func workedDayDeclines() throws {
        let selector = makeSelector()
        let declined = try selector.bookingsToDecline(workedDay)

        try #require(declined.count == 2)
        #expect(declined.map(\.id) == ["b2", "b4"])
    }

    @Test("declines come back in the same finish order the selection used")
    func declinesAreInFinishOrder() throws {
        let selector = makeSelector()
        let declined = try selector.bookingsToDecline(nested)

        try #require(declined.count == 2)
        #expect(declined.map(\.id) == ["n2", "n1"])
    }

    @Test("a day the room can host entirely declines nothing")
    func nothingDeclined() throws {
        let selector = makeSelector()

        #expect(try selector.bookingsToDecline(backToBack) == [])
        #expect(try selector.bookingsToDecline([]) == [])
    }

    @Test("accepted and declined partition the day exactly on every fixture")
    func acceptedAndDeclinedPartitionTheDay() throws {
        let selector = makeSelector()
        for day in days {
            let accepted = try selector.selectCompatible(day)
            let declined = try selector.bookingsToDecline(day)

            #expect(accepted.count + declined.count == day.count)
            #expect(Set(accepted.map(\.id)).union(Set(declined.map(\.id))) == Set(day.map(\.id)))
            #expect(Set(accepted.map(\.id)).isDisjoint(with: Set(declined.map(\.id))))
        }
    }

    @Test("every declined request collides with something the room accepted")
    func everyDeclineHasAReason() throws {
        let selector = makeSelector()
        for day in days {
            let accepted = try selector.selectCompatible(day)
            for turnedAway in try selector.bookingsToDecline(day) {
                #expect(accepted.contains { selector.overlaps($0, turnedAway) })
            }
        }
    }

    @Test("a malformed day is a typed failure here too")
    func malformedDayFails() {
        let selector = makeSelector()

        #expect(throws: BookingError.endNotAfterStart(id: "z3")) {
            try selector.bookingsToDecline([b3, Booking(id: "z3", start: 10, end: 5)])
        }
    }
}

// ── Part 4 ───────────────────────────────────────────────────────────────────

@Suite("Part 4 - Fewest supervisory check-ins")
struct RoomBookingSelectorPart4Tests {
    @Test("the worked day needs two check-ins, and each names what it observes")
    func workedDayPlan() throws {
        let selector = makeSelector()
        let plan = try selector.supervisionPlan(workedDay)

        try #require(plan.count == 2)
        #expect(plan[0] == SupervisionCheckIn(minute: 599, bookingIDs: ["b1", "b2"]))
        #expect(plan[1] == SupervisionCheckIn(minute: 659, bookingIDs: ["b3", "b4"]))
    }

    @Test("the bare minutes are a projection of the plan")
    func minutesProjectThePlan() throws {
        let selector = makeSelector()

        #expect(try selector.supervisionCheckIns(workedDay) == [599, 659])
        for day in days {
            #expect(try selector.supervisionCheckIns(day) == selector.supervisionPlan(day).map(\.minute))
        }
    }

    @Test("a check-in falls on the last minute of a request, not on its end")
    func checkInsUseTheLastMinute() throws {
        let selector = makeSelector()
        let minutes = try selector.supervisionCheckIns(backToBack)

        // The requests run to 10, 20 and 30. A check-in placed on an end
        // observes nothing, because the room is already released by then.
        try #require(minutes.count == 3)
        #expect(minutes == [9, 19, 29])
    }

    @Test("one check-in can observe every request when they all overlap")
    func oneCheckInForNestedRequests() throws {
        let selector = makeSelector()
        let plan = try selector.supervisionPlan(nested)

        try #require(plan.count == 1)
        #expect(plan[0] == SupervisionCheckIn(minute: 39, bookingIDs: ["n1", "n2", "n3"]))
    }

    @Test("declined requests are observed too, not skipped")
    func declinedRequestsAreObserved() throws {
        let selector = makeSelector()
        let plan = try selector.supervisionPlan(startKeyTrap)

        // s1 is declined, and a plan built only from the accepted requests
        // would leave it off the list of what the first check-in sees.
        try #require(plan.count == 2)
        #expect(plan[0] == SupervisionCheckIn(minute: 19, bookingIDs: ["s1", "s2"]))
        #expect(plan[1] == SupervisionCheckIn(minute: 39, bookingIDs: ["s3"]))
    }

    @Test("an empty day needs no check-ins rather than failing")
    func emptyDayNeedsNoCheckIns() throws {
        let selector = makeSelector()

        #expect(try selector.supervisionPlan([]) == [])
        #expect(try selector.supervisionCheckIns([]) == [])
    }

    @Test("every request on the day's list is filed under exactly one check-in")
    func everyRequestIsFiledOnce() throws {
        let selector = makeSelector()
        for day in days {
            let plan = try selector.supervisionPlan(day)
            let filed = plan.flatMap(\.bookingIDs)

            #expect(filed.count == day.count)
            #expect(Set(filed) == Set(day.map(\.id)))
            #expect(plan.allSatisfy { $0.bookingIDs == $0.bookingIDs.sorted() })
        }
    }

    @Test("every request a check-in claims is genuinely in progress at that minute")
    func filedRequestsContainTheirCheckIn() throws {
        let selector = makeSelector()
        for day in days {
            let byID = Dictionary(uniqueKeysWithValues: day.map { ($0.id, $0) })
            for checkIn in try selector.supervisionPlan(day) {
                for id in checkIn.bookingIDs {
                    let booking = try #require(byID[id])
                    #expect(booking.start <= checkIn.minute && checkIn.minute < booking.end)
                }
            }
        }
    }

    @Test("the check-in minutes come back in ascending order")
    func minutesAscend() throws {
        let selector = makeSelector()
        for day in days {
            let minutes = try selector.supervisionCheckIns(day)
            #expect(minutes == minutes.sorted())
            #expect(Set(minutes).count == minutes.count)
        }
    }

    @Test("the fewest check-ins is exactly the most requests the room can host")
    func checkInCountMatchesTheSelectionSize() throws {
        let selector = makeSelector()
        for day in days {
            // Not a coincidence and not a shortcut: on intervals the smallest
            // set of observing instants and the largest compatible selection
            // are the same number, which is what lets this part compose with
            // the second one instead of repeating it.
            #expect(try selector.supervisionCheckIns(day).count == selector.maximumCompatibleCount(day))
        }
    }

    @Test("a malformed day is a typed failure here too")
    func malformedDayFails() {
        let selector = makeSelector()

        #expect(throws: BookingError.duplicateBookingID("b4")) {
            try selector.supervisionPlan([b4, Booking(id: "b4", start: 0, end: 5)])
        }
        #expect(throws: BookingError.endNotAfterStart(id: "z4")) {
            try selector.supervisionCheckIns([Booking(id: "z4", start: 5, end: 5)])
        }
    }

    @Test("selectors are independent and never mutate the day they are given")
    func selectorsAreIndependentAndNonMutating() throws {
        let busy = makeSelector()
        let fresh = makeSelector()

        var day = workedDay
        let original = day

        for _ in 0..<5 {
            _ = try busy.selectCompatible(day)
            _ = try busy.bookingsToDecline(nested)
            _ = try busy.supervisionPlan(startKeyTrap)
        }

        // A second selector still reports the documented answers, which is what
        // a selection cached in static storage would break.
        #expect(try fresh.selectCompatible(workedDay).map(\.id) == ["b1", "b3"])
        #expect(try fresh.supervisionCheckIns(workedDay) == [599, 659])

        // The busy selector answers two different days independently.
        #expect(try busy.maximumCompatibleCount(backToBack) == 3)
        #expect(try busy.maximumCompatibleCount(nested) == 1)
        #expect(try busy.maximumCompatibleCount(backToBack) == 3)

        // The caller's list is untouched, and a caller emptying its own copy
        // changes nothing about a later call.
        #expect(day == original)
        day.removeAll()
        #expect(try fresh.maximumCompatibleCount(original) == 2)
    }
}
