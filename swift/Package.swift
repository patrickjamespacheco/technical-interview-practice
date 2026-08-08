// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TechnicalInterviewPractice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Problem03PermissionManager", targets: ["Problem03PermissionManager"]),
        .library(name: "Problem18InventoryReservationLedger", targets: ["Problem18InventoryReservationLedger"])
    ],
    targets: [
        .target(name: "Problem03PermissionManager"),
        .testTarget(name: "Problem03PermissionManagerTests", dependencies: ["Problem03PermissionManager"]),
        .target(name: "Problem18InventoryReservationLedger"),
        .testTarget(name: "Problem18InventoryReservationLedgerTests", dependencies: ["Problem18InventoryReservationLedger"])
    ]
)
