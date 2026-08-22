public struct Booking: Equatable, Sendable {
    public let id: String
    public let start: Int
    public let end: Int

    public init(id: String, start: Int, end: Int) {
        self.id = id
        self.start = start
        self.end = end
    }

    /// Bookings are half-open in minutes from midnight, so a booking that ends
    /// where another begins occupies no shared minute of the room.
    public var duration: Int { end - start }
}

public struct SupervisionCheckIn: Equatable, Sendable {
    public let minute: Int
    public let bookingIDs: [String]

    public init(minute: Int, bookingIDs: [String]) {
        self.minute = minute
        self.bookingIDs = bookingIDs
    }
}

public enum BookingError: Error, Equatable, Sendable {
    case endNotAfterStart(id: String)
    case duplicateBookingID(String)
    case tooManyBookings(Int)
    case notImplemented
}

public struct RoomBookingSelector: Sendable {
    /// The day's request list is bounded so the sort is the only cost that
    /// matters and no caller can hand over an unbounded schedule.
    public static let maximumBookingCount = 100_000

    public init() {}

    // MARK: Part 1 - Validate and order

    /// Whether two bookings would need the room at the same minute.
    ///
    /// Half-open: a booking running to 600 and one starting at 600 share no
    /// minute, so the room can host both back to back.
    public func overlaps(_ first: Booking, _ second: Booking) -> Bool {
        first.start < second.end && second.start < first.end
    }

    /// The requests ordered by the minute they release the room, earliest
    /// first, with ties broken by id.
    ///
    /// This is the only sort key in the file, and every later part reads the
    /// day through it. The tie-break is not decoration: two requests that end
    /// at the same minute must order the same way on every run, or the
    /// selection a caller sees is not reproducible.
    public func orderedByFinish(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        try validate(bookings)
        return bookings.sorted { left, right in
            left.end == right.end ? left.id < right.id : left.end < right.end
        }
    }

    // MARK: Part 2 - The most compatible bookings

    /// The largest set of requests the one room can host, as the bookings
    /// themselves.
    ///
    /// The exchange argument in one sentence: take any optimal schedule and
    /// swap its first booking for the compatible one that finishes earliest;
    /// the swap leaves at least as much of the day free to the right, so the
    /// count never drops, and repeating it turns any optimal schedule into
    /// this one. That sentence is the whole justification for the key, which
    /// is why sorting by start or by duration is not a matter of taste.
    ///
    /// This method, not the count, is the primitive: a count alone would force
    /// the next part to run the sweep a second time.
    public func selectCompatible(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        var accepted: [Booking] = []
        for booking in try orderedByFinish(bookings) {
            // Half-open again: a request may start exactly when the room is
            // released, so the test is `>=` rather than `>`.
            guard let last = accepted.last else {
                accepted.append(booking)
                continue
            }
            if booking.start >= last.end {
                accepted.append(booking)
            }
        }
        return accepted
    }

    /// How many requests the room can host, which is a projection of the
    /// selection rather than a second sweep.
    public func maximumCompatibleCount(_ bookings: [Booking]) throws(BookingError) -> Int {
        try selectCompatible(bookings).count
    }

    // MARK: Part 3 - Which requests to decline

    /// The requests scheduling has to turn away, in the same finish order the
    /// selection was made in.
    ///
    /// Fewest declines and most bookings hosted are the same answer read from
    /// opposite ends, so this is the complement of the selection and not a
    /// minimisation of its own.
    public func bookingsToDecline(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        let acceptedIDs = Set(try selectCompatible(bookings).map(\.id))
        return try orderedByFinish(bookings).filter { !acceptedIDs.contains($0.id) }
    }

    // MARK: Part 4 - Fewest supervisory check-ins

    /// The fewest minutes at which a supervisor must look in so that every
    /// request on the day's list is in progress at one of them, with the
    /// requests each check-in observes.
    ///
    /// The minutes are not a new algorithm and it would be a mistake to write
    /// one. The fewest check-ins is exactly the number of requests the room
    /// could host, and the last minute of each accepted request is a check-in
    /// that works: a request was declined only because it begins before some
    /// accepted request is released while finishing no earlier than that
    /// request does, so that accepted request's last minute lies inside it.
    /// A maximisation and a minimisation coinciding is a property of
    /// intervals, and it is the reason this part composes with Part 2 rather
    /// than repeating it.
    ///
    /// The attribution is the work. Every request on the day's list is filed
    /// under the earliest check-in that falls inside it, which needs a walk
    /// over the requests rather than over the selection.
    public func supervisionPlan(_ bookings: [Booking]) throws(BookingError) -> [SupervisionCheckIn] {
        let minutes = try selectCompatible(bookings).map { $0.end - 1 }
        guard !minutes.isEmpty else { return [] }

        var observed: [[String]] = Array(repeating: [], count: minutes.count)
        for booking in try orderedByFinish(bookings) {
            // The minutes are ascending, so the first one at or after this
            // request's start is the earliest that can fall inside it, and the
            // argument above guarantees one exists.
            for (index, minute) in minutes.enumerated() where minute >= booking.start {
                observed[index].append(booking.id)
                break
            }
        }

        return zip(minutes, observed).map { minute, ids in
            SupervisionCheckIn(minute: minute, bookingIDs: ids.sorted())
        }
    }

    /// The check-in minutes alone, which is a projection of the plan.
    public func supervisionCheckIns(_ bookings: [Booking]) throws(BookingError) -> [Int] {
        try supervisionPlan(bookings).map(\.minute)
    }

    // MARK: Shared validation

    /// The precondition every part rests on. All four entry points reach the
    /// day's list through `orderedByFinish`, so the check lives once, here.
    private func validate(_ bookings: [Booking]) throws(BookingError) {
        guard bookings.count <= Self.maximumBookingCount else {
            throw .tooManyBookings(bookings.count)
        }
        var seen = Set<String>()
        seen.reserveCapacity(bookings.count)
        for booking in bookings {
            guard booking.end > booking.start else {
                throw .endNotAfterStart(id: booking.id)
            }
            guard seen.insert(booking.id).inserted else {
                throw .duplicateBookingID(booking.id)
            }
        }
    }
}
