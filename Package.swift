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
    .package(url: "https://github.com/myfreeweb/SwiftCBOR.git", from: "0.4.4")
  ],
  targets: [
    .target(
      name: "StatiumSwift",
      dependencies: ["SwiftCBOR"]
    ),
    .testTarget(
      name: "StatiumSwiftTests",
      dependencies: ["StatiumSwift", "SwiftCBOR"]
    )
  ]
)
