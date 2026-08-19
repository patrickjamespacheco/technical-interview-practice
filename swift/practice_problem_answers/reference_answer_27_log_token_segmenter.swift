/// One known segment in the service registry's vocabulary, with the confidence
/// penalty the pipeline pays for using it. Lower is more confident.
public struct VocabularySegment: Equatable, Sendable {
    public let text: String
    public let penalty: Int

    public init(text: String, penalty: Int) {
        self.text = text
        self.penalty = penalty
    }
}

/// A segmentation and what it costs.
public struct Segmentation: Equatable, Sendable {
    public let segments: [String]
    public let totalPenalty: Int

    public init(segments: [String], totalPenalty: Int) {
        self.segments = segments
        self.totalPenalty = totalPenalty
    }
}

public enum SegmenterError: Error, Equatable, Sendable {
    case emptyVocabulary
    case emptySegmentText
    case negativePenalty(String)
    case duplicateSegmentText(String)
    case noValidSegmentation
    case notImplemented
}

public struct LogTokenSegmenter: Sendable {
    /// The vocabulary, arranged for the two questions the scan actually asks:
    /// is this piece known, and what does it cost. The longest entry bounds the
    /// inner loop, so a scan never proposes a piece no entry could match.
    private let penalties: [String: Int]
    private let longestSegmentLength: Int

    public init(vocabulary: [VocabularySegment]) throws(SegmenterError) {
        guard !vocabulary.isEmpty else { throw .emptyVocabulary }

        var penalties: [String: Int] = [:]
        for segment in vocabulary {
            guard !segment.text.isEmpty else { throw .emptySegmentText }
            guard segment.penalty >= 0 else { throw .negativePenalty(segment.text) }
            guard penalties[segment.text] == nil else { throw .duplicateSegmentText(segment.text) }
            penalties[segment.text] = segment.penalty
        }

        self.penalties = penalties
        self.longestSegmentLength = vocabulary.map(\.text.count).max() ?? 0
    }

    // MARK: Part 1 - Can the identifier be segmented?

    /// Whether the identifier is entirely covered by known segments.
    ///
    /// One entry means "the first i characters split cleanly", so the empty
    /// prefix is the base case and it is true: nothing left to cover is covered.
    public func canSegment(_ identifier: String) -> Bool {
        let characters = Array(identifier)
        return reachability(characters).feasible[characters.count]
    }

    // MARK: Part 2 - Return one canonical segmentation

    /// One segmentation, chosen canonically: at every cut the shortest possible
    /// last segment wins, because the split points are scanned from the closest
    /// one backwards and the first that works is recorded.
    public func firstSegmentation(_ identifier: String) throws(SegmenterError) -> [String] {
        let characters = Array(identifier)
        let table = reachability(characters)
        guard table.feasible[characters.count] else { throw .noValidSegmentation }
        return rebuild(from: table.previousCut, characters: characters)
    }

    // MARK: Part 3 - Enumerate every segmentation

    /// Every segmentation of the identifier, ordered by ascending first-segment
    /// length, and recursively so within each branch.
    ///
    /// Part 1's table answers "is there one". It cannot answer "give me all of
    /// them", because the answer is not a number and no single entry can hold a
    /// growing list of splits cheaply. So the shape changes from a table walked
    /// forwards to a recursion over start positions, and the memo is what keeps
    /// the work per position bounded. The memo bounds the work, not the size of
    /// the output: an identifier can genuinely have exponentially many splits.
    public func allSegmentations(_ identifier: String) -> [[String]] {
        let characters = Array(identifier)
        guard canSegment(identifier) else { return [] }

        var memo: [Int: [[String]]] = [:]

        func segmentations(from start: Int) -> [[String]] {
            if let cached = memo[start] { return cached }
            if start == characters.count { return [[]] }

            var found: [[String]] = []
            let furthest = min(characters.count, start + longestSegmentLength)
            for end in stride(from: start + 1, through: furthest, by: 1) {
                let piece = String(characters[start..<end])
                guard penalties[piece] != nil else { continue }
                for rest in segmentations(from: end) {
                    found.append([piece] + rest)
                }
            }

            memo[start] = found
            return found
        }

        return segmentations(from: 0)
    }

    // MARK: Part 4 - Cheapest segmentation

    /// The least-penalty segmentation. Fewer segments is not automatically
    /// cheaper, which is why this cannot be read off Part 2's answer.
    ///
    /// This is Part 1's loop with a minimum in place of the disjunction, and it
    /// hands its cut record to the same rebuild helper Part 2 uses. Ties resolve
    /// to the shorter last segment, matching Part 2's canonical order, because
    /// the strict comparison keeps the first cut a backwards scan reaches.
    public func cheapestSegmentation(_ identifier: String) throws(SegmenterError) -> Segmentation {
        let characters = Array(identifier)
        let unreachable = Int.max

        var cost = Array(repeating: unreachable, count: characters.count + 1)
        var previousCut = Array(repeating: Int?.none, count: characters.count + 1)
        cost[0] = 0

        for end in stride(from: 1, through: characters.count, by: 1) {
            for start in cuts(before: end) where cost[start] != unreachable {
                guard let penalty = penalties[String(characters[start..<end])] else { continue }
                if cost[start] + penalty < cost[end] {
                    cost[end] = cost[start] + penalty
                    previousCut[end] = start
                }
            }
        }

        guard cost[characters.count] != unreachable else { throw .noValidSegmentation }
        return Segmentation(
            segments: rebuild(from: previousCut, characters: characters),
            totalPenalty: cost[characters.count]
        )
    }

    // MARK: Shared machinery

    /// The split points that could begin the last segment ending at `end`,
    /// nearest first. Nearest first is what makes the canonical segmentation
    /// prefer the shorter last segment, and bounding the scan by the longest
    /// vocabulary entry keeps it from proposing pieces nothing could match.
    private func cuts(before end: Int) -> StrideThrough<Int> {
        stride(from: end - 1, through: max(0, end - longestSegmentLength), by: -1)
    }

    /// Whether each prefix splits cleanly, and where the last segment of that
    /// prefix began. Part 1 reads the final flag; Part 2 walks the cuts back.
    private func reachability(_ characters: [Character]) -> (feasible: [Bool], previousCut: [Int?]) {
        var feasible = Array(repeating: false, count: characters.count + 1)
        var previousCut = Array(repeating: Int?.none, count: characters.count + 1)
        feasible[0] = true

        for end in stride(from: 1, through: characters.count, by: 1) {
            for start in cuts(before: end) where feasible[start] {
                if penalties[String(characters[start..<end])] != nil {
                    feasible[end] = true
                    previousCut[end] = start
                    break
                }
            }
        }

        return (feasible, previousCut)
    }

    /// Walks a cut record back from the whole identifier to the empty prefix and
    /// turns it into segments in reading order.
    private func rebuild(from previousCut: [Int?], characters: [Character]) -> [String] {
        var reversedSegments: [String] = []
        var end = characters.count
        while end > 0, let start = previousCut[end] {
            reversedSegments.append(String(characters[start..<end]))
            end = start
        }
        return reversedSegments.reversed()
    }
}
