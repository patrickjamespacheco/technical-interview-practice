// Problem 03: Permission Manager (RBAC)
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build an in-memory role-based access-control engine in three cumulative parts.
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in this value. Use readable string IDs.
//
// Part 1: create roles, grant/revoke permissions, assign/unassign roles, and query.
// Part 2: add single-parent, transitive role inheritance.
// Part 3: match exact and wildcard scoped permissions.
//
// Example (this file compiles before implementation):
//   var manager = PermissionManager()
//   try manager.createRole(id: "admin", permissions: [Permission("users:write")])
//   try manager.assignRole("admin", to: "alice")
//   let allowed = manager.hasPermission(Permission("users:write"), userID: "alice")

public struct Permission: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

public struct Role: Equatable, Sendable {
    public let id: String
    public var permissions: Set<Permission>
    public var parentID: String?
    public init(id: String, permissions: Set<Permission> = [], parentID: String? = nil) {
        self.id = id
        self.permissions = permissions
        self.parentID = parentID
    }
}

public enum PermissionPattern: Equatable, Sendable {
    case exact(resource: String, action: String)
    case anyAction(resource: String)
    case anyResource(action: String)
    case any

    public init?(_ permission: Permission) {
        let pieces = permission.rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        let resource = String(pieces[0]), action = String(pieces[1])
        switch (resource, action) {
        case ("*", "*"): self = .any
        case ("*", _): self = .anyResource(action: action)
        case (_, "*"): self = .anyAction(resource: resource)
        default: self = .exact(resource: resource, action: action)
        }
    }

    public func matches(resource: String, action: String) -> Bool {
        switch self {
        case let .exact(expectedResource, expectedAction): expectedResource == resource && expectedAction == action
        case let .anyAction(expectedResource): expectedResource == resource
        case let .anyResource(expectedAction): expectedAction == action
        case .any: true
        }
    }
}

public enum PermissionManagerError: Error, Equatable, Sendable {
    case duplicateRole(String)
    case unknownRole(String)
    case roleNotAssigned(userID: String, roleID: String)
    case notImplemented
}

public protocol PermissionChecking {
    func hasPermission(_ permission: Permission, userID: String) -> Bool
    func hasScopedPermission(userID: String, resource: String, action: String) -> Bool
}

public struct PermissionManager: PermissionChecking, Sendable {
    public init() {}

    // MARK: Part 1 — flat roles and permissions
    public mutating func createRole(id: String, permissions: Set<Permission> = []) throws(PermissionManagerError) { throw .notImplemented }
    public mutating func grant(_ permission: Permission, to roleID: String) throws(PermissionManagerError) { throw .notImplemented }
    public mutating func revoke(_ permission: Permission, from roleID: String) throws(PermissionManagerError) { throw .notImplemented }
    public mutating func assignRole(_ roleID: String, to userID: String) throws(PermissionManagerError) { throw .notImplemented }
    public mutating func unassignRole(_ roleID: String, from userID: String) throws(PermissionManagerError) { throw .notImplemented }
    public func hasPermission(_ permission: Permission, userID: String) -> Bool { false }
    public func allPermissions(for userID: String) -> Set<Permission> { [] }
    public func permissions(forRole roleID: String) throws(PermissionManagerError) -> Set<Permission> { throw .notImplemented }

    // MARK: Part 2 — inheritance
    public mutating func setParentRole(_ parentRoleID: String, for roleID: String) throws(PermissionManagerError) { throw .notImplemented }

    // MARK: Part 3 — scoped wildcard matching
    public func hasScopedPermission(userID: String, resource: String, action: String) -> Bool { false }
}
