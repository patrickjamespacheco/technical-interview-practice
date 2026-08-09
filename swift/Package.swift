// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TechnicalInterviewPractice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Problem03PermissionManager", targets: ["Problem03PermissionManager"]),
        .library(name: "Problem18InventoryReservationLedger", targets: ["Problem18InventoryReservationLedger"]),
        .library(name: "Problem10DispatchManager", targets: ["Problem10DispatchManager"]),
        .library(name: "Problem05MedicationTitration", targets: ["Problem05MedicationTitration"]),
        .library(name: "Problem13ContractLifecycle", targets: ["Problem13ContractLifecycle"]),
        .library(name: "Problem15TicTacToeEngine", targets: ["Problem15TicTacToeEngine"])
    ],
    targets: [
        .target(name: "Problem03PermissionManager"),
        .testTarget(name: "Problem03PermissionManagerTests", dependencies: ["Problem03PermissionManager"]),
        .target(name: "Problem18InventoryReservationLedger"),
        .testTarget(name: "Problem18InventoryReservationLedgerTests", dependencies: ["Problem18InventoryReservationLedger"]),
        .target(name: "Problem10DispatchManager"),
        .testTarget(name: "Problem10DispatchManagerTests", dependencies: ["Problem10DispatchManager"]),
        .target(name: "Problem05MedicationTitration"),
        .testTarget(name: "Problem05MedicationTitrationTests", dependencies: ["Problem05MedicationTitration"]),
        .target(name: "Problem13ContractLifecycle"),
        .testTarget(name: "Problem13ContractLifecycleTests", dependencies: ["Problem13ContractLifecycle"]),
        .target(name: "Problem15TicTacToeEngine"),
        .testTarget(name: "Problem15TicTacToeEngineTests", dependencies: ["Problem15TicTacToeEngine"])
    ]
)
