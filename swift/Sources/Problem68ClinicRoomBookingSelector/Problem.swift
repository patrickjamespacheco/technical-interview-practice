// Problem 68: Clinic Room Booking Selector
// Swift 6, macOS 14+ | Mid-level | approximately 45 minutes
//
// A shared procedure room in an outpatient clinic receives more booking
// requests for a day than it can possibly host. Scheduling needs three answers
// from the same list: the most requests the one room can take, the requests
// that therefore have to be declined, and separately the fewest moments at
// which a supervisor must look in so that no request on the day's list goes
// unobserved, together with what each of those check-ins actually sees.
//
// Bookings are half-open, measured in minutes from midnight: a booking that
// ends where another begins occupies no shared minute, so the room can host
// both back to back.
//
// This is a greedy problem, which means the interesting question is never how
// to write the loop. It is why the loop is allowed to commit to a choice and
// never revisit it. Every part below rests on one sort key, and the key carries
// the entire claim: if you cannot say in a sentence why that key is safe, you
// have no evidence the answer is right, because a wrong key also produces a
// plausible-looking schedule.
//
// You choose the internal data structures; the public interface is the
// contract. Store all mutable state in instance properties initialized by init.
// Never use mutable global or static state. Immutable static constants are
// fine.
//
/*
# Example
let selector = RoomBookingSelector()
let requests = [
    Booking(id: "b1", start: 540, end: 600),
    Booking(id: "b2", start: 560, end: 640),
    Booking(id: "b3", start: 600, end: 660),
    Booking(id: "b4", start: 630, end: 700),
]

selector.overlaps(requests[0], requests[1])          // -> true
selector.overlaps(requests[0], requests[2])          // -> false  (600 is exclusive)

try selector.orderedByFinish(requests).map(\.id)     // -> ["b1", "b2", "b3", "b4"]
try selector.maximumCompatibleCount(requests)        // -> 2
try selector.selectCompatible(requests).map(\.id)    // -> ["b1", "b3"]
try selector.bookingsToDecline(requests).map(\.id)   // -> ["b2", "b4"]
try selector.supervisionCheckIns(requests)           // -> [599, 659]
try selector.supervisionPlan(requests)
// -> [SupervisionCheckIn(minute: 599, bookingIDs: ["b1", "b2"]),
//     SupervisionCheckIn(minute: 659, bookingIDs: ["b3", "b4"])]
*/
//
// PART 1 - Validate and order  (~9 min)
// Decide when two bookings collide, and put the day's requests into the one
// order every later part will read them in.
// The overlap test is the boundary convention written down once. Half-open
// means two bookings collide only when each starts strictly before the other
// ends; a request beginning at the minute the room is released is compatible
// with it, and getting that backwards moves every answer in this file by one
// booking.
// The order is by the minute the room is released, earliest first. Two
// requests that finish at the same minute must still order the same way on
// every run, so break the tie by id; without that the selection is not
// reproducible and no test can assert it.
// A booking whose end is not after its start is a fault, and so is a list that
// repeats an id or that exceeds the supported request count. Each is a typed
// failure naming what broke.
//
// PART 2 - The most compatible bookings  (~13 min)
// Report the largest set of requests the single room can host, as the bookings
// themselves, and how many that is.
// Before writing the sweep, state the exchange argument out loud in one
// sentence: take any optimal schedule, swap its first booking for the
// compatible request that finishes earliest, and argue why the count cannot
// drop. That sentence is the reason the key is finish time and not start time
// or duration, and both of those wrong keys have counterexamples two or three
// bookings long.
// Return the selection rather than only the count. The next part needs the
// bookings themselves, and a method that returned a count would force the
// whole sweep to be written a second time to get them.
//
// PART 3 - Which requests to decline  (~9 min)
// Report the requests scheduling has to turn away, in the same finish order the
// selection was made in.
// There is no second algorithm here and there should not be one. Fewest
// declines and most bookings hosted are one answer read from opposite ends, so
// this is the complement of the previous part over the same ordered list. A
// candidate who reaches for a new greedy here has missed that the two questions
// are the same question.
//
// PART 4 - Fewest supervisory check-ins  (~14 min)
// Report the fewest minutes at which a supervisor must look in so that every
// request on the day's list is in progress at one of them, and report which
// requests each of those check-ins observes.
// This part covers every request the day contains, accepted or declined:
// supervision is about the requests on the list, not the subset one room
// happened to fit. That is what makes the count surprising, and finding the
// surprise is the work here.
// Before writing anything, argue this: the fewest check-ins is exactly the
// number of requests the room could host, and the last minute of each request
// the previous part accepted is a check-in that works. Every declined request
// was declined because it begins before some accepted request is released
// while finishing no earlier than that request does, so that accepted
// request's last minute falls inside it. A maximisation and a minimisation
// turning out to be the same number is not a coincidence on intervals, and
// spotting it is worth more than any loop in this file.
// So the minutes come from the previous part. The attribution does not: every
// request has to be filed under a check-in, and a request is filed under the
// earliest check-in that falls inside it. List the ids of each check-in's
// requests in ascending id order so the plan is reproducible, and return the
// richer plan as the primitive with the bare minutes as its projection.


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
    public func overlaps(_ first: Booking, _ second: Booking) -> Bool {
        false
    }

    public func orderedByFinish(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        throw .notImplemented
    }

    // MARK: Part 2 - The most compatible bookings
    public func selectCompatible(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        throw .notImplemented
    }

    public func maximumCompatibleCount(_ bookings: [Booking]) throws(BookingError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - Which requests to decline
    public func bookingsToDecline(_ bookings: [Booking]) throws(BookingError) -> [Booking] {
        throw .notImplemented
    }

    // MARK: Part 4 - Fewest supervisory check-ins
    public func supervisionPlan(_ bookings: [Booking]) throws(BookingError) -> [SupervisionCheckIn] {
        throw .notImplemented
    }

    public func supervisionCheckIns(_ bookings: [Booking]) throws(BookingError) -> [Int] {
        throw .notImplemented
    }
}
