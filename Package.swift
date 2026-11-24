// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniDeck",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MiniDeck", path: "Sources/MiniDeck")]
)
