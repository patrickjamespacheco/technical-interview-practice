import Testing
@testable import Problem34FloodplainPondingAnalyzer

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// Builds a gauge run whose post ids are zero-padded and ordered, so a failure
/// message names a post rather than an index.
private func posts(_ elevations: [Int]) -> [GaugePost] {
    elevations.enumerated().map { index, elevation in
        GaugePost(id: "gauge-" + (index < 10 ? "0" : "") + String(index), elevation: elevation)
    }
}

/// The worked channel profile.
private let workedProfile = posts([0, 1, 0, 2, 1, 0, 1, 3, 2, 1, 2, 1])

/// A profile that leans: the tallest post is the first one. A pass that moves
/// the taller cursor inward reports water here that the ground would drain.
private let leaningProfile = posts([4, 2, 3])

/// One deep basin between two banks, so the largest pond is the whole hollow.
private let basinProfile = posts([3, 0, 0, 2, 0, 4])

private let risingProfile = posts([1, 2, 3, 4, 5])
private let fallingProfile = posts([5, 4, 3, 2, 1])
private let flatProfile = posts([0, 0, 0])

/// Two ponds of exactly the same volume, so the tie rule is observable.
private let twinPondProfile = posts([2, 0, 2, 0, 2])

private let profiles: [[GaugePost]] = [
    workedProfile,
    leaningProfile,
    basinProfile,
    risingProfile,
    fallingProfile,
    flatProfile,
    twinPondProfile,
    posts([7]),
    [],
]

private func makeAnalyzer() -> FloodplainAnalyzer {
    FloodplainAnalyzer()
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Widest impoundable span")
struct FloodplainPart1Tests {
    @Test("the worked profile impounds fourteen between the two posts of height two")
    func workedProfileWidestSpan() throws {
        let analyzer = makeAnalyzer()
        let impoundment = try #require(try analyzer.widestImpoundment(profile: workedProfile))

        #expect(impoundment == Impoundment(leftID: "gauge-03", rightID: "gauge-10", capacity: 14))
    }

    @Test("a leaning profile takes its span from the ends, not from the tallest pair")
    func leaningProfileWidestSpan() throws {
        let analyzer = makeAnalyzer()
        let impoundment = try #require(try analyzer.widestImpoundment(profile: leaningProfile))

        // The outer pair holds three times two intervals. A pass that advances
        // the taller cursor abandons it after one step.
        #expect(impoundment == Impoundment(leftID: "gauge-00", rightID: "gauge-02", capacity: 6))
    }

    @Test("a basin's widest span is bank to bank")
    func basinWidestSpan() throws {
        let analyzer = makeAnalyzer()
        let impoundment = try #require(try analyzer.widestImpoundment(profile: basinProfile))

        #expect(impoundment == Impoundment(leftID: "gauge-00", rightID: "gauge-05", capacity: 15))
    }

    @Test("a monotone profile still has a widest span")
    func monotoneProfiles() throws {
        let analyzer = makeAnalyzer()
        let rising = try #require(try analyzer.widestImpoundment(profile: risingProfile))
        let falling = try #require(try analyzer.widestImpoundment(profile: fallingProfile))

        #expect(rising.capacity == 6)
        #expect(falling.capacity == 6)
    }

    @Test("a profile that can impound nothing reports no impoundment")
    func nothingToImpound() throws {
        let analyzer = makeAnalyzer()

        #expect(try analyzer.widestImpoundment(profile: flatProfile) == nil)
        #expect(try analyzer.widestImpoundment(profile: posts([7])) == nil)
        #expect(try analyzer.widestImpoundment(profile: []) == nil)
    }

    @Test("the converging sweep agrees with looking at every pair")
    func sweepAgreesWithEveryPair() throws {
        let analyzer = makeAnalyzer()
        for profile in profiles {
            var expected = 0
            for left in profile.indices {
                for right in profile.indices where right > left {
                    expected = max(
                        expected,
                        min(profile[left].elevation, profile[right].elevation) * (right - left)
                    )
                }
            }
            let capacity = try analyzer.widestImpoundment(profile: profile)?.capacity ?? 0
            #expect(capacity == expected)
        }
    }

    @Test("a gauge below datum is a typed failure naming the post")
    func negativeElevationFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: ProfileError.negativeElevation(id: "gauge-01")) {
            try analyzer.widestImpoundment(profile: posts([3, -1, 4]))
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Standing depth at every post")
struct FloodplainPart2Tests {
    @Test("the worked profile ponds six centimetres spread over four posts")
    func workedProfileDepths() throws {
        let analyzer = makeAnalyzer()
        let depths = try analyzer.pondingProfile(profile: workedProfile)

        #expect(depths == [0, 0, 1, 0, 1, 2, 1, 0, 0, 1, 0, 0])
        #expect(try analyzer.totalPondedVolume(profile: workedProfile) == 6)
    }

    @Test("a leaning profile ponds one, not two")
    func leaningProfileDepths() throws {
        let analyzer = makeAnalyzer()

        // Advancing the taller cursor claims two here: it lets the opening post
        // of four set the water level over the dip without the far bank of
        // three ever capping it.
        #expect(try analyzer.pondingProfile(profile: leaningProfile) == [0, 1, 0])
        #expect(try analyzer.totalPondedVolume(profile: leaningProfile) == 1)
    }

    @Test("a basin fills to the level of its lower bank")
    func basinDepths() throws {
        let analyzer = makeAnalyzer()

        #expect(try analyzer.pondingProfile(profile: basinProfile) == [0, 3, 3, 1, 3, 0])
        #expect(try analyzer.totalPondedVolume(profile: basinProfile) == 10)
    }

    @Test("no post ever reports a negative depth")
    func noNegativeDepths() throws {
        let analyzer = makeAnalyzer()

        // A pass that records the depth before raising its running maximum
        // reports minus seven here.
        #expect(try analyzer.pondingProfile(profile: posts([7])) == [0])
        for profile in profiles {
            let depths = try analyzer.pondingProfile(profile: profile)
            #expect(depths.allSatisfy { $0 >= 0 })
            #expect(depths.count == profile.count)
        }
    }

    @Test("a monotone profile holds nothing anywhere")
    func monotoneProfilesHoldNothing() throws {
        let analyzer = makeAnalyzer()

        #expect(try analyzer.pondingProfile(profile: risingProfile) == [0, 0, 0, 0, 0])
        #expect(try analyzer.pondingProfile(profile: fallingProfile) == [0, 0, 0, 0, 0])
        #expect(try analyzer.totalPondedVolume(profile: risingProfile) == 0)
        #expect(try analyzer.totalPondedVolume(profile: fallingProfile) == 0)
    }

    @Test("an empty profile has no depths and holds nothing")
    func emptyProfile() throws {
        let analyzer = makeAnalyzer()

        #expect(try analyzer.pondingProfile(profile: []) == [])
        #expect(try analyzer.totalPondedVolume(profile: []) == 0)
    }

    @Test("the depths agree with the level each post actually sits under")
    func depthsAgreeWithTheStraightforwardDerivation() throws {
        let analyzer = makeAnalyzer()
        for profile in profiles {
            let elevations = profile.map(\.elevation)
            let expected = elevations.indices.map { index -> Int in
                let leftMax = elevations[...index].max() ?? 0
                let rightMax = elevations[index...].max() ?? 0
                return max(0, min(leftMax, rightMax) - elevations[index])
            }
            #expect(try analyzer.pondingProfile(profile: profile) == expected)
        }
    }

    @Test("the total is the sum of the depths on every profile")
    func totalIsTheSumOfTheDepths() throws {
        let analyzer = makeAnalyzer()
        for profile in profiles {
            let depths = try analyzer.pondingProfile(profile: profile)
            #expect(try analyzer.totalPondedVolume(profile: profile) == depths.reduce(0, +))
        }
    }

    @Test("the widest span could always hold everything the ground actually holds")
    func widestSpanBoundsTheTotal() throws {
        let analyzer = makeAnalyzer()
        for profile in profiles {
            let capacity = try analyzer.widestImpoundment(profile: profile)?.capacity ?? 0
            #expect(capacity >= (try analyzer.totalPondedVolume(profile: profile)))
        }
    }

    @Test("a gauge below datum is a typed failure naming the post")
    func negativeElevationFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: ProfileError.negativeElevation(id: "gauge-02")) {
            try analyzer.pondingProfile(profile: posts([3, 1, -4, 2]))
        }
        #expect(throws: ProfileError.negativeElevation(id: "gauge-02")) {
            try analyzer.totalPondedVolume(profile: posts([3, 1, -4, 2]))
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - The largest single pond")
struct FloodplainPart3Tests {
    @Test("the worked profile's largest pond is the middle hollow")
    func workedProfileLargestPond() throws {
        let analyzer = makeAnalyzer()
        let pond = try #require(try analyzer.largestPond(profile: workedProfile))

        #expect(pond == Pond(startIndex: 4, endIndex: 6, volume: 4))
    }

    @Test("a basin is one pond spanning every flooded post")
    func basinLargestPond() throws {
        let analyzer = makeAnalyzer()
        let pond = try #require(try analyzer.largestPond(profile: basinProfile))

        #expect(pond == Pond(startIndex: 1, endIndex: 4, volume: 10))
    }

    @Test("two ponds of the same volume resolve to the earlier one")
    func tiedPondsResolveToTheEarlier() throws {
        let analyzer = makeAnalyzer()
        let pond = try #require(try analyzer.largestPond(profile: twinPondProfile))

        #expect(pond == Pond(startIndex: 1, endIndex: 1, volume: 2))
    }

    @Test("a profile holding nothing reports no pond")
    func noPond() throws {
        let analyzer = makeAnalyzer()

        #expect(try analyzer.largestPond(profile: risingProfile) == nil)
        #expect(try analyzer.largestPond(profile: fallingProfile) == nil)
        #expect(try analyzer.largestPond(profile: flatProfile) == nil)
        #expect(try analyzer.largestPond(profile: []) == nil)
    }

    @Test("the largest pond is a real run of the depth profile and never exceeds the total")
    func pondAgreesWithTheDepthProfile() throws {
        let analyzer = makeAnalyzer()
        for profile in profiles {
            let depths = try analyzer.pondingProfile(profile: profile)
            guard let pond = try analyzer.largestPond(profile: profile) else {
                #expect(depths.allSatisfy { $0 == 0 })
                continue
            }
            #expect(pond.startIndex <= pond.endIndex)
            #expect(pond.startIndex >= 0)
            #expect(pond.endIndex < depths.count)
            #expect(depths[pond.startIndex...pond.endIndex].allSatisfy { $0 > 0 })
            #expect(depths[pond.startIndex...pond.endIndex].reduce(0, +) == pond.volume)
            #expect(pond.volume <= (try analyzer.totalPondedVolume(profile: profile)))
            // A maximal run: the posts either side of it are dry or off the end.
            if pond.startIndex > 0 { #expect(depths[pond.startIndex - 1] == 0) }
            if pond.endIndex + 1 < depths.count { #expect(depths[pond.endIndex + 1] == 0) }
        }
    }

    @Test("a gauge below datum is a typed failure naming the post")
    func negativeElevationFails() {
        let analyzer = makeAnalyzer()
        #expect(throws: ProfileError.negativeElevation(id: "gauge-00")) {
            try analyzer.largestPond(profile: posts([-3, 1, 4]))
        }
    }

    @Test("analyzers are independent and never mutate the profile they are given")
    func analyzersAreIndependentAndNonMutating() throws {
        let busy = makeAnalyzer()
        let fresh = makeAnalyzer()

        var profile = workedProfile
        let original = profile

        for _ in 0..<5 {
            _ = try busy.pondingProfile(profile: basinProfile)
            _ = try busy.largestPond(profile: twinPondProfile)
            _ = try busy.widestImpoundment(profile: profile)
        }

        // A second analyzer still reports the documented answers, which is what
        // a depth table cached in static storage would break.
        #expect(try fresh.totalPondedVolume(profile: workedProfile) == 6)
        #expect(try fresh.pondingProfile(profile: leaningProfile) == [0, 1, 0])
        #expect(try fresh.largestPond(profile: basinProfile) == Pond(startIndex: 1, endIndex: 4, volume: 10))

        // The busy analyzer answers two different profiles independently.
        #expect(try busy.totalPondedVolume(profile: basinProfile) == 10)
        #expect(try busy.totalPondedVolume(profile: twinPondProfile) == 4)
        #expect(try busy.totalPondedVolume(profile: basinProfile) == 10)

        // The caller's profile is untouched, and a caller emptying its own copy
        // changes nothing about a later call.
        #expect(profile == original)
        profile.removeAll()
        #expect(try fresh.totalPondedVolume(profile: original) == 6)
    }
}
