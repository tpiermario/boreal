// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Boreal", platforms: [.macOS(.v13)],
    products: [.executable(name: "Boreal", targets: ["Boreal"])],
    targets: [
        .target(name: "CSMC", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "Boreal", dependencies: ["CSMC"]),
        .testTarget(name: "BorealTests", dependencies: ["Boreal"])
    ])
