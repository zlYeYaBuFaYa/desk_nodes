// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "DeskNodesCore", targets: ["DeskNodesCore"]),
    .library(name: "DeskNodesPersistence", targets: ["DeskNodesPersistence"])]
var targets: [Target] = [
    .target(name: "DeskNodesCore"),
    .target(name: "DeskNodesActions", dependencies: ["DeskNodesPersistence"]),
    .testTarget(name: "DeskNodesActionsTests", dependencies: ["DeskNodesActions"]),
    .systemLibrary(name: "CSQLite"), // module map links sqlite3; SDK/system headers, no pkg-config
    .target(name: "DeskNodesPersistence", dependencies: ["DeskNodesCore", "CSQLite"]),
    .testTarget(name: "DeskNodesPersistenceTests", dependencies: ["DeskNodesPersistence", "CSQLite"]),
    .testTarget(name: "DeskNodesCoreTests", dependencies: ["DeskNodesCore"])
]
#if os(macOS)
products.append(.executable(name: "DeskNodes", targets: ["DeskNodesApp"]))
targets.append(.executableTarget(name: "DeskNodesApp", dependencies: ["DeskNodesCore", "DeskNodesActions", "DeskNodesPersistence"]))
targets.append(.testTarget(name: "DeskNodesAppTests", dependencies: ["DeskNodesApp", "DeskNodesCore"]))
#endif

let package = Package(
    name: "DeskNodes", platforms: [.macOS(.v14)], products: products, targets: targets
)
