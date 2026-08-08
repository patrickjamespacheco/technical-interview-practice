import Testing
@testable import Problem03PermissionManager

private func makeFreshManager() -> PermissionManager { PermissionManager() }
private func makeSeededManager() throws -> PermissionManager {
    var manager = PermissionManager()
    try manager.createRole(id: "viewer", permissions: ["posts:read", "comments:read"])
    try manager.createRole(id: "editor", permissions: ["posts:write", "comments:write"])
    try manager.createRole(id: "admin", permissions: ["billing:read", "users:write"])
    return manager
}

@Suite("Part 1 — Flat roles and permissions")
struct Part1 {
    @Test("roles default empty and reject duplicate IDs")
    func roles() throws {
        var manager = makeFreshManager()
        try manager.createRole(id: "role_empty_test")
        #expect(try manager.permissions(forRole: "role_empty_test") == [])
        #expect(throws: PermissionManagerError.duplicateRole("role_empty_test")) {
            try manager.createRole(id: "role_empty_test")
        }
    }

    @Test("grant and revoke are idempotent; unknown roles throw")
    func mutation() throws {
        var manager = try makeSeededManager()
        try manager.grant("posts:write", to: "viewer")
        try manager.grant("posts:write", to: "viewer")
        #expect(try manager.permissions(forRole: "viewer").contains("posts:write"))
        try manager.revoke("posts:write", from: "viewer")
        try manager.revoke("posts:write", from: "viewer")
        #expect(throws: PermissionManagerError.unknownRole("ghost_grant_test")) {
            try manager.grant("posts:read", to: "ghost_grant_test")
        }
    }

    @Test("multiple assigned roles compose and unassignment is typed")
    func assignment() throws {
        var manager = try makeSeededManager()
        try manager.assignRole("viewer", to: "alice_assignment_test")
        try manager.assignRole("admin", to: "alice_assignment_test")
        #expect(manager.hasPermission("posts:read", userID: "alice_assignment_test"))
        #expect(manager.hasPermission("billing:read", userID: "alice_assignment_test"))
        try manager.unassignRole("admin", from: "alice_assignment_test")
        #expect(!manager.hasPermission("billing:read", userID: "alice_assignment_test"))
        #expect(throws: PermissionManagerError.roleNotAssigned(userID: "alice_assignment_test", roleID: "editor")) {
            try manager.unassignRole("editor", from: "alice_assignment_test")
        }
    }

    @Test("unknown users have no permissions")
    func unknownUser() {
        let manager = makeFreshManager()
        #expect(manager.allPermissions(for: "unknown_user_test").isEmpty)
        #expect(!manager.hasPermission("posts:read", userID: "unknown_user_test"))
    }

    @Test("instances own independent state")
    func isolation() throws {
        var first = makeFreshManager()
        let second = makeFreshManager()
        try first.createRole(id: "isolation_role", permissions: ["reports:read"])
        #expect(try first.permissions(forRole: "isolation_role") == ["reports:read"])
        #expect(throws: PermissionManagerError.unknownRole("isolation_role")) {
            try second.permissions(forRole: "isolation_role")
        }
    }
}

@Suite("Part 2 — Role inheritance")
struct Part2 {
    @Test("inheritance is transitive and parent replacement takes effect")
    func inheritance() throws {
        var manager = makeFreshManager()
        try manager.createRole(id: "base_a", permissions: ["a:read"])
        try manager.createRole(id: "base_b", permissions: ["b:read"])
        try manager.createRole(id: "mid", permissions: ["mid:write"])
        try manager.createRole(id: "top", permissions: ["top:admin"])
        try manager.setParentRole("base_a", for: "mid")
        try manager.setParentRole("mid", for: "top")
        #expect(try manager.permissions(forRole: "top") == ["a:read", "mid:write", "top:admin"])
        try manager.setParentRole("base_b", for: "mid")
        #expect(try manager.permissions(forRole: "top") == ["b:read", "mid:write", "top:admin"])
    }

    @Test("assigned users receive inherited but not sibling permissions")
    func userInheritance() throws {
        var manager = try makeSeededManager()
        try manager.setParentRole("viewer", for: "editor")
        try manager.assignRole("editor", to: "alice_inheritance_test")
        #expect(manager.hasPermission("posts:read", userID: "alice_inheritance_test"))
        #expect(!manager.hasPermission("billing:read", userID: "alice_inheritance_test"))
    }
}

@Suite("Part 3 — Scoped permissions")
struct Part3 {
    @Test("exact, action, resource, and universal patterns match")
    func patterns() throws {
        var manager = makeFreshManager()
        try manager.createRole(id: "scoped_patterns", permissions: ["posts:read", "comments:*", "*:delete", "*:*", "plain"])
        try manager.assignRole("scoped_patterns", to: "alice_scoped_test")
        #expect(manager.hasScopedPermission(userID: "alice_scoped_test", resource: "posts", action: "read"))
        #expect(manager.hasScopedPermission(userID: "alice_scoped_test", resource: "comments", action: "write"))
        #expect(manager.hasScopedPermission(userID: "alice_scoped_test", resource: "users", action: "delete"))
        #expect(manager.hasScopedPermission(userID: "alice_scoped_test", resource: "anything", action: "everything"))
        #expect(!manager.hasScopedPermission(userID: "unknown_scoped_test", resource: "posts", action: "read"))
    }

    @Test("plain permissions are ignored and inherited wildcards apply")
    func inheritedWildcard() throws {
        var manager = makeFreshManager()
        try manager.createRole(id: "plain_parent", permissions: ["plain_permission"])
        try manager.createRole(id: "wild_parent", permissions: ["billing:*"])
        try manager.createRole(id: "child_scoped", permissions: [])
        try manager.setParentRole("wild_parent", for: "child_scoped")
        try manager.assignRole("child_scoped", to: "bob_scoped_test")
        #expect(manager.hasScopedPermission(userID: "bob_scoped_test", resource: "billing", action: "write"))
        try manager.assignRole("plain_parent", to: "charlie_plain_test")
        #expect(!manager.hasScopedPermission(userID: "charlie_plain_test", resource: "plain_permission", action: "read"))
    }
}
