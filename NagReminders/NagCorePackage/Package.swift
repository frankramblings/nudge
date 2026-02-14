// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "NagCore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "NagCore",
      targets: ["NagCore"]
    ),
  ],
  targets: [
    .target(
      name: "NagCore",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "NagCoreTests",
      dependencies: ["NagCore"]
    ),
  ]
)
