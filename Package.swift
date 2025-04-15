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
  targets: [
    .target(
      name: "StatiumSwift"
    ),
    .testTarget(
      name: "StatiumSwiftTests",
      dependencies: ["StatiumSwift"]
    ),
  ]
)
