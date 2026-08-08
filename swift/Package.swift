// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TechnicalInterviewPractice",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Problem03PermissionManager", targets: ["Problem03PermissionManager"])],
    targets: [
        .target(name: "Problem03PermissionManager"),
        .testTarget(name: "Problem03PermissionManagerTests", dependencies: ["Problem03PermissionManager"])
    ]
)
