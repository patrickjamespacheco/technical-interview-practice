import Foundation
import Testing
@testable import Problem02APIRateLimiter

private let base = Date(timeIntervalSince1970: 1_700_000_000)
private let plans = [
    "free": Plan(requestsPerMinute: 3, requestsPerDay: 10),
    "pro": Plan(requestsPerMinute: 100, requestsPerDay: 5_000),
    "unlimited": Plan(requestsPerMinute: nil, requestsPerDay: nil)
]
private func makeFreshLimiter(now: Date = base) -> APIRateLimiter {
    APIRateLimiter(plans: plans, now: { now })
}
private func makeSeededLimiter(now: Date = base) async throws -> APIRateLimiter {
    let limiter = makeFreshLimiter(now: now)
    try await limiter.createKey(id: "pk.seed", owner: "alice", planID: "pro")
    return limiter
}

@Suite("Part 1 — Keys and rich rate decisions")
struct RateLimiterPart1 {
    @Test("key lifecycle is validated and preserves identity")
    func lifecycle() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.lifecycle", owner: "alice", planID: "free")
        await #expect(throws: APIRateLimiterError.duplicateKey("pk.lifecycle")) {
            try await limiter.createKey(id: "pk.lifecycle", owner: "bob", planID: "pro")
        }
        await #expect(throws: APIRateLimiterError.unknownPlan("missing-plan")) {
            try await limiter.updatePlan(for: "pk.lifecycle", to: "missing-plan")
        }
        try await limiter.updatePlan(for: "pk.lifecycle", to: "pro")
        let decision = await limiter.evaluate("pk.lifecycle", at: base)
        guard case let .allowed(usage) = decision else { Issue.record("expected allowed decision"); return }
        #expect(usage.planID == "pro")
    }

    @Test("missing and revoked keys have associated denial context")
    func keyDenials() async throws {
        let limiter = try await makeSeededLimiter()
        #expect(await limiter.evaluate("pk.missing", at: base) == .denied(.keyNotFound(keyID: "pk.missing")))
        try await limiter.revokeKey("pk.seed")
        #expect(await limiter.evaluate("pk.seed", at: base) == .denied(.keyDisabled(keyID: "pk.seed")))
        await #expect(throws: APIRateLimiterError.unknownKey("pk.ghost-revoke")) {
            try await limiter.revokeKey("pk.ghost-revoke")
        }
    }

    @Test("the injected clock drives omitted dates")
    func injectedClock() async throws {
        let injected = base.addingTimeInterval(500)
        let limiter = makeFreshLimiter(now: injected)
        try await limiter.createKey(id: "pk.clock", owner: "clock-owner", planID: "free")
        guard case let .allowed(usage) = await limiter.evaluate("pk.clock") else {
            Issue.record("expected injected-clock evaluation to be allowed"); return
        }
        #expect(usage.minuteUsed == 0)
    }

    @Test("actors own independent key state")
    func isolation() async throws {
        let first = makeFreshLimiter(), second = makeFreshLimiter()
        try await first.createKey(id: "pk.isolation", owner: "alice", planID: "free")
        #expect(await first.evaluate("pk.isolation", at: base) != .denied(.keyNotFound(keyID: "pk.isolation")))
        #expect(await second.evaluate("pk.isolation", at: base) == .denied(.keyNotFound(keyID: "pk.isolation")))
    }
}

@Suite("Part 2 — Atomic request handling")
struct RateLimiterPart2 {
    @Test("handling records atomically and returns updated usage")
    func allowedHandling() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.allowed", owner: "alice", planID: "free")
        guard case let .allowed(first) = await limiter.handleRequest("pk.allowed", at: base) else {
            Issue.record("first request should pass"); return
        }
        #expect(first.minuteUsed == 1)
        guard case let .allowed(second) = await limiter.handleRequest("pk.allowed", at: base.addingTimeInterval(1)) else {
            Issue.record("second request should pass"); return
        }
        #expect(second.minuteUsed == 2)
    }

    @Test("concurrent actor calls cannot exceed the cap")
    func concurrentCap() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.concurrent", owner: "alice", planID: "free")
        let decisions = await withTaskGroup(of: RateLimitDecision.self, returning: [RateLimitDecision].self) { group in
            for _ in 0..<8 {
                group.addTask { await limiter.handleRequest("pk.concurrent", at: base) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let allowedCount = decisions.filter { if case .allowed = $0 { true } else { false } }.count
        #expect(allowedCount == 3)
        #expect(decisions.contains(.denied(.perMinuteExceeded(limit: 3, used: 3))))
    }

    @Test("minute precedes day denial and denied requests do not mutate")
    func denialPriority() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.priority", owner: "alice", planID: "free")
        for offset in 0..<3 { _ = await limiter.handleRequest("pk.priority", at: base.addingTimeInterval(Double(offset))) }
        #expect(await limiter.handleRequest("pk.priority", at: base.addingTimeInterval(3)) == .denied(.perMinuteExceeded(limit: 3, used: 3)))
        #expect(await limiter.evaluate("pk.priority", at: base.addingTimeInterval(3)) == .denied(.perMinuteExceeded(limit: 3, used: 3)))
    }

    @Test("day windows roll forward without sleeps")
    func dayWindow() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.day", owner: "alice", planID: "free")
        for hour in 1...10 { _ = await limiter.handleRequest("pk.day", at: base.addingTimeInterval(Double(hour * 3600))) }
        let now = base.addingTimeInterval(10 * 3600 + 1)
        #expect(await limiter.evaluate("pk.day", at: now) == .denied(.perDayExceeded(limit: 10, used: 10)))
        #expect(await limiter.evaluate("pk.day", at: base.addingTimeInterval(26 * 3600)) != .denied(.perDayExceeded(limit: 10, used: 10)))
    }
}

@Suite("Part 3 — Usage and immutable snapshots")
struct RateLimiterPart3 {
    @Test("usage separates minute and day counts")
    func usage() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.usage", owner: "alice", planID: "pro")
        _ = await limiter.handleRequest("pk.usage", at: base.addingTimeInterval(-3_600))
        _ = await limiter.handleRequest("pk.usage", at: base.addingTimeInterval(-30))
        let usage = try await limiter.usage(for: "pk.usage", at: base)
        #expect(usage.minuteUsed == 1)
        #expect(usage.dayUsed == 2)
        #expect(usage.minuteLimit == 100)
    }

    @Test("snapshots are sorted value copies")
    func snapshots() async throws {
        let limiter = makeFreshLimiter()
        try await limiter.createKey(id: "pk.zed", owner: "zed", planID: "free")
        try await limiter.createKey(id: "pk.alpha", owner: "alpha", planID: "unlimited")
        let first = await limiter.keySnapshots()
        _ = await limiter.handleRequest("pk.alpha", at: base)
        let second = await limiter.keySnapshots()
        #expect(first.map(\.id) == ["pk.alpha", "pk.zed"])
        // Establish the counts before indexing, so empty snapshots fail here
        // instead of trapping and taking down the whole run.
        try #require(!first.isEmpty && !second.isEmpty)
        #expect(first[0].requestDates.isEmpty)
        #expect(second[0].requestDates == [base])
    }
}
