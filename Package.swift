// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "DeskNodesCore", targets: ["DeskNodesCore"])]
var targets: [Target] = [
    .target(name: "DeskNodesCore"),
    .testTarget(name: "DeskNodesCoreTests", dependencies: ["DeskNodesCore"])
]
#if os(macOS)
products.append(.executable(name: "DeskNodes", targets: ["DeskNodesApp"]))
targets.append(.executableTarget(name: "DeskNodesApp", dependencies: ["DeskNodesCore"]))
targets.append(.testTarget(name: "DeskNodesAppTests", dependencies: ["DeskNodesApp", "DeskNodesCore"]))
#endif

let package = Package(
    name: "DeskNodes", platforms: [.macOS(.v14)], products: products, targets: targets
)
