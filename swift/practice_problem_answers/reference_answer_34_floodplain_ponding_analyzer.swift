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

    /// The pair of posts that could hold back the most water between them,
    /// measured as the shorter of the two elevations times the number of
    /// intervals separating them.
    ///
    /// Two cursors converge from the ends. There is no target to compare a sum
    /// against here, so the move rule comes from a discard argument instead:
    /// the span's capacity is capped by the shorter side, and moving the taller
    /// side inward can only shorten the span without ever raising that cap.
    /// So the shorter side is the one that moves, and every pair it discards
    /// was already proven no better than the pair just measured.
    public func widestImpoundment(profile: [GaugePost]) throws(ProfileError) -> Impoundment? {
        try validate(profile)
        guard profile.count >= 2 else { return nil }

        var lo = 0
        var hi = profile.count - 1
        var best: Impoundment?

        while lo < hi {
            let capacity = min(profile[lo].elevation, profile[hi].elevation) * (hi - lo)
            if capacity > (best?.capacity ?? 0) {
                best = Impoundment(leftID: profile[lo].id, rightID: profile[hi].id, capacity: capacity)
            }
            if profile[lo].elevation <= profile[hi].elevation {
                lo += 1
            } else {
                hi -= 1
            }
        }

        return best
    }

    // MARK: Part 2 - Standing depth at every post

    /// The depth of standing water above every post once the channel has
    /// saturated.
    ///
    /// The same two cursors, now each carrying the tallest post it has walked
    /// past. Whichever side is shorter is the side whose answer is already
    /// settled: nothing beyond the other cursor can be lower than the side
    /// standing opposite it, so the running maximum on the shorter side is the
    /// water level over that post, whatever the rest of the profile does.
    ///
    /// The running maximum is updated before the depth is recorded. Recording
    /// first reports a negative depth at every post that is itself the tallest
    /// so far, which is why the profile is worth exposing: a total can stay
    /// plausible while the profile underneath it is wrong.
    public func pondingProfile(profile: [GaugePost]) throws(ProfileError) -> [Int] {
        try validate(profile)
        guard !profile.isEmpty else { return [] }

        var depths = [Int](repeating: 0, count: profile.count)
        var lo = 0
        var hi = profile.count - 1
        var leftMax = 0
        var rightMax = 0

        while lo <= hi {
            // The shorter side is the one that moves. Advancing the taller
            // side is the discard argument run backwards, and it invents
            // water over ground that would drain.
            if profile[lo].elevation <= profile[hi].elevation {
                leftMax = max(leftMax, profile[lo].elevation)
                depths[lo] = leftMax - profile[lo].elevation
                lo += 1
            } else {
                rightMax = max(rightMax, profile[hi].elevation)
                depths[hi] = rightMax - profile[hi].elevation
                hi -= 1
            }
        }

        return depths
    }

    /// The total standing water across the whole profile.
    ///
    /// This is the sum of the depth at every post. There is one converging walk
    /// in this file and the total is a projection of it, because a total that
    /// derives itself separately is a second implementation of the same idea
    /// with none of the evidence.
    public func totalPondedVolume(profile: [GaugePost]) throws(ProfileError) -> Int {
        try pondingProfile(profile: profile).reduce(0, +)
    }

    // MARK: Part 3 - The largest single pond

    /// The single body of standing water holding the most, as the maximal run
    /// of consecutive posts with water above them.
    ///
    /// This reads the depths rather than re-deriving them. Where two ponds hold
    /// the same volume the earlier one wins, so the answer never depends on
    /// which way the scan happened to run.
    public func largestPond(profile: [GaugePost]) throws(ProfileError) -> Pond? {
        let depths = try pondingProfile(profile: profile)

        var best: Pond?
        var index = 0

        while index < depths.count {
            guard depths[index] > 0 else {
                index += 1
                continue
            }
            var end = index
            var volume = 0
            while end < depths.count, depths[end] > 0 {
                volume += depths[end]
                end += 1
            }
            if volume > (best?.volume ?? 0) {
                best = Pond(startIndex: index, endIndex: end - 1, volume: volume)
            }
            index = end
        }

        return best
    }

    // MARK: Shared validation

    /// A gauge below datum is a miscalibrated post rather than a hollow, and
    /// the report names the post so someone can go and look at it.
    private func validate(_ profile: [GaugePost]) throws(ProfileError) {
        for post in profile where post.elevation < 0 {
            throw .negativeElevation(id: post.id)
        }
    }
}
