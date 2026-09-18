// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChromiumExtensionSupport",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ChromiumExtensionSupport", targets: ["ChromiumExtensionSupport"])],
    targets: [
        .target(name: "ChromiumExtensionSupport"),
        .testTarget(name: "ChromiumExtensionSupportTests", dependencies: ["ChromiumExtensionSupport"])
    ]
)
