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
        self.id = id; self.permissions = permissions; self.parentID = parentID
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
        case let .exact(r, a): r == resource && a == action
        case let .anyAction(r): r == resource
        case let .anyResource(a): a == action
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
    private var roles: [String: Role] = [:]
    private var userRoles: [String: Set<String>] = [:]
    public init() {}

    public mutating func createRole(id: String, permissions: Set<Permission> = []) throws(PermissionManagerError) {
        guard roles[id] == nil else { throw PermissionManagerError.duplicateRole(id) }
        roles[id] = Role(id: id, permissions: permissions)
    }

    public mutating func grant(_ permission: Permission, to roleID: String) throws(PermissionManagerError) {
        guard roles[roleID] != nil else { throw PermissionManagerError.unknownRole(roleID) }
        roles[roleID]!.permissions.insert(permission)
    }

    public mutating func revoke(_ permission: Permission, from roleID: String) throws(PermissionManagerError) {
        guard roles[roleID] != nil else { throw PermissionManagerError.unknownRole(roleID) }
        roles[roleID]!.permissions.remove(permission)
    }

    public mutating func assignRole(_ roleID: String, to userID: String) throws(PermissionManagerError) {
        guard roles[roleID] != nil else { throw PermissionManagerError.unknownRole(roleID) }
        userRoles[userID, default: []].insert(roleID)
    }

    public mutating func unassignRole(_ roleID: String, from userID: String) throws(PermissionManagerError) {
        guard roles[roleID] != nil else { throw PermissionManagerError.unknownRole(roleID) }
        guard userRoles[userID]?.contains(roleID) == true else {
            throw PermissionManagerError.roleNotAssigned(userID: userID, roleID: roleID)
        }
        userRoles[userID]!.remove(roleID)
    }

    public func hasPermission(_ permission: Permission, userID: String) -> Bool {
        allPermissions(for: userID).contains(permission)
    }

    public func allPermissions(for userID: String) -> Set<Permission> {
        (userRoles[userID] ?? []).reduce(into: []) { result, roleID in
            if let permissions = try? permissions(forRole: roleID) { result.formUnion(permissions) }
        }
    }

    public func permissions(forRole roleID: String) throws(PermissionManagerError) -> Set<Permission> {
        guard let role = roles[roleID] else { throw PermissionManagerError.unknownRole(roleID) }
        guard let parentID = role.parentID else { return role.permissions }
        return try role.permissions.union(permissions(forRole: parentID))
    }

    public mutating func setParentRole(_ parentRoleID: String, for roleID: String) throws(PermissionManagerError) {
        guard roles[roleID] != nil else { throw PermissionManagerError.unknownRole(roleID) }
        guard roles[parentRoleID] != nil else { throw PermissionManagerError.unknownRole(parentRoleID) }
        roles[roleID]!.parentID = parentRoleID
    }

    public func hasScopedPermission(userID: String, resource: String, action: String) -> Bool {
        allPermissions(for: userID).contains { permission in
            PermissionPattern(permission)?.matches(resource: resource, action: action) == true
        }
    }
}
