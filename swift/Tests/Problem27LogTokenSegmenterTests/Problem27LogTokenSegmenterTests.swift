import Testing
@testable import Problem27LogTokenSegmenter

/// The worked vocabulary: the long entry is legal but expensive, so the shortest
/// segmentation is not the cheapest one.
private let workedVocabulary = [
    VocabularySegment(text: "auth", penalty: 1),
    VocabularySegment(text: "token", penalty: 1),
    VocabularySegment(text: "authtoken", penalty: 5),
    VocabularySegment(text: "refresh", penalty: 1),
]

private func makeWorkedSegmenter() throws -> LogTokenSegmenter {
    try LogTokenSegmenter(vocabulary: workedVocabulary)
}

/// The vocabulary that punishes greedy longest-match segmentation.
private func makeRunSegmenter() throws -> LogTokenSegmenter {
    try LogTokenSegmenter(vocabulary: [
        VocabularySegment(text: "a", penalty: 1),
        VocabularySegment(text: "aa", penalty: 1),
        VocabularySegment(text: "aaa", penalty: 1),
    ])
}

private func makeFlatSegmenter(_ texts: [String], penalty: Int = 2) throws -> LogTokenSegmenter {
    try LogTokenSegmenter(vocabulary: texts.map { VocabularySegment(text: $0, penalty: penalty) })
}

@Suite("Part 1 - Decide whether an identifier segments")
struct SegmenterPart1Tests {
    @Test("the worked identifier segments and a near miss does not")
    func workedIdentifier() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(segmenter.canSegment("authtokenrefresh"))
        #expect(segmenter.canSegment("authtokenexpire") == false)
        #expect(segmenter.canSegment("authtoken"))
    }

    @Test("an empty identifier is covered by shipping no segments at all")
    func emptyIdentifierSegments() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(segmenter.canSegment(""))
    }

    @Test("taking the longest match first is not the same question")
    func greedyLongestMatchTrap() throws {
        let segmenter = try makeRunSegmenter()
        #expect(segmenter.canSegment("aaaa"))
        #expect(segmenter.canSegment("aaaaaaaaaa"))
        #expect(segmenter.canSegment("aaaaab") == false)
    }

    @Test("an identifier longer than every vocabulary entry still segments when its pieces do")
    func identifierLongerThanEveryEntry() throws {
        let segmenter = try makeFlatSegmenter(["log", "in", "user"])
        #expect(segmenter.canSegment("loginuser"))
        #expect(segmenter.canSegment("loginuserlogin"))
        #expect(segmenter.canSegment("loginusr") == false)
    }

    @Test("a single unknown character anywhere blocks the whole identifier")
    func unknownCharacterBlocks() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(segmenter.canSegment("authXtoken") == false)
        #expect(segmenter.canSegment("zauth") == false)
    }

    @Test("a malformed vocabulary is a typed failure")
    func malformedVocabularyFails() {
        #expect(throws: SegmenterError.emptyVocabulary) {
            try LogTokenSegmenter(vocabulary: [])
        }
        #expect(throws: SegmenterError.emptySegmentText) {
            try LogTokenSegmenter(vocabulary: [VocabularySegment(text: "", penalty: 1)])
        }
        #expect(throws: SegmenterError.negativePenalty("auth")) {
            try LogTokenSegmenter(vocabulary: [VocabularySegment(text: "auth", penalty: -1)])
        }
        #expect(throws: SegmenterError.duplicateSegmentText("auth")) {
            try LogTokenSegmenter(vocabulary: [
                VocabularySegment(text: "auth", penalty: 1),
                VocabularySegment(text: "auth", penalty: 2),
            ])
        }
    }
}

@Suite("Part 2 - Return one canonical segmentation")
struct SegmenterPart2Tests {
    @Test("the worked identifier splits into three known segments")
    func workedSegmentation() throws {
        let segmenter = try makeWorkedSegmenter()
        let parts = try segmenter.firstSegmentation("authtokenrefresh")
        try #require(parts.count == 3)
        #expect(parts == ["auth", "token", "refresh"])
        #expect(parts.joined() == "authtokenrefresh")
    }

    @Test("every reported segment is in the vocabulary and they rejoin the identifier")
    func segmentsAreWellFormed() throws {
        let segmenter = try makeFlatSegmenter(["log", "in", "user", "login"])
        let identifier = "loginuserlogin"
        let parts = try segmenter.firstSegmentation(identifier)
        try #require(!parts.isEmpty)
        #expect(parts.joined() == identifier)
        for part in parts {
            #expect(segmenter.canSegment(part))
        }
    }

    @Test("a tie is resolved toward the shorter last segment")
    func canonicalTieBreak() throws {
        let segmenter = try makeWorkedSegmenter()
        let parts = try segmenter.firstSegmentation("authtoken")
        try #require(parts.count == 2)
        #expect(parts == ["auth", "token"])
    }

    @Test("an empty identifier is a segmentation of no segments")
    func emptyIdentifierSegmentation() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(try segmenter.firstSegmentation("") == [])
    }

    @Test("an identifier that does not segment is a typed failure, not a partial split")
    func infeasibleIdentifierFails() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(throws: SegmenterError.noValidSegmentation) {
            try segmenter.firstSegmentation("authtokenexpire")
        }
    }
}

@Suite("Part 3 - Enumerate every segmentation")
struct SegmenterPart3Tests {
    @Test("the worked identifier has exactly two segmentations, shortest first segment first")
    func workedEnumeration() throws {
        let segmenter = try makeWorkedSegmenter()
        let all = segmenter.allSegmentations("authtokenrefresh")
        try #require(all.count == 2)
        #expect(all[0] == ["auth", "token", "refresh"])
        #expect(all[1] == ["authtoken", "refresh"])
    }

    @Test("an identifier that does not segment enumerates nothing")
    func infeasibleEnumeratesNothing() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(segmenter.allSegmentations("authtokenexpire").isEmpty)
    }

    @Test("an empty identifier has exactly one segmentation, and it is empty")
    func emptyIdentifierEnumeration() throws {
        let segmenter = try makeWorkedSegmenter()
        let all = segmenter.allSegmentations("")
        try #require(all.count == 1)
        #expect(all[0] == [])
    }

    @Test("a run of repeats enumerates every way of cutting it")
    func runEnumeration() throws {
        let segmenter = try makeRunSegmenter()
        let all = segmenter.allSegmentations("aaaa")
        try #require(all.count == 7)
        #expect(all.allSatisfy { $0.joined() == "aaaa" })
        #expect(Set(all.map { $0.map(\.count) }).count == 7)
        #expect(all[0] == ["a", "a", "a", "a"])
        #expect(all.map { $0[0].count } == all.map { $0[0].count }.sorted())
    }

    @Test("a long run is counted without enumerating it twice")
    func memoisedLongRun() throws {
        let segmenter = try makeFlatSegmenter(["a", "aa"])
        let identifier = String(repeating: "a", count: 20)
        #expect(segmenter.allSegmentations(identifier).count == 10946)
    }

    @Test("every enumerated segmentation is one the canonical split could have been")
    func enumerationContainsTheCanonicalSplit() throws {
        let segmenter = try makeWorkedSegmenter()
        let canonical = try segmenter.firstSegmentation("authtokenrefresh")
        #expect(segmenter.allSegmentations("authtokenrefresh").contains(canonical))
    }
}

@Suite("Part 4 - Cheapest segmentation")
struct SegmenterPart4Tests {
    @Test("the worked identifier's cheapest split has more segments than its shortest")
    func workedCheapestSegmentation() throws {
        let segmenter = try makeWorkedSegmenter()
        let cheapest = try segmenter.cheapestSegmentation("authtokenrefresh")
        try #require(cheapest.segments.count == 3)
        #expect(cheapest == Segmentation(segments: ["auth", "token", "refresh"], totalPenalty: 3))

        let all = segmenter.allSegmentations("authtokenrefresh")
        try #require(all.count == 2)
        #expect(all[1].count < cheapest.segments.count)
    }

    @Test("the long expensive entry wins once it is cheap enough")
    func cheapestFollowsThePenalties() throws {
        let segmenter = try LogTokenSegmenter(vocabulary: [
            VocabularySegment(text: "auth", penalty: 4),
            VocabularySegment(text: "token", penalty: 4),
            VocabularySegment(text: "authtoken", penalty: 1),
            VocabularySegment(text: "refresh", penalty: 1),
        ])
        let cheapest = try segmenter.cheapestSegmentation("authtokenrefresh")
        try #require(cheapest.segments.count == 2)
        #expect(cheapest.segments == ["authtoken", "refresh"])
        #expect(cheapest.totalPenalty == 2)
    }

    @Test("equal penalties make the cheapest split the one with the fewest segments")
    func equalPenaltiesCountSegments() throws {
        let segmenter = try makeFlatSegmenter(["a", "aa", "aaa"], penalty: 3)
        let cheapest = try segmenter.cheapestSegmentation("aaaaaa")
        try #require(cheapest.segments.count == 2)
        #expect(cheapest.totalPenalty == cheapest.segments.count * 3)
        #expect(cheapest.segments == ["aaa", "aaa"])
    }

    @Test("an empty identifier costs nothing")
    func emptyIdentifierCostsNothing() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(try segmenter.cheapestSegmentation("") == Segmentation(segments: [], totalPenalty: 0))
    }

    @Test("an identifier that does not segment is a typed failure")
    func infeasibleIdentifierFails() throws {
        let segmenter = try makeWorkedSegmenter()
        #expect(throws: SegmenterError.noValidSegmentation) {
            try segmenter.cheapestSegmentation("authtokenexpire")
        }
    }

    @Test("segmenters are independent: one vocabulary never answers for another")
    func segmentersAreIndependent() throws {
        let narrow = try makeFlatSegmenter(["auth", "token"])
        let wide = try makeWorkedSegmenter()

        for _ in 0..<5 {
            _ = wide.allSegmentations("authtokenrefresh")
            _ = try wide.cheapestSegmentation("authtokenrefresh")
        }

        #expect(narrow.canSegment("authtokenrefresh") == false)
        #expect(narrow.canSegment("authtoken"))
        #expect(throws: SegmenterError.noValidSegmentation) {
            try narrow.firstSegmentation("authtokenrefresh")
        }
        #expect(wide.canSegment("authtokenrefresh"))
        #expect(try wide.cheapestSegmentation("authtokenrefresh").totalPenalty == 3)
    }
}
