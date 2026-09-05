import Testing
@testable import Problem73CoursePrerequisiteOrder

private func makePlanner() -> CoursePlanner { CoursePlanner() }

// Check the contract, not one arbitrary choice among valid topological orders.
private func requireValidOrder(_ order: [String], for courses: [Course]) throws {
    try #require(order.count == courses.count)
    try #require(Set(order) == Set(courses.map(\.id)))
    let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    for course in courses {
        let position = try #require(positions[course.id])
        for prerequisite in course.prerequisites {
            let prerequisitePosition = try #require(positions[prerequisite])
            #expect(prerequisitePosition < position)
        }
    }
}

private func requireWaves(_ waves: [[String]], for courses: [Course], matching expected: [Set<String>]) throws {
    try requireValidOrder(waves.flatMap { $0 }, for: courses)
    #expect(waves.map { Set($0) } == expected)
}

@Suite("Part 1 — A valid order")
struct CoursePrerequisiteOrderPart1Tests {
    @Test("a chain has one order even when input arrives backwards")
    func chain() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "chain-app", prerequisites: ["chain-swift"]),
            Course(id: "chain-swift", prerequisites: ["chain-basics"]),
            Course(id: "chain-basics"),
        ]
        #expect(try planner.order(courses) == ["chain-basics", "chain-swift", "chain-app"])
    }

    @Test("several valid orders are accepted by their dependency property")
    func branchingAndJoining() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "branch-app", prerequisites: ["branch-ui", "branch-data"]),
            Course(id: "branch-data", prerequisites: ["branch-basics"]),
            Course(id: "branch-basics"),
            Course(id: "branch-ui", prerequisites: ["branch-basics"]),
        ]
        try requireValidOrder(planner.order(courses), for: courses)
    }

    @Test("empty input has an empty order")
    func empty() throws {
        let planner = makePlanner()
        #expect(try planner.order([]) == [])
    }

    @Test("one independent course is included")
    func single() throws {
        let planner = makePlanner()
        #expect(try planner.order([Course(id: "single-order")]) == ["single-order"])
    }

    @Test("disconnected chains and an isolated course are all included")
    func disconnected() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "disconnected-ui", prerequisites: ["disconnected-design"]),
            Course(id: "disconnected-data", prerequisites: ["disconnected-math"]),
            Course(id: "disconnected-design"),
            Course(id: "disconnected-independent"),
            Course(id: "disconnected-math"),
        ]
        try requireValidOrder(planner.order(courses), for: courses)
    }

    @Test("all independent courses appear exactly once in any order")
    func independent() throws {
        let planner = makePlanner()
        let courses = ["independent-z", "independent-a", "independent-m"].map { Course(id: $0) }
        try requireValidOrder(planner.order(courses), for: courses)
    }

    @Test("a course waits for every prerequisite, including a transitive one")
    func multiplePrerequisites() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "multiple-end", prerequisites: ["multiple-root", "multiple-middle", "multiple-other"]),
            Course(id: "multiple-root"),
            Course(id: "multiple-middle", prerequisites: ["multiple-root"]),
            Course(id: "multiple-other"),
        ]
        try requireValidOrder(planner.order(courses), for: courses)
    }

    @Test("two planners agree after repeated use and leave caller input unchanged")
    func isolation() throws {
        let first = makePlanner()
        let second = makePlanner()
        let courses = [
            Course(id: "isolation-end", prerequisites: ["isolation-start"]),
            Course(id: "isolation-start"),
        ]
        let original = courses
        for _ in 0..<4 {
            #expect(try first.order(courses) == ["isolation-start", "isolation-end"])
            #expect(try first.order([Course(id: "isolation-unrelated")]) == ["isolation-unrelated"])
        }
        #expect(try second.order(courses) == ["isolation-start", "isolation-end"])
        #expect(try first.order(courses) == second.order(courses))
        #expect(courses == original)
    }
}

@Suite("Part 2 — Detect a cycle")
struct CoursePrerequisiteOrderPart2Tests {
    @Test("acyclic and empty inputs can finish")
    func finishable() throws {
        let planner = makePlanner()
        #expect(try planner.canFinish([]))
        #expect(try planner.canFinish([Course(id: "finishable-single")]))
        #expect(try planner.canFinish([
            Course(id: "finishable-end", prerequisites: ["finishable-start"]),
            Course(id: "finishable-start"),
        ]))
    }

    @Test("a directed cycle is reported instead of returning an order")
    func cycle() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "cycle-a", prerequisites: ["cycle-b"]),
            Course(id: "cycle-b", prerequisites: ["cycle-c"]),
            Course(id: "cycle-c", prerequisites: ["cycle-a"]),
        ]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.order(courses) }
        #expect(try !planner.canFinish(courses))
    }

    @Test("a self prerequisite is a cycle")
    func selfCycle() throws {
        let planner = makePlanner()
        let courses = [Course(id: "self-cycle", prerequisites: ["self-cycle"])]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.order(courses) }
        #expect(try !planner.canFinish(courses))
    }

    @Test("a ready prefix does not hide a cycle or its blocked downstream course")
    func blockedRemainder() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "blocked-ready"),
            Course(id: "blocked-a", prerequisites: ["blocked-ready", "blocked-b"]),
            Course(id: "blocked-b", prerequisites: ["blocked-a"]),
            Course(id: "blocked-tail", prerequisites: ["blocked-b"]),
        ]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.order(courses) }
        #expect(try !planner.canFinish(courses))
    }

    @Test("a completed disconnected component does not make the whole graph finishable")
    func disconnectedCycle() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "mixed-free"),
            Course(id: "mixed-end", prerequisites: ["mixed-free"]),
            Course(id: "mixed-a", prerequisites: ["mixed-b"]),
            Course(id: "mixed-b", prerequisites: ["mixed-a"]),
        ]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.order(courses) }
        #expect(try !planner.canFinish(courses))
        #expect(try planner.canFinish([Course(id: "mixed-next-call")]))
    }

    @Test("all 64 directed three-course graphs agree with an independent permutation oracle")
    func exhaustiveSmallGraphs() throws {
        let planner = makePlanner()
        let ids = ["exhaustive-a", "exhaustive-b", "exhaustive-c"]
        let edges = ids.flatMap { before in ids.filter { $0 != before }.map { (before, $0) } }
        // Enumeration, not another in-degree traversal: an order exists exactly
        // when one permutation puts every prerequisite before its course.
        let permutations = ids.flatMap { first in
            ids.filter { $0 != first }.map { second in
                [first, second] + ids.filter { $0 != first && $0 != second }
            }
        }
        for mask in 0..<(1 << edges.count) {
            let chosen = edges.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let courses = ids.map { id in
                Course(id: id, prerequisites: chosen.filter { $0.1 == id }.map { $0.0 })
            }
            let hasOrder = permutations.contains { candidate in
                chosen.allSatisfy { edge in candidate.firstIndex(of: edge.0)! < candidate.firstIndex(of: edge.1)! }
            }
            #expect(try planner.canFinish(courses) == hasOrder)
            if hasOrder {
                try requireValidOrder(planner.order(courses), for: courses)
            } else {
                #expect(throws: CoursePlanError.cycleDetected) { try planner.order(courses) }
            }
        }
    }
}

@Suite("Part 3 — Parallel waves")
struct CoursePrerequisiteOrderPart3Tests {
    @Test("empty input has no waves")
    func empty() throws {
        let planner = makePlanner()
        #expect(try planner.parallelWaves([]) == [])
    }

    @Test("a single course has one wave")
    func single() throws {
        let planner = makePlanner()
        #expect(try planner.parallelWaves([Course(id: "single-wave")]) == [["single-wave"]])
    }

    @Test("all ready courses belong to the same wave")
    func independent() throws {
        let planner = makePlanner()
        let courses = ["wave-z", "wave-a", "wave-m"].map { Course(id: $0) }
        try requireWaves(planner.parallelWaves(courses), for: courses, matching: [Set(courses.map(\.id))])
    }

    @Test("newly unlocked courses wait for the next wave")
    func chain() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "waves-last", prerequisites: ["waves-middle"]),
            Course(id: "waves-first"),
            Course(id: "waves-middle", prerequisites: ["waves-first"]),
        ]
        #expect(try planner.parallelWaves(courses) == [["waves-first"], ["waves-middle"], ["waves-last"]])
    }

    @Test("branching courses run together and their join waits for both")
    func diamond() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "diamond-app", prerequisites: ["diamond-ui", "diamond-data"]),
            Course(id: "diamond-basics"),
            Course(id: "diamond-ui", prerequisites: ["diamond-basics"]),
            Course(id: "diamond-data", prerequisites: ["diamond-basics"]),
        ]
        try requireWaves(planner.parallelWaves(courses), for: courses, matching: [
            ["diamond-basics"], ["diamond-ui", "diamond-data"], ["diamond-app"],
        ])
    }

    @Test("disconnected components share waves and a join waits for its longest prerequisite chain")
    func unequalDepths() throws {
        let planner = makePlanner()
        let courses = [
            Course(id: "depth-join", prerequisites: ["depth-short", "depth-middle"]),
            Course(id: "depth-short"),
            Course(id: "depth-long"),
            Course(id: "depth-middle", prerequisites: ["depth-long"]),
            Course(id: "depth-isolated"),
            Course(id: "depth-other-end", prerequisites: ["depth-other-start"]),
            Course(id: "depth-other-start"),
        ]
        let waves = try planner.parallelWaves(courses)
        try requireWaves(waves, for: courses, matching: [
            ["depth-short", "depth-long", "depth-isolated", "depth-other-start"],
            ["depth-middle", "depth-other-end"],
            ["depth-join"],
        ])
        try requireValidOrder(planner.order(courses), for: courses)
        #expect(try planner.canFinish(courses))
    }

    @Test("a cycle produces no successful waves")
    func cycle() {
        let planner = makePlanner()
        let courses = [Course(id: "wave-self", prerequisites: ["wave-self"])]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.parallelWaves(courses) }
    }

    @Test("completed waves cannot hide a disconnected cycle")
    func partialWaves() {
        let planner = makePlanner()
        let courses = [
            Course(id: "partial-ready"),
            Course(id: "partial-next", prerequisites: ["partial-ready"]),
            Course(id: "partial-a", prerequisites: ["partial-b"]),
            Course(id: "partial-b", prerequisites: ["partial-a"]),
        ]
        #expect(throws: CoursePlanError.cycleDetected) { try planner.parallelWaves(courses) }
    }
}
