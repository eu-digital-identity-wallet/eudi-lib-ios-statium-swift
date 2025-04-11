// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "StatusList",
  platforms: [.iOS(.v14), .macOS(.v12)],
  products: [
    .library(
      name: "eudi-lib-ios-statium-swift",
      targets: ["eudi-lib-ios-statium-swift"]
    )
  ],
  targets: [
    .target(
      name: "eudi-lib-ios-statium-swift"
    ),
    .testTarget(
      name: "eudi-lib-ios-statium-swiftTests",
      dependencies: ["eudi-lib-ios-statium-swift"]
    ),
  ]
)
