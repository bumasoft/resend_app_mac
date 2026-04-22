// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ResendMailboxBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ResendMailboxBar",
            targets: ["ResendMailboxBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ResendMailboxBar",
            path: "ResendMailboxBar"
        ),
        .testTarget(
            name: "ResendMailboxBarTests",
            dependencies: ["ResendMailboxBar"],
            path: "ResendMailboxBarTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
