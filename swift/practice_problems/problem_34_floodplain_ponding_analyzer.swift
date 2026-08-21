// Problem 34: Floodplain Ponding Analyzer
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A network of flood gauges reports ground elevation at fixed intervals along a
// channel. Planners want three things out of that profile: the widest pair of
// posts that could impound water between them, the standing depth over every
// post once the channel has saturated, and the largest single body of standing
// water. Each post covers one interval of channel, which is the standard
// first-order model and the one the gauges are spaced for.
//
// Every part walks two cursors inward from the ends of the profile. What makes
// this family different from the sorted-array kind is that there is no target
// to compare a sum against, so the rule for which cursor moves has to be argued
// rather than read off. That single conditional is the whole difficulty of this
// problem, and it is worth saying the argument out loud before writing it.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let analyzer = FloodplainAnalyzer()
// elevations 0, 1, 0, 2, 1, 0, 1, 3, 2, 1, 2, 1 on posts gauge-00 through gauge-11
let posts = [
    GaugePost(id: "gauge-00", elevation: 0), GaugePost(id: "gauge-01", elevation: 1),
    GaugePost(id: "gauge-02", elevation: 0), GaugePost(id: "gauge-03", elevation: 2),
    GaugePost(id: "gauge-04", elevation: 1), GaugePost(id: "gauge-05", elevation: 0),
    GaugePost(id: "gauge-06", elevation: 1), GaugePost(id: "gauge-07", elevation: 3),
    GaugePost(id: "gauge-08", elevation: 2), GaugePost(id: "gauge-09", elevation: 1),
    GaugePost(id: "gauge-10", elevation: 2), GaugePost(id: "gauge-11", elevation: 1),
]

try analyzer.widestImpoundment(profile: posts)
// -> Impoundment(leftID: "gauge-03", rightID: "gauge-10", capacity: 14)

try analyzer.pondingProfile(profile: posts)
// -> [0, 0, 1, 0, 1, 2, 1, 0, 0, 1, 0, 0]

try analyzer.totalPondedVolume(profile: posts)   // -> 6
try analyzer.largestPond(profile: posts)
// -> Pond(startIndex: 4, endIndex: 6, volume: 4)
*/
//
// PART 1 - Widest impoundable span  (~12 min)
// Report the pair of posts that could hold back the most water between them.
// A pair's capacity is the shorter of the two elevations times the number of
// intervals separating them, and the posts in between are ignored: this asks
// what the two walls could hold, not what the ground allows.
// Converge two cursors from the ends. The move rule is a discard argument, not
// a comparison against a target: the capacity is capped by the shorter side,
// and moving the taller side inward can only shorten the span while leaving
// that cap where it was. So move the shorter side, and say why before you write
// it, because every pair the move discards has to be one already proven no
// better than the pair just measured.
// A profile with fewer than two posts, and one where no pair holds anything at
// all, both report that there is no impoundment.
// A gauge reading below datum is a miscalibrated post rather than a hollow, so
// it is a typed failure naming the post.
//
// PART 2 - Standing depth at every post  (~19 min)
// Report the depth of standing water above every post once the channel has
// saturated, and the total across the whole profile.
// The same two cursors, now each carrying the tallest post it has walked past.
// Whichever side is shorter is the side whose answer is already settled, and
// that is what lets a single converging pass do what a pair of prefix-maximum
// arrays would otherwise be needed for.
// Two traps. The first is the move rule run backwards: advancing the taller
// side discards pairs that were never proven impossible, and it invents water
// over ground that would drain. The second is ordering: the running maximum has
// to be updated before the depth at that post is recorded. Recording first
// reports a negative depth at every post that is itself the tallest so far, and
// the profile is exposed rather than only the total because a total is the one
// number that can stay plausible while the profile underneath it is wrong.
// Comparing the two running maxima instead of the two posts is a different
// statement of the same rule and is not a bug; the bug is moving the wrong side.
// The total is the sum of the depths. Make it a projection of the profile
// rather than a second walk, so there is one converging pass in this file.
//
// PART 3 - The largest single pond  (~14 min)
// Report the single body of standing water that holds the most, as the maximal
// run of consecutive posts with water above them, with its bounds inclusive.
// Read the depths from Part 2 rather than deriving anything again. Where two
// ponds hold the same volume, the earlier one wins, so the answer never depends
// on which way the scan happened to run.
// A profile holding no water at all reports that there is no pond.

public struct GaugePost: Equatable, Sendable {
    public let id: String
    public let elevation: Int

    public init(id: String, elevation: Int) {
        self.id = id
        self.elevation = elevation
    }
}

public struct Impoundment: Equatable, Sendable {
    public let leftID: String
    public let rightID: String
    public let capacity: Int

    public init(leftID: String, rightID: String, capacity: Int) {
        self.leftID = leftID
        self.rightID = rightID
        self.capacity = capacity
    }
}

public struct Pond: Equatable, Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let volume: Int

    public init(startIndex: Int, endIndex: Int, volume: Int) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.volume = volume
    }
}

public enum ProfileError: Error, Equatable, Sendable {
    case negativeElevation(id: String)
    case notImplemented
}

public struct FloodplainAnalyzer: Sendable {
    public init() {}

    // MARK: Part 1 - Widest impoundable span
    public func widestImpoundment(profile: [GaugePost]) throws(ProfileError) -> Impoundment? {
        throw .notImplemented
    }

    // MARK: Part 2 - Standing depth at every post
    public func pondingProfile(profile: [GaugePost]) throws(ProfileError) -> [Int] {
        throw .notImplemented
    }

    public func totalPondedVolume(profile: [GaugePost]) throws(ProfileError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - The largest single pond
    public func largestPond(profile: [GaugePost]) throws(ProfileError) -> Pond? {
        throw .notImplemented
    }
}
