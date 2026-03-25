// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "StatiumSwift",
  platforms: [.iOS(.v14), .macOS(.v12)],
  products: [
    .library(
      name: "StatiumSwift",
      targets: ["StatiumSwift"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/niscy-eudiw/SwiftCBOR.git", from: "0.6.3"),
    .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.4.1")),
  ],
  targets: [
    .target(
      name: "StatiumSwift",
      dependencies: ["SwiftCBOR", .product(name: "Collections", package: "swift-collections")]
    ),
    .testTarget(
      name: "StatiumSwiftTests",
      dependencies: ["StatiumSwift", "SwiftCBOR", .product(name: "Collections", package: "swift-collections")]
    )
  ]
)
